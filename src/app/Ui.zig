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
) void {
    renderToolbar(qr, tr, state, world, selection, viewport_w);
    renderStatusBar(qr, tr, state, world, camera, selection, mouse_x, mouse_y, viewport_w, viewport_h);
}

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
    if (world) |w| {
        const name = World.extractWorldName(w.path);
        var x = PADDING + tr.measureText("Unchunked", TEXT_SCALE) + PADDING;
        tr.drawText("|", x, text_y, TEXT_SCALE, DIM_TEXT_COLOR);
        x += tr.measureText("|", TEXT_SCALE) + PADDING;
        tr.drawText(name, x, text_y, TEXT_SCALE, TEXT_COLOR);
    }

    // Right: shortcuts
    const shortcuts = "Ctrl+O Open  Ctrl+G Goto";
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

    // Right: selection count
    const selected = selection.count();
    if (selected > 0) {
        var buf: [64]u8 = undefined;
        const sel_text = std.fmt.bufPrint(&buf, "Selected: {d}", .{selected}) catch return;
        const sel_w = tr.measureText(sel_text, SMALL_TEXT_SCALE);
        tr.drawText(sel_text, viewport_w - sel_w - PADDING, text_y, SMALL_TEXT_SCALE, ACCENT_COLOR);
    }
}
