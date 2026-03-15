const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("../platform/glfw.zig");
const vk = @import("../platform/volk.zig");
const Window = @import("../platform/Window.zig").Window;
const Renderer = @import("../renderer/Renderer.zig");
const QuadRenderer = @import("../renderer/QuadRenderer.zig");
const TextRenderer = @import("../renderer/TextRenderer.zig");
const TileRenderer = @import("../renderer/TileRenderer.zig");
const Camera = @import("Camera.zig");
const Selection = @import("Selection.zig");
const World = @import("../world/World.zig");
const Ui = @import("Ui.zig");
const file_dialog = @import("file_dialog.zig");

const App = @This();

const State = Ui.State;

window: *Window,
renderer: Renderer,
quad_renderer: QuadRenderer,
text_renderer: TextRenderer,
tile_renderer: TileRenderer,
camera: Camera,
selection: Selection,
world: ?World,
thread_pool: *World.ThreadPool,
allocator: std.mem.Allocator,
io: std.Io,
environ_map: *std.process.Environ.Map,
state: State = .no_world,
mouse_x: f64 = 0,
mouse_y: f64 = 0,
left_down: bool = false,
drag_start_x: i32 = 0,
drag_start_z: i32 = 0,
is_dragging: bool = false,

pub fn init(allocator: std.mem.Allocator, io: std.Io, environ_map: *std.process.Environ.Map, window: *Window) !App {
    var renderer = try Renderer.init(window);
    const quad_renderer = try QuadRenderer.init(&renderer);
    const text_renderer = try TextRenderer.init(&renderer);
    const tile_renderer = try TileRenderer.init(&renderer, allocator);

    // Default thread count: number of CPU cores, minimum 2
    const cpu_count = std.Thread.getCpuCount() catch 4;
    const thread_count: u32 = @intCast(@max(2, cpu_count -| 2));
    const thread_pool = try allocator.create(World.ThreadPool);
    try thread_pool.init(allocator, thread_count);

    const fb = window.getFramebufferSize();

    const app = App{
        .window = window,
        .renderer = renderer,
        .quad_renderer = quad_renderer,
        .text_renderer = text_renderer,
        .tile_renderer = tile_renderer,
        .camera = .{
            .viewport_width = @floatFromInt(fb.width),
            .viewport_height = @floatFromInt(fb.height),
        },
        .selection = Selection.init(allocator),
        .world = null,
        .thread_pool = thread_pool,
        .allocator = allocator,
        .io = io,
        .environ_map = environ_map,
    };

    return app;
}

pub fn setupCallbacks(self: *App) void {
    glfw.setWindowUserPointer(self.window.handle, self);
    glfw.setFramebufferSizeCallback(self.window.handle, framebufferSizeCallback);
    glfw.setScrollCallback(self.window.handle, scrollCallback);
    glfw.setMouseButtonCallback(self.window.handle, mouseButtonCallback);
    glfw.setCursorPosCallback(self.window.handle, cursorPosCallback);
    glfw.setKeyCallback(self.window.handle, keyCallback);
}

pub fn deinit(self: *App) void {
    vk.deviceWaitIdle(self.renderer.device) catch {};
    if (self.world) |*w| w.deinit();
    self.thread_pool.deinit();
    self.allocator.destroy(self.thread_pool);
    self.tile_renderer.deinit();
    self.text_renderer.deinit();
    self.quad_renderer.deinit();
    self.renderer.deinit();
    self.selection.deinit();
    if (self.world) |*w| w.deinit();
}

pub fn openWorld(self: *App, path: []const u8) void {
    if (self.world) |*w| w.deinit();

    const owned_path = self.allocator.dupe(u8, path) catch return;
    self.world = World.init(self.allocator, self.io, owned_path, self.thread_pool);
    self.world.?.scanRegions() catch |err| {
        std.log.err("Failed to scan regions: {}", .{err});
        self.world.?.deinit();
        self.world = null;
        return;
    };

    self.state = .viewing;
    self.selection.clear();
    self.camera.center_x = 0;
    self.camera.center_z = 0;
    self.tile_renderer.clearSlots();

    std.log.info("Opened world: {s} ({} regions, {} chunks)", .{
        World.extractWorldName(path),
        self.world.?.regions.count(),
        self.world.?.totalChunkCount(),
    });
}

pub fn switchDimension(self: *App, dim: World.Dimension) void {
    const world = &(self.world orelse return);
    if (world.dimension == dim) return;

    world.setDimension(dim) catch |err| {
        std.log.err("Failed to switch dimension: {}", .{err});
        return;
    };

    self.selection.clear();
    self.tile_renderer.clearSlots();

    std.log.info("Switched to {s} ({} regions)", .{
        @tagName(dim),
        world.regions.count(),
    });
}

pub fn update(self: *App) !void {
    // Load regions BEFORE starting the frame (uploads use separate command buffers)
    self.processRegionLoading();

    const frame_ctx = try self.renderer.beginFrame();
    const ctx = frame_ctx orelse return;

    const cmd = ctx.cmd;

    // Update camera viewport on resize
    self.camera.setViewportSize(ctx.extent.width, ctx.extent.height);

    // Transition: UNDEFINED → COLOR_ATTACHMENT_OPTIMAL
    const subresource_range: vk.VkImageSubresourceRange = .{
        .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
        .baseMipLevel = 0,
        .levelCount = 1,
        .baseArrayLayer = 0,
        .layerCount = 1,
    };

    const barrier_to_render: vk.VkImageMemoryBarrier = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .srcQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
        .image = ctx.swapchain_image,
        .subresourceRange = subresource_range,
    };

    vk.cmdPipelineBarrier(
        cmd,
        vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        0,
        0,
        null,
        0,
        null,
        1,
        @ptrCast(&barrier_to_render),
    );

    // Begin dynamic rendering
    const clear_value: vk.VkClearColorValue = .{ .float32 = .{ 0.15, 0.15, 0.15, 1.0 } };
    const color_attachment: vk.VkRenderingAttachmentInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .pNext = null,
        .imageView = ctx.swapchain_image_view,
        .imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = 0,
        .resolveImageView = null,
        .resolveImageLayout = 0,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{ .color = clear_value },
    };

    const rendering_info: vk.VkRenderingInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .pNext = null,
        .flags = 0,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = ctx.extent },
        .layerCount = 1,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachments = @ptrCast(&color_attachment),
        .pDepthAttachment = null,
        .pStencilAttachment = null,
    };

    vk.cmdBeginRendering(cmd, &rendering_info);

    // Set dynamic viewport/scissor
    const viewport: vk.VkViewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(ctx.extent.width),
        .height = @floatFromInt(ctx.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vk.cmdSetViewport(cmd, 0, 1, @ptrCast(&viewport));

    const scissor: vk.VkRect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = ctx.extent,
    };
    vk.cmdSetScissor(cmd, 0, 1, @ptrCast(&scissor));

    var view_proj = self.camera.getViewProjection();

    // Render tile map (textured region quads)
    self.tile_renderer.beginFrame();
    self.renderTileMap();
    self.tile_renderer.flush(cmd, &view_proj, self.renderer.current_frame);

    // Reset SSBO offset for this frame (allows multiple flushes without overwriting)
    self.quad_renderer.resetFrame(self.renderer.current_frame);

    // Grid + selection overlays (world-space)
    self.renderLoadingIndicators();
    self.renderGridOverlays();
    self.renderSelection();
    self.renderBoxSelection();
    self.quad_renderer.flush(cmd, &view_proj, self.renderer.current_frame);

    // UI overlay (screen-space)
    const vw: f32 = @floatFromInt(ctx.extent.width);
    const vh: f32 = @floatFromInt(ctx.extent.height);
    var screen_proj = screenOrtho(vw, vh);

    self.text_renderer.beginFrame();
    const world_ptr: ?*const World = if (self.world) |*w| w else null;
    Ui.render(&self.quad_renderer, &self.text_renderer, self.state, world_ptr, &self.camera, &self.selection, self.mouse_x, self.mouse_y, vw, vh, self.thread_pool.threadCount());

    self.quad_renderer.flush(cmd, &screen_proj, self.renderer.current_frame);
    self.text_renderer.flush(cmd, &screen_proj, self.renderer.current_frame);

    vk.cmdEndRendering(cmd);

    // Transition: COLOR_ATTACHMENT_OPTIMAL → PRESENT_SRC_KHR
    const barrier_to_present: vk.VkImageMemoryBarrier = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dstAccessMask = 0,
        .oldLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .newLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .srcQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
        .image = ctx.swapchain_image,
        .subresourceRange = subresource_range,
    };

    vk.cmdPipelineBarrier(
        cmd,
        vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        0,
        0,
        null,
        0,
        null,
        1,
        @ptrCast(&barrier_to_present),
    );

    try self.renderer.endFrame(ctx);
}

fn processRegionLoading(self: *App) void {
    const world = &(self.world orelse return);

    var new_keys: std.ArrayListUnmanaged(World.RegionKey) = .empty;
    defer new_keys.deinit(self.allocator);
    const center_rx: i32 = @intFromFloat(@floor(self.camera.center_x / 32.0));
    const center_rz: i32 = @intFromFloat(@floor(self.camera.center_z / 32.0));
    world.loadRegions(center_rx, center_rz, &new_keys);

    for (new_keys.items) |key| {
        if (world.getRegion(key.x, key.z)) |region| {
            if (region.pixels) |px| {
                // Non-blocking: if GPU is busy with previous upload, try next frame
                if (!self.tile_renderer.uploadRegion(key.x, key.z, px)) break;
            }
        }
    }
}

fn renderTileMap(self: *App) void {
    const world = &(self.world orelse return);

    var region_it = world.regions.iterator();
    while (region_it.next()) |entry| {
        const region = entry.value_ptr;
        if (region.pixels != null) {
            self.tile_renderer.drawRegion(region.rx, region.rz);
        }
    }
}

fn renderLoadingIndicators(self: *App) void {
    const world = &(self.world orelse return);

    const loading_bg = QuadRenderer.Color{ .r = 0.18, .g = 0.18, .b = 0.2, .a = 0.6 };
    const loading_border = QuadRenderer.Color{ .r = 0.3, .g = 0.35, .b = 0.5, .a = 0.5 };
    const border_w: f32 = @floatCast(1.0 / self.camera.scale);

    var region_it = world.regions.iterator();
    while (region_it.next()) |entry| {
        const region = entry.value_ptr;
        if (region.pixels != null) continue; // already loaded

        const rx: f32 = @floatFromInt(@as(i32, region.rx) * 32);
        const rz: f32 = @floatFromInt(@as(i32, region.rz) * 32);

        // Dark background
        self.quad_renderer.drawQuad(rx, rz, 32, 32, loading_bg);

        // Border outline
        self.quad_renderer.drawQuad(rx, rz, 32, border_w, loading_border); // top
        self.quad_renderer.drawQuad(rx, rz + 32 - border_w, 32, border_w, loading_border); // bottom
        self.quad_renderer.drawQuad(rx, rz, border_w, 32, loading_border); // left
        self.quad_renderer.drawQuad(rx + 32 - border_w, rz, border_w, 32, loading_border); // right
    }
}

fn renderGridOverlays(self: *App) void {
    if (self.world == null) return;

    const range = self.camera.visibleChunkRange();
    const line_thickness: f32 = @floatCast(1.0 / self.camera.scale);

    // Region grid (always visible): thick red lines at 32-chunk boundaries
    {
        const region_min_x = @divFloor(range.min_x, 32) * 32;
        const region_max_x = (@divFloor(range.max_x, 32) + 1) * 32;
        const region_min_z = @divFloor(range.min_z, 32) * 32;
        const region_max_z = (@divFloor(range.max_z, 32) + 1) * 32;

        const region_line_w = line_thickness * 3;
        const region_color = QuadRenderer.Color{ .r = 0.8, .g = 0.2, .b = 0.2, .a = 0.7 };

        // Vertical lines
        var x = region_min_x;
        while (x <= region_max_x) : (x += 32) {
            self.quad_renderer.drawQuad(
                @as(f32, @floatFromInt(x)) - region_line_w / 2,
                @floatFromInt(range.min_z),
                region_line_w,
                @floatFromInt(range.max_z - range.min_z),
                region_color,
            );
        }

        // Horizontal lines
        var z = region_min_z;
        while (z <= region_max_z) : (z += 32) {
            self.quad_renderer.drawQuad(
                @floatFromInt(range.min_x),
                @as(f32, @floatFromInt(z)) - region_line_w / 2,
                @floatFromInt(range.max_x - range.min_x),
                region_line_w,
                region_color,
            );
        }
    }

    // Chunk grid (only when zoomed in enough)
    if (self.camera.scale > 4) {
        const chunk_line_w = line_thickness;
        const chunk_color = QuadRenderer.Color{ .r = 0.4, .g = 0.4, .b = 0.4, .a = 0.3 };

        var x = range.min_x;
        while (x <= range.max_x) : (x += 1) {
            if (@mod(x, 32) == 0) continue; // Skip region boundaries
            self.quad_renderer.drawQuad(
                @as(f32, @floatFromInt(x)) - chunk_line_w / 2,
                @floatFromInt(range.min_z),
                chunk_line_w,
                @floatFromInt(range.max_z - range.min_z),
                chunk_color,
            );
        }

        var z = range.min_z;
        while (z <= range.max_z) : (z += 1) {
            if (@mod(z, 32) == 0) continue;
            self.quad_renderer.drawQuad(
                @floatFromInt(range.min_x),
                @as(f32, @floatFromInt(z)) - chunk_line_w / 2,
                @floatFromInt(range.max_x - range.min_x),
                chunk_line_w,
                chunk_color,
            );
        }
    }
}

fn renderSelection(self: *App) void {
    const range = self.camera.visibleChunkRange();
    const selection_color = QuadRenderer.Color{ .r = 0.2, .g = 0.4, .b = 0.9, .a = 0.4 };

    var it = self.selection.chunks.keyIterator();
    while (it.next()) |key| {
        if (key.x < range.min_x or key.x > range.max_x or key.z < range.min_z or key.z > range.max_z) continue;
        self.quad_renderer.drawQuad(
            @floatFromInt(key.x),
            @floatFromInt(key.z),
            1.0,
            1.0,
            selection_color,
        );
    }
}

fn renderBoxSelection(self: *App) void {
    if (!self.selection.box_selecting) return;

    const min_x = @min(self.selection.box_start_x, self.selection.box_end_x);
    const max_x = @max(self.selection.box_start_x, self.selection.box_end_x);
    const min_z = @min(self.selection.box_start_z, self.selection.box_end_z);
    const max_z = @max(self.selection.box_start_z, self.selection.box_end_z);

    const preview_color = QuadRenderer.Color{ .r = 0.3, .g = 0.5, .b = 1.0, .a = 0.25 };

    var cx = min_x;
    while (cx <= max_x) : (cx += 1) {
        var cz = min_z;
        while (cz <= max_z) : (cz += 1) {
            self.quad_renderer.drawQuad(
                @floatFromInt(cx),
                @floatFromInt(cz),
                1.0,
                1.0,
                preview_color,
            );
        }
    }
}

fn screenOrtho(width: f32, height: f32) [16]f32 {
    // Column-major orthographic projection: (0,0) top-left, (w,h) bottom-right
    return .{
        2.0 / width, 0,             0,  0,
        0,           2.0 / height,  0,  0,
        0,           0,            -1,  0,
        -1,          -1,            0,  1,
    };
}

// GLFW Callbacks
fn framebufferSizeCallback(glfw_window: ?*glfw.Window, _: c_int, _: c_int) callconv(.c) void {
    const app = glfw.getWindowUserPointer(glfw_window.?, App) orelse return;
    app.renderer.framebuffer_resized = true;
}

fn scrollCallback(glfw_window: ?*glfw.Window, _: f64, yoffset: f64) callconv(.c) void {
    const app = glfw.getWindowUserPointer(glfw_window.?, App) orelse return;
    app.camera.zoom(yoffset, app.mouse_x, app.mouse_y);
}

fn mouseButtonCallback(glfw_window: ?*glfw.Window, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    const app = glfw.getWindowUserPointer(glfw_window.?, App) orelse return;

    if (button == glfw.GLFW_MOUSE_BUTTON_MIDDLE or button == glfw.GLFW_MOUSE_BUTTON_RIGHT) {
        if (action == glfw.GLFW_PRESS) {
            app.camera.startPan(app.mouse_x, app.mouse_y);
        } else if (action == glfw.GLFW_RELEASE) {
            app.camera.endPan();
        }
    }

    if (button == glfw.GLFW_MOUSE_BUTTON_LEFT) {
        if (action == glfw.GLFW_PRESS) {
            app.left_down = true;
            app.is_dragging = false;
            const world_pos = app.camera.screenToWorld(app.mouse_x, app.mouse_y);
            app.drag_start_x = @intFromFloat(@floor(world_pos.x));
            app.drag_start_z = @intFromFloat(@floor(world_pos.z));
        } else if (action == glfw.GLFW_RELEASE) {
            if (app.is_dragging) {
                app.selection.endBoxSelect();
            } else {
                // Single click
                const world_pos = app.camera.screenToWorld(app.mouse_x, app.mouse_y);
                const cx: i32 = @intFromFloat(@floor(world_pos.x));
                const cz: i32 = @intFromFloat(@floor(world_pos.z));

                if (mods & glfw.GLFW_MOD_SHIFT != 0) {
                    // Shift+click: toggle region
                    const rx = @divFloor(cx, 32);
                    const rz = @divFloor(cz, 32);
                    app.selection.toggleRegion(rx, rz);
                } else {
                    app.selection.toggle(cx, cz);
                }
        
            }
            app.left_down = false;
            app.is_dragging = false;
        }
    }

    if (button == glfw.GLFW_MOUSE_BUTTON_RIGHT and action == glfw.GLFW_PRESS) {
        if (app.selection.count() > 0) {
            app.selection.clear();
    
        }
    }
}

fn cursorPosCallback(glfw_window: ?*glfw.Window, xpos: f64, ypos: f64) callconv(.c) void {
    const app = glfw.getWindowUserPointer(glfw_window.?, App) orelse return;
    app.mouse_x = xpos;
    app.mouse_y = ypos;

    app.camera.updatePan(xpos, ypos);

    // Box selection drag
    if (app.left_down) {
        const world_pos = app.camera.screenToWorld(xpos, ypos);
        const cx: i32 = @intFromFloat(@floor(world_pos.x));
        const cz: i32 = @intFromFloat(@floor(world_pos.z));

        if (!app.is_dragging and (cx != app.drag_start_x or cz != app.drag_start_z)) {
            app.is_dragging = true;
            app.selection.startBoxSelect(app.drag_start_x, app.drag_start_z);
        }

        if (app.is_dragging) {
            app.selection.updateBoxSelect(cx, cz);
        }
    }
}

fn keyCallback(glfw_window: ?*glfw.Window, key: c_int, _: c_int, action: c_int, mods: c_int) callconv(.c) void {
    const app = glfw.getWindowUserPointer(glfw_window.?, App) orelse return;

    if (action != glfw.GLFW_PRESS) return;

    switch (app.state) {
        .confirm_delete => {
            if (key == glfw.GLFW_KEY_Y) {
                // Perform deletion
                if (app.world) |*world| {
                    const chunks = app.selection.getSelectedChunks(app.allocator) catch return;
                    defer app.allocator.free(chunks);

                    const deleted = world.deleteChunks(chunks) catch |err| {
                        std.log.err("Delete failed: {}", .{err});
                        app.state = .viewing;
                
                        return;
                    };

                    std.log.info("Deleted {} chunks", .{deleted});
                    app.selection.clear();
                }
                app.state = .viewing;
        
            } else if (key == glfw.GLFW_KEY_N or key == glfw.GLFW_KEY_ESCAPE) {
                app.state = .viewing;
        
            }
        },
        .viewing => {
            if (key == glfw.GLFW_KEY_DELETE and app.selection.count() > 0) {
                app.state = .confirm_delete;
        
            } else if (key == glfw.GLFW_KEY_ESCAPE) {
                if (app.selection.count() > 0) {
                    app.selection.clear();
            
                }
            } else if (key == glfw.GLFW_KEY_O and (mods & glfw.GLFW_MOD_CONTROL != 0)) {
                // Ctrl+O: Open folder dialog
                const path = file_dialog.openFolderDialog(app.allocator, app.io, app.environ_map) catch return;
                if (path) |p| {
                    app.openWorld(p);
                    app.allocator.free(p);
                }
            } else if (key == glfw.GLFW_KEY_EQUAL) {
                // + key: increase thread count
                const cur = app.thread_pool.threadCount();
                app.thread_pool.resize(@min(cur + 1, 64));
            } else if (key == glfw.GLFW_KEY_MINUS) {
                // - key: decrease thread count
                const cur = app.thread_pool.threadCount();
                if (cur > 1) app.thread_pool.resize(cur - 1);
            } else if (key == glfw.GLFW_KEY_1) {
                app.switchDimension(.overworld);
            } else if (key == glfw.GLFW_KEY_2) {
                app.switchDimension(.nether);
            } else if (key == glfw.GLFW_KEY_3) {
                app.switchDimension(.the_end);
            } else if (key == glfw.GLFW_KEY_G and (mods & glfw.GLFW_MOD_CONTROL != 0)) {
                // Ctrl+G: Goto - read coordinates from stdin via Io
                std.log.info("Enter coordinates (chunk X Z) in console:", .{});
                const stdin_file = std.Io.File.stdin();
                var buf: [256]u8 = undefined;
                var iov = [_][]u8{buf[0..]};
                const n = stdin_file.readStreaming(app.io, &iov) catch {
                    std.log.warn("Ctrl+G requires -Dconsole=true", .{});
                    return;
                };
                if (n == 0) return;
                const trimmed = std.mem.trim(u8, buf[0..n], " \r\n\t");
                var split = std.mem.splitScalar(u8, trimmed, ' ');
                const x_str = split.next() orelse return;
                const z_str = split.next() orelse return;
                const x = std.fmt.parseInt(i32, x_str, 10) catch return;
                const z = std.fmt.parseInt(i32, z_str, 10) catch return;
                app.camera.goTo(@floatFromInt(x), @floatFromInt(z));
        
            }
        },
        .no_world => {
            if (key == glfw.GLFW_KEY_O and (mods & glfw.GLFW_MOD_CONTROL != 0)) {
                const path = file_dialog.openFolderDialog(app.allocator, app.io, app.environ_map) catch return;
                if (path) |p| {
                    app.openWorld(p);
                    app.allocator.free(p);
                }
            }
        },
    }
}
