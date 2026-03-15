const std = @import("std");
const vk = @import("../platform/volk.zig");
const shaderc = @import("../platform/shaderc.zig");
const freetype = @import("../platform/freetype.zig");
const Renderer = @import("Renderer.zig");

const TextRenderer = @This();

const MAX_CHARS = 4096;
const VERTICES_PER_CHAR = 6;
const MAX_VERTICES = MAX_CHARS * VERTICES_PER_CHAR;

const FONT_SIZE = 32;
const ATLAS_COLS = 16;
const ATLAS_ROWS = 6; // covers ASCII 32-127 (96 chars)
const FIRST_CHAR = 32;
const LAST_CHAR = 127;
const NUM_CHARS = LAST_CHAR - FIRST_CHAR;

pub const TextVertex = extern struct {
    px: f32,
    py: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const Color = struct {
    r: f32 = 1.0,
    g: f32 = 1.0,
    b: f32 = 1.0,
    a: f32 = 1.0,
};

const GlyphMetrics = struct {
    advance_x: f32,
    bearing_x: f32,
    bearing_y: f32,
    width: f32,
    height: f32,
};

const VERTEX_SIZE = @sizeOf(TextVertex);
const BUFFER_SIZE = MAX_VERTICES * VERTEX_SIZE;

pipeline: vk.VkPipeline = null,
pipeline_layout: vk.VkPipelineLayout = null,
descriptor_set_layout: vk.VkDescriptorSetLayout = null,
descriptor_pool: vk.VkDescriptorPool = null,
descriptor_sets: [Renderer.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet = .{null} ** Renderer.MAX_FRAMES_IN_FLIGHT,

vertex_buffer: vk.VkBuffer = null,
vertex_memory: vk.VkDeviceMemory = null,
mapped_data: ?*anyopaque = null,
vertex_count: u32 = 0,

font_image: vk.VkImage = null,
font_image_view: vk.VkImageView = null,
font_memory: vk.VkDeviceMemory = null,
font_sampler: vk.VkSampler = null,

device: vk.VkDevice = null,
swapchain_format: vk.VkFormat = vk.VK_FORMAT_B8G8R8A8_SRGB,

// Per-glyph metrics
glyph_metrics: [NUM_CHARS]GlyphMetrics = undefined,
cell_width: u32 = 0,
cell_height: u32 = 0,
atlas_width: u32 = 0,
atlas_height: u32 = 0,
font_ascender: f32 = 0,
font_line_height: f32 = 0,

pub fn init(renderer: *Renderer) !TextRenderer {
    var self = TextRenderer{};
    self.device = renderer.device;
    self.swapchain_format = renderer.swapchain_format;

    try self.createFontTexture(renderer);
    try self.createVertexBuffer(renderer);
    try self.createDescriptors();
    try self.createPipeline();

    return self;
}

pub fn deinit(self: *TextRenderer) void {
    if (self.descriptor_pool != null) vk.destroyDescriptorPool(self.device, self.descriptor_pool, null);
    if (self.descriptor_set_layout != null) vk.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
    if (self.pipeline != null) vk.destroyPipeline(self.device, self.pipeline, null);
    if (self.pipeline_layout != null) vk.destroyPipelineLayout(self.device, self.pipeline_layout, null);
    if (self.vertex_buffer != null) vk.destroyBuffer(self.device, self.vertex_buffer, null);
    if (self.vertex_memory != null) vk.freeMemory(self.device, self.vertex_memory, null);
    if (self.font_sampler != null) vk.destroySampler(self.device, self.font_sampler, null);
    if (self.font_image_view != null) vk.destroyImageView(self.device, self.font_image_view, null);
    if (self.font_image != null) vk.destroyImage(self.device, self.font_image, null);
    if (self.font_memory != null) vk.freeMemory(self.device, self.font_memory, null);
}

pub fn beginFrame(self: *TextRenderer) void {
    self.vertex_count = 0;
}

pub fn drawText(self: *TextRenderer, text: []const u8, x: f32, y: f32, scale: f32, color: Color) void {
    var cursor_x = x;

    for (text) |ch| {
        if (self.vertex_count + VERTICES_PER_CHAR > MAX_VERTICES) return;
        if (ch < FIRST_CHAR or ch >= LAST_CHAR) {
            cursor_x += self.glyph_metrics[0].advance_x * scale; // space width for unknown chars
            continue;
        }

        const idx = ch - FIRST_CHAR;
        const m = self.glyph_metrics[idx];

        const col: f32 = @floatFromInt(idx % ATLAS_COLS);
        const row: f32 = @floatFromInt(idx / ATLAS_COLS);
        const cw: f32 = @floatFromInt(self.cell_width);
        const ch_f: f32 = @floatFromInt(self.cell_height);
        const aw: f32 = @floatFromInt(self.atlas_width);
        const ah: f32 = @floatFromInt(self.atlas_height);

        const tex_u0 = (col * cw) / aw;
        const tex_v0 = (row * ch_f) / ah;
        const tex_u1 = (col * cw + m.width) / aw;
        const tex_v1 = (row * ch_f + m.height) / ah;

        const gx = @round(cursor_x + m.bearing_x * scale);
        const gy = @round(y + (self.font_ascender - m.bearing_y) * scale);
        const gw = @ceil(m.width * scale);
        const gh = @ceil(m.height * scale);

        const base: [*]TextVertex = @ptrCast(@alignCast(self.mapped_data orelse return));
        const verts = base[self.vertex_count..][0..6];

        verts[0] = .{ .px = gx, .py = gy, .u = tex_u0, .v = tex_v0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[1] = .{ .px = gx + gw, .py = gy, .u = tex_u1, .v = tex_v0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[2] = .{ .px = gx, .py = gy + gh, .u = tex_u0, .v = tex_v1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[3] = .{ .px = gx + gw, .py = gy, .u = tex_u1, .v = tex_v0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[4] = .{ .px = gx + gw, .py = gy + gh, .u = tex_u1, .v = tex_v1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[5] = .{ .px = gx, .py = gy + gh, .u = tex_u0, .v = tex_v1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };

        self.vertex_count += VERTICES_PER_CHAR;
        cursor_x += m.advance_x * scale;
    }
}

pub fn drawFmt(self: *TextRenderer, x: f32, y: f32, scale: f32, color: Color, comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
    self.drawText(text, x, y, scale, color);
}

pub fn flush(self: *TextRenderer, cmd: vk.VkCommandBuffer, screen_proj: *const [16]f32, frame_index: u32) void {
    if (self.vertex_count == 0) return;

    vk.cmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);
    vk.cmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, @ptrCast(&self.descriptor_sets[frame_index]), 0, null);
    vk.cmdPushConstants(cmd, self.pipeline_layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, screen_proj);
    vk.cmdDraw(cmd, self.vertex_count, 1, 0, 0);
}

pub fn measureText(self: *const TextRenderer, text: []const u8, scale: f32) f32 {
    var w: f32 = 0;
    for (text) |ch| {
        if (ch < FIRST_CHAR or ch >= LAST_CHAR) {
            w += self.glyph_metrics[0].advance_x * scale;
        } else {
            w += self.glyph_metrics[ch - FIRST_CHAR].advance_x * scale;
        }
    }
    return w;
}

pub fn measureFmt(self: *const TextRenderer, scale: f32, comptime fmt: []const u8, args: anytype) f32 {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return 0;
    return self.measureText(text, scale);
}

fn createFontTexture(self: *TextRenderer, renderer: *Renderer) !void {
    // Initialize FreeType and load system font
    const ft_lib = try freetype.initLibrary();
    defer freetype.doneLibrary(ft_lib);

    const font_path = freetype.findSystemFont() orelse return error.InitializationFailed;
    const face = try freetype.newFace(ft_lib, font_path);
    defer freetype.doneFace(face);

    try freetype.setPixelSizes(face, 0, FONT_SIZE);

    // First pass: render all glyphs to find max cell size
    var max_w: u32 = 0;
    var max_h: u32 = 0;
    var max_bearing_y: i32 = 0;
    var max_descent: i32 = 0;

    for (0..NUM_CHARS) |i| {
        const ch: u32 = @intCast(FIRST_CHAR + i);
        freetype.loadChar(face, ch, freetype.FT_LOAD_RENDER) catch continue;
        const info = freetype.getGlyphInfo(face);

        self.glyph_metrics[i] = .{
            .advance_x = @floatFromInt(info.advance_x),
            .bearing_x = @floatFromInt(info.bearing_x),
            .bearing_y = @floatFromInt(info.bearing_y),
            .width = @floatFromInt(info.width),
            .height = @floatFromInt(info.height),
        };

        if (info.width > max_w) max_w = info.width;
        if (info.height > max_h) max_h = info.height;
        if (info.bearing_y > max_bearing_y) max_bearing_y = info.bearing_y;
        const descent = @as(i32, @intCast(info.height)) - info.bearing_y;
        if (descent > max_descent) max_descent = descent;
    }

    self.cell_width = max_w + 2;
    self.cell_height = max_h + 2;
    self.atlas_width = self.cell_width * ATLAS_COLS;
    self.atlas_height = self.cell_height * ATLAS_ROWS;
    self.font_ascender = @floatFromInt(max_bearing_y);
    self.font_line_height = @floatFromInt(max_bearing_y + max_descent);

    // Allocate atlas pixel data
    const atlas_size: usize = self.atlas_width * self.atlas_height;
    const atlas_data = std.heap.page_allocator.alloc(u8, atlas_size) catch return error.OutOfHostMemory;
    defer std.heap.page_allocator.free(atlas_data);
    @memset(atlas_data, 0);

    // Second pass: render glyphs into atlas
    for (0..NUM_CHARS) |i| {
        const ch: u32 = @intCast(FIRST_CHAR + i);
        freetype.loadChar(face, ch, freetype.FT_LOAD_RENDER) catch continue;
        const info = freetype.getGlyphInfo(face);

        if (info.width == 0 or info.height == 0) continue;

        const col = i % ATLAS_COLS;
        const row = i / ATLAS_COLS;
        const base_x = col * self.cell_width;
        const base_y = row * self.cell_height;

        // Copy glyph bitmap into atlas cell
        for (0..info.height) |gy| {
            for (0..info.width) |gx| {
                const src_idx = gy * @as(usize, @intCast(info.pitch)) + gx;
                const dst_x = base_x + gx;
                const dst_y = base_y + gy;
                if (dst_x < self.atlas_width and dst_y < self.atlas_height) {
                    atlas_data[dst_y * self.atlas_width + dst_x] = info.bitmap[src_idx];
                }
            }
        }
    }

    std.log.info("Font atlas created: {}x{} (cell {}x{}) from {s}", .{
        self.atlas_width, self.atlas_height, self.cell_width, self.cell_height,
        std.mem.span(font_path),
    });

    // Upload atlas to GPU
    try self.uploadAtlas(renderer, atlas_data, self.atlas_width, self.atlas_height);
}

fn uploadAtlas(self: *TextRenderer, renderer: *Renderer, atlas_data: []const u8, width: u32, height: u32) !void {
    const atlas_size: u64 = @intCast(atlas_data.len);

    // Staging buffer
    const staging_buffer = try vk.createBuffer(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = null, .flags = 0,
        .size = atlas_size,
        .usage = vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0, .pQueueFamilyIndices = null,
    }, null);
    defer vk.destroyBuffer(self.device, staging_buffer, null);

    var staging_mem_req: vk.VkMemoryRequirements = undefined;
    vk.getBufferMemoryRequirements(self.device, staging_buffer, &staging_mem_req);

    var mem_properties: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.getPhysicalDeviceMemoryProperties(renderer.physical_device, &mem_properties);

    const staging_memory = try vk.allocateMemory(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = null,
        .allocationSize = staging_mem_req.size,
        .memoryTypeIndex = findMemoryType(mem_properties, staging_mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.NoSuitableDevice,
    }, null);
    defer vk.freeMemory(self.device, staging_memory, null);

    try vk.bindBufferMemory(self.device, staging_buffer, staging_memory, 0);

    var mapped: ?*anyopaque = null;
    try vk.mapMemory(self.device, staging_memory, 0, atlas_size, 0, &mapped);
    const dst: [*]u8 = @ptrCast(mapped orelse return error.MemoryMapFailed);
    @memcpy(dst[0..atlas_data.len], atlas_data);

    // Create image
    self.font_image = try vk.createImage(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .pNext = null, .flags = 0,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = vk.VK_FORMAT_R8_UNORM,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1, .arrayLayers = 1,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
        .usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0, .pQueueFamilyIndices = null,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    }, null);

    var img_mem_req: vk.VkMemoryRequirements = undefined;
    vk.getImageMemoryRequirements(self.device, self.font_image, &img_mem_req);

    self.font_memory = try vk.allocateMemory(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = null,
        .allocationSize = img_mem_req.size,
        .memoryTypeIndex = findMemoryType(mem_properties, img_mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.NoSuitableDevice,
    }, null);
    try vk.bindImageMemory(self.device, self.font_image, self.font_memory, 0);

    // Upload via one-shot command buffer
    try self.execUpload(renderer, staging_buffer, width, height);

    // Image view
    self.font_image_view = try vk.createImageView(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .pNext = null, .flags = 0,
        .image = self.font_image, .viewType = vk.VK_IMAGE_VIEW_TYPE_2D, .format = vk.VK_FORMAT_R8_UNORM,
        .components = .{ .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY },
        .subresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
    }, null);

    // Sampler — linear filtering for smooth text
    self.font_sampler = try vk.createSampler(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, .pNext = null, .flags = 0,
        .magFilter = vk.c.VK_FILTER_LINEAR,
        .minFilter = vk.c.VK_FILTER_LINEAR,
        .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .mipLodBias = 0, .anisotropyEnable = vk.VK_FALSE, .maxAnisotropy = 1,
        .compareEnable = vk.VK_FALSE, .compareOp = 0,
        .minLod = 0, .maxLod = 0,
        .borderColor = vk.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = vk.VK_FALSE,
    }, null);
}

fn execUpload(self: *TextRenderer, renderer: *Renderer, staging_buffer: vk.VkBuffer, width: u32, height: u32) !void {
    var cmd: vk.VkCommandBuffer = null;
    try vk.allocateCommandBuffers(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .pNext = null,
        .commandPool = renderer.command_pool, .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1,
    }, @ptrCast(&cmd));

    try vk.beginCommandBuffer(cmd, &.{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, .pNext = null,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, .pInheritanceInfo = null,
    });

    const subresource_range: vk.VkImageSubresourceRange = .{
        .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1,
    };

    // UNDEFINED → TRANSFER_DST
    vk.cmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, @ptrCast(&vk.VkImageMemoryBarrier{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .pNext = null,
        .srcAccessMask = 0, .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        .oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = self.font_image, .subresourceRange = subresource_range,
    }));

    // Copy
    vk.cmdCopyBufferToImage(cmd, staging_buffer, self.font_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, @ptrCast(&vk.VkBufferImageCopy{
        .bufferOffset = 0, .bufferRowLength = 0, .bufferImageHeight = 0,
        .imageSubresource = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = width, .height = height, .depth = 1 },
    }));

    // TRANSFER_DST → SHADER_READ_ONLY
    vk.cmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, @ptrCast(&vk.VkImageMemoryBarrier{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .pNext = null,
        .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT, .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT,
        .oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, .newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = self.font_image, .subresourceRange = subresource_range,
    }));

    try vk.endCommandBuffer(cmd);

    try vk.queueSubmit(renderer.graphics_queue, 1, @ptrCast(&vk.VkSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, .pNext = null,
        .waitSemaphoreCount = 0, .pWaitSemaphores = null, .pWaitDstStageMask = null,
        .commandBufferCount = 1, .pCommandBuffers = @ptrCast(&cmd),
        .signalSemaphoreCount = 0, .pSignalSemaphores = null,
    }), null);
    try vk.deviceWaitIdle(self.device);
}

fn createVertexBuffer(self: *TextRenderer, renderer: *Renderer) !void {
    self.vertex_buffer = try vk.createBuffer(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .pNext = null, .flags = 0,
        .size = BUFFER_SIZE, .usage = vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE, .queueFamilyIndexCount = 0, .pQueueFamilyIndices = null,
    }, null);

    var mem_req: vk.VkMemoryRequirements = undefined;
    vk.getBufferMemoryRequirements(self.device, self.vertex_buffer, &mem_req);

    var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.getPhysicalDeviceMemoryProperties(renderer.physical_device, &mem_props);

    self.vertex_memory = try vk.allocateMemory(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = null,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = findMemoryType(mem_props, mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.NoSuitableDevice,
    }, null);
    try vk.bindBufferMemory(self.device, self.vertex_buffer, self.vertex_memory, 0);
    try vk.mapMemory(self.device, self.vertex_memory, 0, vk.VK_WHOLE_SIZE, 0, &self.mapped_data);
}

fn createDescriptors(self: *TextRenderer) !void {
    const bindings = [2]vk.VkDescriptorSetLayoutBinding{
        .{ .binding = 0, .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, .pImmutableSamplers = null },
        .{ .binding = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1, .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .pImmutableSamplers = null },
    };

    self.descriptor_set_layout = try vk.createDescriptorSetLayout(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .pNext = null, .flags = 0, .bindingCount = 2, .pBindings = &bindings,
    }, null);

    const pool_sizes = [2]vk.VkDescriptorPoolSize{
        .{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = Renderer.MAX_FRAMES_IN_FLIGHT },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = Renderer.MAX_FRAMES_IN_FLIGHT },
    };

    self.descriptor_pool = try vk.createDescriptorPool(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .pNext = null, .flags = 0,
        .maxSets = Renderer.MAX_FRAMES_IN_FLIGHT, .poolSizeCount = 2, .pPoolSizes = &pool_sizes,
    }, null);

    var layouts: [Renderer.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSetLayout = undefined;
    for (&layouts) |*l| l.* = self.descriptor_set_layout;

    try vk.allocateDescriptorSets(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .pNext = null,
        .descriptorPool = self.descriptor_pool, .descriptorSetCount = Renderer.MAX_FRAMES_IN_FLIGHT, .pSetLayouts = &layouts,
    }, &self.descriptor_sets);

    for (0..Renderer.MAX_FRAMES_IN_FLIGHT) |i| {
        const buffer_desc: vk.VkDescriptorBufferInfo = .{ .buffer = self.vertex_buffer, .offset = 0, .range = vk.VK_WHOLE_SIZE };
        const image_desc: vk.VkDescriptorImageInfo = .{ .sampler = self.font_sampler, .imageView = self.font_image_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };

        const writes = [2]vk.VkWriteDescriptorSet{
            .{ .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .pNext = null, .dstSet = self.descriptor_sets[i], .dstBinding = 0, .dstArrayElement = 0, .descriptorCount = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pImageInfo = null, .pBufferInfo = @ptrCast(&buffer_desc), .pTexelBufferView = null },
            .{ .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .pNext = null, .dstSet = self.descriptor_sets[i], .dstBinding = 1, .dstArrayElement = 0, .descriptorCount = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = @ptrCast(&image_desc), .pBufferInfo = null, .pTexelBufferView = null },
        };
        vk.updateDescriptorSets(self.device, 2, &writes, 0, null);
    }
}

fn createPipeline(self: *TextRenderer) !void {
    const vert_source = @embedFile("shaders/text.vert");
    const frag_source = @embedFile("shaders/text.frag");

    const compiler = shaderc.compiler_initialize();
    if (compiler == null) return error.InitializationFailed;
    defer shaderc.compiler_release(compiler);

    const vert_result = shaderc.compile_into_spv(compiler, @ptrCast(vert_source.ptr), vert_source.len, shaderc.shaderc_vertex_shader, "text.vert", "main", null);
    defer shaderc.result_release(vert_result);
    if (shaderc.result_get_compilation_status(vert_result) != shaderc.shaderc_compilation_status_success) {
        std.log.err("Text vertex shader failed: {s}", .{shaderc.result_get_error_message(vert_result)});
        return error.InitializationFailed;
    }

    const frag_result = shaderc.compile_into_spv(compiler, @ptrCast(frag_source.ptr), frag_source.len, shaderc.shaderc_fragment_shader, "text.frag", "main", null);
    defer shaderc.result_release(frag_result);
    if (shaderc.result_get_compilation_status(frag_result) != shaderc.shaderc_compilation_status_success) {
        std.log.err("Text fragment shader failed: {s}", .{shaderc.result_get_error_message(frag_result)});
        return error.InitializationFailed;
    }

    const vert_module = try vk.createShaderModule(self.device, &.{ .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .pNext = null, .flags = 0, .codeSize = shaderc.result_get_length(vert_result), .pCode = @ptrCast(@alignCast(shaderc.result_get_bytes(vert_result))) }, null);
    defer vk.destroyShaderModule(self.device, vert_module, null);

    const frag_module = try vk.createShaderModule(self.device, &.{ .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .pNext = null, .flags = 0, .codeSize = shaderc.result_get_length(frag_result), .pCode = @ptrCast(@alignCast(shaderc.result_get_bytes(frag_result))) }, null);
    defer vk.destroyShaderModule(self.device, frag_module, null);

    const shader_stages = [2]vk.VkPipelineShaderStageCreateInfo{
        .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .pNext = null, .flags = 0, .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = vert_module, .pName = "main", .pSpecializationInfo = null },
        .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .pNext = null, .flags = 0, .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = frag_module, .pName = "main", .pSpecializationInfo = null },
    };

    const color_blend_attachment: vk.VkPipelineColorBlendAttachmentState = .{
        .blendEnable = vk.VK_TRUE,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA, .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE, .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO, .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
    };

    const dynamic_states = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
    const push_constant_range: vk.VkPushConstantRange = .{ .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, .offset = 0, .size = 64 };

    self.pipeline_layout = try vk.createPipelineLayout(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .pNext = null, .flags = 0,
        .setLayoutCount = 1, .pSetLayouts = @ptrCast(&self.descriptor_set_layout),
        .pushConstantRangeCount = 1, .pPushConstantRanges = @ptrCast(&push_constant_range),
    }, null);

    const rendering_info: vk.VkPipelineRenderingCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO, .pNext = null, .viewMask = 0, .colorAttachmentCount = 1, .pColorAttachmentFormats = @ptrCast(&self.swapchain_format), .depthAttachmentFormat = 0, .stencilAttachmentFormat = 0 };

    const pipeline_info: vk.VkGraphicsPipelineCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, .pNext = &rendering_info, .flags = 0,
        .stageCount = 2, .pStages = &shader_stages,
        .pVertexInputState = &vk.VkPipelineVertexInputStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, .pNext = null, .flags = 0, .vertexBindingDescriptionCount = 0, .pVertexBindingDescriptions = null, .vertexAttributeDescriptionCount = 0, .pVertexAttributeDescriptions = null },
        .pInputAssemblyState = &vk.VkPipelineInputAssemblyStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .pNext = null, .flags = 0, .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, .primitiveRestartEnable = vk.VK_FALSE },
        .pTessellationState = null,
        .pViewportState = &vk.VkPipelineViewportStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .pNext = null, .flags = 0, .viewportCount = 1, .pViewports = null, .scissorCount = 1, .pScissors = null },
        .pRasterizationState = &vk.VkPipelineRasterizationStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .pNext = null, .flags = 0, .depthClampEnable = vk.VK_FALSE, .rasterizerDiscardEnable = vk.VK_FALSE, .polygonMode = vk.VK_POLYGON_MODE_FILL, .cullMode = vk.VK_CULL_MODE_NONE, .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE, .depthBiasEnable = vk.VK_FALSE, .depthBiasConstantFactor = 0, .depthBiasClamp = 0, .depthBiasSlopeFactor = 0, .lineWidth = 1.0 },
        .pMultisampleState = &vk.VkPipelineMultisampleStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .pNext = null, .flags = 0, .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT, .sampleShadingEnable = vk.VK_FALSE, .minSampleShading = 1.0, .pSampleMask = null, .alphaToCoverageEnable = vk.VK_FALSE, .alphaToOneEnable = vk.VK_FALSE },
        .pDepthStencilState = null,
        .pColorBlendState = &vk.VkPipelineColorBlendStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .pNext = null, .flags = 0, .logicOpEnable = vk.VK_FALSE, .logicOp = 0, .attachmentCount = 1, .pAttachments = @ptrCast(&color_blend_attachment), .blendConstants = .{ 0, 0, 0, 0 } },
        .pDynamicState = &vk.VkPipelineDynamicStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .pNext = null, .flags = 0, .dynamicStateCount = dynamic_states.len, .pDynamicStates = &dynamic_states },
        .layout = self.pipeline_layout, .renderPass = null, .subpass = 0, .basePipelineHandle = null, .basePipelineIndex = -1,
    };

    try vk.createGraphicsPipelines(self.device, null, 1, @ptrCast(&pipeline_info), null, @ptrCast(&self.pipeline));
    std.log.info("TextRenderer pipeline created", .{});
}

fn findMemoryType(mem_properties: vk.VkPhysicalDeviceMemoryProperties, type_filter: u32, properties: u32) ?u32 {
    for (0..mem_properties.memoryTypeCount) |i| {
        const idx: u5 = @intCast(i);
        if ((type_filter & (@as(u32, 1) << idx)) != 0 and
            (mem_properties.memoryTypes[i].propertyFlags & properties) == properties)
            return @intCast(i);
    }
    return null;
}
