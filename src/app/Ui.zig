const std = @import("std");
const QuadRenderer = @import("../renderer/QuadRenderer.zig");
const TextRenderer = @import("../renderer/TextRenderer.zig");
const Camera = @import("Camera.zig");
const Selection = @import("Selection.zig");
const World = @import("../world/World.zig");

const Ui = @This();

const TOOLBAR_HEIGHT: f32 = 36;
const STATUSBAR_HEIGHT: f32 = 32;
const PADDING: f32 = 10;
const TEXT_SCALE: f32 = 0.5;
const SMALL_TEXT_SCALE: f32 = 0.42;

const BG_COLOR = QuadRenderer.Color{ .r = 0.12, .g = 0.12, .b = 0.12, .a = 0.92 };
const TEXT_COLOR = TextRenderer.Color{ .r = 0.9, .g = 0.9, .b = 0.9, .a = 1.0 };
const DIM_TEXT_COLOR = TextRenderer.Color{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1.0 };
const ACCENT_COLOR = TextRenderer.Color{ .r = 0.4, .g = 0.7, .b = 1.0, .a = 1.0 };
const WARN_COLOR = TextRenderer.Color{ .r = 1.0, .g = 0.4, .b = 0.3, .a = 1.0 };

pub const State = enum {
    no_world,
    viewing,
    confirm_delete,
};

pub fn render(
    qr: *QuadRenderer,
    tr: *TextRenderer,
    state: State,
    world: ?*const World,
    camera: *const Camera,
    selection: *const Selection,
    mouse_x: f64,
    mouse_y: f64,
    viewport_w: f32,
    viewport_h: f32,
    thread_count: u32,
    hover_block: []const u8,
) void {
    renderToolbar(qr, tr, state, world, selection, viewport_w);
    renderStatusBar(qr, tr, state, world, camera, selection, mouse_x, mouse_y, viewport_w, viewport_h, thread_count, hover_block);
}

const TAB_COLOR = QuadRenderer.Color{ .r = 0.22, .g = 0.22, .b = 0.24, .a = 0.95 };
const TAB_ACTIVE_COLOR = QuadRenderer.Color{ .r = 0.32, .g = 0.32, .b = 0.38, .a = 1.0 };
const TAB_TEXT_INACTIVE = TextRenderer.Color{ .r = 0.75, .g = 0.75, .b = 0.75, .a = 1.0 };
const TAB_TEXT_ACTIVE = TextRenderer.Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };

fn renderToolbar(
    qr: *QuadRenderer,
    tr: *TextRenderer,
    state: State,
    world: ?*const World,
    selection: *const Selection,
    viewport_w: f32,
) void {
    qr.drawQuad(0, 0, viewport_w, TOOLBAR_HEIGHT, BG_COLOR);

    const text_y: f32 = (TOOLBAR_HEIGHT - tr.font_line_height * TEXT_SCALE) / 2;

    if (state == .confirm_delete) {
        const selected = selection.count();
        tr.drawFmt(PADDING, text_y, TEXT_SCALE, WARN_COLOR, "DELETE {d} chunks? Press Y to confirm, Esc to cancel", .{selected});
        return;
    }

    // Left: app name + world name
    tr.drawText("Unchunked", PADDING, text_y, TEXT_SCALE, ACCENT_COLOR);
    var x_pos = PADDING + tr.measureText("Unchunked", TEXT_SCALE);

    if (world) |w| {
        const name = World.extractWorldName(w.path);
        x_pos += PADDING;
        tr.drawText("|", x_pos, text_y, TEXT_SCALE, DIM_TEXT_COLOR);
        x_pos += tr.measureText("|", TEXT_SCALE) + PADDING;
        tr.drawText(name, x_pos, text_y, TEXT_SCALE, TEXT_COLOR);
        x_pos += tr.measureText(name, TEXT_SCALE);

        // Dimension tabs
        x_pos += PADDING * 2;
        const tab_names = [_][]const u8{ "Overworld", "Nether", "End" };
        const tab_dims = [_]World.Dimension{ .overworld, .nether, .the_end };
        const tab_h: f32 = TOOLBAR_HEIGHT - 4;
        const tab_y: f32 = 2;
        const tab_pad: f32 = 12;

        for (tab_names, tab_dims) |tab_name, tab_dim| {
            const tab_w = tr.measureText(tab_name, SMALL_TEXT_SCALE) + tab_pad * 2;
            const is_active = w.dimension == tab_dim;

            qr.drawQuad(x_pos, tab_y, tab_w, tab_h, if (is_active) TAB_ACTIVE_COLOR else TAB_COLOR);

            const tab_text_y = tab_y + (tab_h - tr.font_line_height * SMALL_TEXT_SCALE) / 2;
            tr.drawText(tab_name, x_pos + tab_pad, tab_text_y, SMALL_TEXT_SCALE, if (is_active) TAB_TEXT_ACTIVE else TAB_TEXT_INACTIVE);

            x_pos += tab_w + 2;
        }
    }

    // Right: shortcuts
    const shortcuts = "1/2/3 Dim  Ctrl+O Open";
    const shortcuts_w = tr.measureText(shortcuts, SMALL_TEXT_SCALE);
    const shortcuts_y: f32 = (TOOLBAR_HEIGHT - tr.font_line_height * SMALL_TEXT_SCALE) / 2;
    tr.drawText(shortcuts, viewport_w - shortcuts_w - PADDING, shortcuts_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR);
}

fn renderStatusBar(
    qr: *QuadRenderer,
    tr: *TextRenderer,
    state: State,
    world: ?*const World,
    camera: *const Camera,
    selection: *const Selection,
    mouse_x: f64,
    mouse_y: f64,
    viewport_w: f32,
    viewport_h: f32,
    thread_count: u32,
    hover_block: []const u8,
) void {
    _ = state;
    _ = world;
    const bar_y = viewport_h - STATUSBAR_HEIGHT;

    qr.drawQuad(0, bar_y, viewport_w, STATUSBAR_HEIGHT, BG_COLOR);

    const text_y = bar_y + (STATUSBAR_HEIGHT - tr.font_line_height * SMALL_TEXT_SCALE) / 2;

    // Coordinate display
    const world_pos = camera.screenToWorld(mouse_x, mouse_y);
    const block_x: i32 = @intFromFloat(@floor(world_pos.x * 16));
    const block_z: i32 = @intFromFloat(@floor(world_pos.z * 16));
    const chunk_x: i32 = @intFromFloat(@floor(world_pos.x));
    const chunk_z: i32 = @intFromFloat(@floor(world_pos.z));
    const region_x = @divFloor(chunk_x, 32);
    const region_z = @divFloor(chunk_z, 32);

    var x: f32 = PADDING;

    tr.drawText("Block: ", x, text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR);
    x += tr.measureText("Block: ", SMALL_TEXT_SCALE);
    tr.drawFmt(x, text_y, SMALL_TEXT_SCALE, TEXT_COLOR, "{d},{d}", .{ block_x, block_z });
    x += tr.measureFmt(SMALL_TEXT_SCALE, "{d},{d}", .{ block_x, block_z }) + PADDING * 2;

    tr.drawText("Chunk: ", x, text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR);
    x += tr.measureText("Chunk: ", SMALL_TEXT_SCALE);
    tr.drawFmt(x, text_y, SMALL_TEXT_SCALE, TEXT_COLOR, "{d},{d}", .{ chunk_x, chunk_z });
    x += tr.measureFmt(SMALL_TEXT_SCALE, "{d},{d}", .{ chunk_x, chunk_z }) + PADDING * 2;

    tr.drawText("Region: ", x, text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR);
    x += tr.measureText("Region: ", SMALL_TEXT_SCALE);
    tr.drawFmt(x, text_y, SMALL_TEXT_SCALE, TEXT_COLOR, "{d},{d}", .{ region_x, region_z });
    x += tr.measureFmt(SMALL_TEXT_SCALE, "{d},{d}", .{ region_x, region_z }) + PADDING * 2;

    if (hover_block.len > 0) {
        // Strip "minecraft:" prefix for cleaner display
        const display_name = if (std.mem.startsWith(u8, hover_block, "minecraft:"))
            hover_block["minecraft:".len..]
        else
            hover_block;
        tr.drawText(display_name, x, text_y, SMALL_TEXT_SCALE, ACCENT_COLOR);
    }

    // Right side: thread count + selection count
    var right_x = viewport_w - PADDING;

    // Thread count
    {
        var buf: [32]u8 = undefined;
        const txt = std.fmt.bufPrint(&buf, "Threads: {d} (+/-)", .{thread_count}) catch "";
        const w = tr.measureText(txt, SMALL_TEXT_SCALE);
        right_x -= w;
        tr.drawText(txt, right_x, text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR);
        right_x -= PADDING * 2;
    }

    // Selection count
    const selected = selection.count();
    if (selected > 0) {
        var buf: [64]u8 = undefined;
        const sel_text = std.fmt.bufPrint(&buf, "Selected: {d}", .{selected}) catch return;
        const sel_w = tr.measureText(sel_text, SMALL_TEXT_SCALE);
        right_x -= sel_w;
        tr.drawText(sel_text, right_x, text_y, SMALL_TEXT_SCALE, ACCENT_COLOR);
    }
}
