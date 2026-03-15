const std = @import("std");
const QuadRenderer = @import("../renderer/QuadRenderer.zig");
const TextRenderer = @import("../renderer/TextRenderer.zig");
const Camera = @import("Camera.zig");
const Selection = @import("Selection.zig");
const World = @import("../world/World.zig");

const Ui = @This();

const TOOLBAR_HEIGHT: f32 = 28;
const STATUSBAR_HEIGHT: f32 = 24;
const PADDING: f32 = 8;
const TEXT_SCALE: f32 = 1.5;
const SMALL_TEXT_SCALE: f32 = 1.25;

const BG_COLOR = QuadRenderer.Color{ .r = 0.12, .g = 0.12, .b = 0.12, .a = 0.9 };
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
    quad_renderer: *QuadRenderer,
    text_renderer: *TextRenderer,
    state: State,
    world: ?*const World,
    camera: *const Camera,
    selection: *const Selection,
    mouse_x: f64,
    mouse_y: f64,
    viewport_w: f32,
    viewport_h: f32,
) void {
    renderToolbar(quad_renderer, text_renderer, state, world, selection, viewport_w);
    renderStatusBar(quad_renderer, text_renderer, state, world, camera, selection, mouse_x, mouse_y, viewport_w, viewport_h);
}

fn renderToolbar(
    qr: *QuadRenderer,
    tr: *TextRenderer,
    state: State,
    world: ?*const World,
    selection: *const Selection,
    viewport_w: f32,
) void {
    // Background bar
    qr.drawQuad(0, 0, viewport_w, TOOLBAR_HEIGHT, BG_COLOR);

    const text_y: f32 = (TOOLBAR_HEIGHT - 8 * TEXT_SCALE) / 2;

    if (state == .confirm_delete) {
        const selected = selection.count();
        tr.drawFmt(PADDING, text_y, TEXT_SCALE, WARN_COLOR, "DELETE {d} chunks? Press Y to confirm, Esc to cancel", .{selected});
        return;
    }

    // Left side: world name
    if (world) |w| {
        const name = World.extractWorldName(w.path);
        tr.drawText("Unchunked", PADDING, text_y, TEXT_SCALE, ACCENT_COLOR);
        const sep_x = PADDING + TextRenderer.textWidth("Unchunked", TEXT_SCALE) + PADDING;
        tr.drawText("|", sep_x, text_y, TEXT_SCALE, DIM_TEXT_COLOR);
        const name_x = sep_x + TextRenderer.textWidth("|", TEXT_SCALE) + PADDING;
        tr.drawText(name, name_x, text_y, TEXT_SCALE, TEXT_COLOR);
    } else {
        tr.drawText("Unchunked", PADDING, text_y, TEXT_SCALE, ACCENT_COLOR);
    }

    // Right side: shortcuts
    const shortcuts = "Ctrl+O Open  Ctrl+G Goto";
    const shortcuts_w = TextRenderer.textWidth(shortcuts, SMALL_TEXT_SCALE);
    const shortcuts_y: f32 = (TOOLBAR_HEIGHT - 8 * SMALL_TEXT_SCALE) / 2;
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
) void {
    _ = state;
    const bar_y = viewport_h - STATUSBAR_HEIGHT;

    // Background bar
    qr.drawQuad(0, bar_y, viewport_w, STATUSBAR_HEIGHT, BG_COLOR);

    const text_y = bar_y + (STATUSBAR_HEIGHT - 8 * SMALL_TEXT_SCALE) / 2;

    if (world == null) {
        tr.drawText("No world loaded - press Ctrl+O or pass path as argument", PADDING, text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR);
        return;
    }

    // Coordinate display
    const world_pos = camera.screenToWorld(mouse_x, mouse_y);
    const block_x: i32 = @intFromFloat(@floor(world_pos.x * 16));
    const block_z: i32 = @intFromFloat(@floor(world_pos.z * 16));
    const chunk_x: i32 = @intFromFloat(@floor(world_pos.x));
    const chunk_z: i32 = @intFromFloat(@floor(world_pos.z));
    const region_x = @divFloor(chunk_x, 32);
    const region_z = @divFloor(chunk_z, 32);

    tr.drawFmt(PADDING, text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR, "Block: ", .{});
    var x_offset = PADDING + TextRenderer.textWidth("Block: ", SMALL_TEXT_SCALE);
    tr.drawFmt(x_offset, text_y, SMALL_TEXT_SCALE, TEXT_COLOR, "{d},{d}", .{ block_x, block_z });

    x_offset += TextRenderer.textWidth(fmtBuf("{d},{d}", .{ block_x, block_z }), SMALL_TEXT_SCALE) + PADDING;
    tr.drawFmt(x_offset, text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR, "Chunk: ", .{});
    x_offset += TextRenderer.textWidth("Chunk: ", SMALL_TEXT_SCALE);
    tr.drawFmt(x_offset, text_y, SMALL_TEXT_SCALE, TEXT_COLOR, "{d},{d}", .{ chunk_x, chunk_z });

    x_offset += TextRenderer.textWidth(fmtBuf("{d},{d}", .{ chunk_x, chunk_z }), SMALL_TEXT_SCALE) + PADDING;
    tr.drawFmt(x_offset, text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR, "Region: ", .{});
    x_offset += TextRenderer.textWidth("Region: ", SMALL_TEXT_SCALE);
    tr.drawFmt(x_offset, text_y, SMALL_TEXT_SCALE, TEXT_COLOR, "{d},{d}", .{ region_x, region_z });

    // Right side: selection count
    const selected = selection.count();
    if (selected > 0) {
        var buf: [64]u8 = undefined;
        const sel_text = std.fmt.bufPrint(&buf, "Selected: {d}", .{selected}) catch return;
        const sel_w = TextRenderer.textWidth(sel_text, SMALL_TEXT_SCALE);
        tr.drawText(sel_text, viewport_w - sel_w - PADDING, text_y, SMALL_TEXT_SCALE, ACCENT_COLOR);
    }
}

fn fmtBuf(comptime fmt: []const u8, args: anytype) []const u8 {
    const S = struct {
        var buf: [128]u8 = undefined;
    };
    return std.fmt.bufPrint(&S.buf, fmt, args) catch "";
}
