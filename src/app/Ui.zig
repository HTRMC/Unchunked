const std = @import("std");
const QuadRenderer = @import("../renderer/QuadRenderer.zig");
const TextRenderer = @import("../renderer/TextRenderer.zig");
const Camera = @import("Camera.zig");
const Selection = @import("Selection.zig");
const World = @import("../world/World.zig");

const Ui = @This();

pub const TOOLBAR_HEIGHT: f32 = 36;
const STATUSBAR_HEIGHT: f32 = 32;
const PADDING: f32 = 10;
const TEXT_SCALE: f32 = 0.5;
const SMALL_TEXT_SCALE: f32 = 0.42;
const MENU_HEADER_PAD: f32 = 10;
const MENU_GAP: f32 = 2;
const DROPDOWN_WIDTH: f32 = 220;
const DROPDOWN_ITEM_HEIGHT: f32 = 28;
const DROPDOWN_PAD: f32 = 4;
const SLIDER_WIDTH: f32 = 120;
const SLIDER_HANDLE_W: f32 = 8;
const SLIDER_HANDLE_H: f32 = 18;
const SLIDER_TRACK_H: f32 = 6;

const BG_COLOR = QuadRenderer.Color{ .r = 0.12, .g = 0.12, .b = 0.12, .a = 0.92 };
const DROPDOWN_BG = QuadRenderer.Color{ .r = 0.14, .g = 0.14, .b = 0.16, .a = 0.96 };
const HOVER_BG = QuadRenderer.Color{ .r = 0.25, .g = 0.25, .b = 0.32, .a = 1.0 };
const TEXT_COLOR = TextRenderer.Color{ .r = 0.9, .g = 0.9, .b = 0.9, .a = 1.0 };
const DIM_TEXT_COLOR = TextRenderer.Color{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1.0 };
const ACCENT_COLOR = TextRenderer.Color{ .r = 0.4, .g = 0.7, .b = 1.0, .a = 1.0 };
const WARN_COLOR = TextRenderer.Color{ .r = 1.0, .g = 0.4, .b = 0.3, .a = 1.0 };
const TAB_COLOR = QuadRenderer.Color{ .r = 0.22, .g = 0.22, .b = 0.24, .a = 0.95 };
const TAB_ACTIVE_COLOR = QuadRenderer.Color{ .r = 0.32, .g = 0.32, .b = 0.38, .a = 1.0 };
const TAB_TEXT_INACTIVE = TextRenderer.Color{ .r = 0.75, .g = 0.75, .b = 0.75, .a = 1.0 };
const TAB_TEXT_ACTIVE = TextRenderer.Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
const MENU_HEADER_HOVER_BG = QuadRenderer.Color{ .r = 0.2, .g = 0.2, .b = 0.24, .a = 1.0 };
const SLIDER_TRACK_COLOR = QuadRenderer.Color{ .r = 0.2, .g = 0.2, .b = 0.22, .a = 1.0 };
const SLIDER_HANDLE_COLOR = QuadRenderer.Color{ .r = 0.45, .g = 0.55, .b = 0.75, .a = 1.0 };

pub const State = enum {
    no_world,
    viewing,
    confirm_delete,
};

pub const MenuId = enum(u8) {
    file = 0,
    view = 1,
    selection = 2,
    tools = 3,
};

const MenuItem = struct {
    label: []const u8,
    shortcut: []const u8,
};

const menu_headers = [_][]const u8{ "File", "View", "Selection", "Tools" };

const file_items = [_]MenuItem{
    .{ .label = "Open World", .shortcut = "Ctrl+O" },
    .{ .label = "Quit", .shortcut = "" },
};

const view_items = [_]MenuItem{
    .{ .label = "Goto", .shortcut = "Ctrl+G" },
    .{ .label = "Toggle Chunk Grid", .shortcut = "" },
    .{ .label = "Toggle Region Grid", .shortcut = "" },
};

const selection_items = [_]MenuItem{
    .{ .label = "Clear", .shortcut = "Esc" },
    .{ .label = "Delete Selected", .shortcut = "Del" },
};

const tools_items = [_]MenuItem{
    .{ .label = "Threads +", .shortcut = "+" },
    .{ .label = "Threads -", .shortcut = "-" },
};

pub fn getMenuItems(menu: MenuId) []const MenuItem {
    return switch (menu) {
        .file => &file_items,
        .view => &view_items,
        .selection => &selection_items,
        .tools => &tools_items,
    };
}

pub fn getMenuItemCount(menu: MenuId) u8 {
    return @intCast(getMenuItems(menu).len);
}

const Y_MIN: f32 = -64;
const Y_MAX: f32 = 319;
const Y_RANGE: f32 = Y_MAX - Y_MIN;

pub const HitResult = union(enum) {
    none,
    menu_header: MenuId,
    menu_item: u8,
    dimension_tab: World.Dimension,
    y_slider,
};

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn contains(self: Rect, mx: f64, my: f64) bool {
        const fx: f32 = @floatCast(mx);
        const fy: f32 = @floatCast(my);
        return fx >= self.x and fx < self.x + self.w and fy >= self.y and fy < self.y + self.h;
    }
};

fn menuHeaderRect(tr: *const TextRenderer, idx: usize) Rect {
    var x: f32 = PADDING;
    for (0..idx) |i| {
        x += tr.measureText(menu_headers[i], SMALL_TEXT_SCALE) + MENU_HEADER_PAD * 2 + MENU_GAP;
    }
    const w = tr.measureText(menu_headers[idx], SMALL_TEXT_SCALE) + MENU_HEADER_PAD * 2;
    return .{ .x = x, .y = 0, .w = w, .h = TOOLBAR_HEIGHT };
}

fn menuEndX(tr: *const TextRenderer) f32 {
    var x: f32 = PADDING;
    for (menu_headers) |header| {
        x += tr.measureText(header, SMALL_TEXT_SCALE) + MENU_HEADER_PAD * 2 + MENU_GAP;
    }
    return x;
}

fn tabStartX(tr: *const TextRenderer, world: *const World) f32 {
    var x = menuEndX(tr) + PADDING;
    // Separator
    x += tr.measureText("|", TEXT_SCALE) + PADDING;
    // World name
    const name = World.extractWorldName(world.path);
    x += tr.measureText(name, TEXT_SCALE) + PADDING * 2;
    return x;
}

pub fn getTabRect(tr: *const TextRenderer, world: *const World, tab_idx: u8) Rect {
    var x = tabStartX(tr, world);
    const tab_names = [_][]const u8{ "Overworld", "Nether", "End" };
    const tab_pad: f32 = 12;
    const tab_h: f32 = TOOLBAR_HEIGHT - 4;
    const tab_y: f32 = 2;

    for (0..tab_idx) |i| {
        x += tr.measureText(tab_names[i], SMALL_TEXT_SCALE) + tab_pad * 2 + 2;
    }
    const w = tr.measureText(tab_names[tab_idx], SMALL_TEXT_SCALE) + tab_pad * 2;
    return .{ .x = x, .y = tab_y, .w = w, .h = tab_h };
}

pub fn getSliderTrackRect(tr: *const TextRenderer, viewport_w: f32) Rect {
    const label_w = tr.measureText("Y:", SMALL_TEXT_SCALE);
    var buf: [8]u8 = undefined;
    const val_text = std.fmt.bufPrint(&buf, "{d}", .{@as(i16, 319)}) catch "";
    const val_w = tr.measureText(val_text, SMALL_TEXT_SCALE);
    const total_w = label_w + 6 + SLIDER_WIDTH + 6 + val_w;
    const start_x = viewport_w - PADDING - total_w;
    const track_x = start_x + label_w + 6;
    const center_y = TOOLBAR_HEIGHT / 2;
    return .{ .x = track_x, .y = center_y - SLIDER_HANDLE_H / 2, .w = SLIDER_WIDTH, .h = SLIDER_HANDLE_H };
}

pub fn sliderValueFromX(tr: *const TextRenderer, viewport_w: f32, mouse_x: f64) i16 {
    const track = getSliderTrackRect(tr, viewport_w);
    const mx: f32 = @floatCast(mouse_x);
    const t = std.math.clamp((mx - track.x) / track.w, 0, 1);
    return @intFromFloat(Y_MIN + t * Y_RANGE);
}

pub fn hitTest(tr: *const TextRenderer, mouse_x: f64, mouse_y: f64, viewport_w: f32, world: ?*const World, open_menu: ?MenuId) HitResult {
    const my: f32 = @floatCast(mouse_y);

    // Check dropdown area (below toolbar)
    if (open_menu) |menu| {
        const header = menuHeaderRect(tr, @intFromEnum(menu));
        const items = getMenuItems(menu);
        const dropdown_h = @as(f32, @floatFromInt(items.len)) * DROPDOWN_ITEM_HEIGHT + DROPDOWN_PAD * 2;
        const dropdown_rect = Rect{ .x = header.x, .y = TOOLBAR_HEIGHT, .w = DROPDOWN_WIDTH, .h = dropdown_h };

        if (dropdown_rect.contains(mouse_x, mouse_y)) {
            const local_y = my - TOOLBAR_HEIGHT - DROPDOWN_PAD;
            if (local_y >= 0) {
                const idx: u8 = @intFromFloat(local_y / DROPDOWN_ITEM_HEIGHT);
                if (idx < items.len) return .{ .menu_item = idx };
            }
            return .none;
        }
    }

    // Check toolbar area
    if (my >= 0 and my < TOOLBAR_HEIGHT) {
        // Menu headers
        for (0..menu_headers.len) |i| {
            const rect = menuHeaderRect(tr, i);
            if (rect.contains(mouse_x, mouse_y)) {
                return .{ .menu_header = @enumFromInt(i) };
            }
        }

        // Y slider
        if (world != null) {
            const slider_rect = getSliderTrackRect(tr, viewport_w);
            if (slider_rect.contains(mouse_x, mouse_y)) {
                return .y_slider;
            }
        }

        // Dimension tabs
        if (world) |w| {
            const tab_dims = [_]World.Dimension{ .overworld, .nether, .the_end };
            for (0..3) |i| {
                const rect = getTabRect(tr, w, @intCast(i));
                if (rect.contains(mouse_x, mouse_y)) {
                    return .{ .dimension_tab = tab_dims[i] };
                }
            }
        }
    }

    return .none;
}

pub fn getHoveredMenuItem(tr: *const TextRenderer, mouse_x: f64, mouse_y: f64, menu: MenuId) ?u8 {
    const header = menuHeaderRect(tr, @intFromEnum(menu));
    const items = getMenuItems(menu);
    const dropdown_h = @as(f32, @floatFromInt(items.len)) * DROPDOWN_ITEM_HEIGHT + DROPDOWN_PAD * 2;
    const dropdown_rect = Rect{ .x = header.x, .y = TOOLBAR_HEIGHT, .w = DROPDOWN_WIDTH, .h = dropdown_h };

    if (!dropdown_rect.contains(mouse_x, mouse_y)) return null;
    const my: f32 = @floatCast(mouse_y);
    const local_y = my - TOOLBAR_HEIGHT - DROPDOWN_PAD;
    if (local_y < 0) return null;
    const idx: u8 = @intFromFloat(local_y / DROPDOWN_ITEM_HEIGHT);
    if (idx < items.len) return idx;
    return null;
}

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
    open_menu: ?MenuId,
    hover_item: ?u8,
    y_level: i16,
    show_chunk_grid: bool,
    show_region_grid: bool,
) void {
    _ = show_chunk_grid;
    _ = show_region_grid;
    renderToolbar(qr, tr, state, world, selection, viewport_w, open_menu, y_level);
    if (open_menu) |menu| {
        renderDropdown(qr, tr, menu, hover_item);
    }
    renderStatusBar(qr, tr, state, world, camera, selection, mouse_x, mouse_y, viewport_w, viewport_h, thread_count, hover_block);
}

fn renderToolbar(
    qr: *QuadRenderer,
    tr: *TextRenderer,
    state: State,
    world: ?*const World,
    selection: *const Selection,
    viewport_w: f32,
    open_menu: ?MenuId,
    y_level: i16,
) void {
    qr.drawQuad(0, 0, viewport_w, TOOLBAR_HEIGHT, BG_COLOR);

    const text_y: f32 = (TOOLBAR_HEIGHT - tr.font_line_height * TEXT_SCALE) / 2;
    const small_text_y: f32 = (TOOLBAR_HEIGHT - tr.font_line_height * SMALL_TEXT_SCALE) / 2;

    if (state == .confirm_delete) {
        const selected = selection.count();
        tr.drawFmt(PADDING, text_y, TEXT_SCALE, WARN_COLOR, "DELETE {d} chunks? Press Y to confirm, Esc to cancel", .{selected});
        return;
    }

    // Menu headers
    for (menu_headers, 0..) |header, i| {
        const rect = menuHeaderRect(tr, i);
        const is_open = if (open_menu) |m| @intFromEnum(m) == i else false;
        if (is_open) {
            qr.drawQuad(rect.x, rect.y, rect.w, rect.h, MENU_HEADER_HOVER_BG);
        }
        tr.drawText(header, rect.x + MENU_HEADER_PAD, small_text_y, SMALL_TEXT_SCALE, if (is_open) TEXT_COLOR else DIM_TEXT_COLOR);
    }

    // Separator + world name + tabs
    if (world) |w| {
        var x_pos = menuEndX(tr) + PADDING;
        tr.drawText("|", x_pos, text_y, TEXT_SCALE, DIM_TEXT_COLOR);
        x_pos += tr.measureText("|", TEXT_SCALE) + PADDING;

        const name = World.extractWorldName(w.path);
        tr.drawText(name, x_pos, text_y, TEXT_SCALE, TEXT_COLOR);
        x_pos += tr.measureText(name, TEXT_SCALE) + PADDING * 2;

        // Dimension tabs
        const tab_names = [_][]const u8{ "Overworld", "Nether", "End" };
        const tab_dims = [_]World.Dimension{ .overworld, .nether, .the_end };
        const tab_pad: f32 = 12;

        for (tab_names, tab_dims, 0..) |tab_name, tab_dim, i| {
            const rect = getTabRect(tr, w, @intCast(i));
            const is_active = w.dimension == tab_dim;
            qr.drawQuad(rect.x, rect.y, rect.w, rect.h, if (is_active) TAB_ACTIVE_COLOR else TAB_COLOR);
            const tab_text_y = rect.y + (rect.h - tr.font_line_height * SMALL_TEXT_SCALE) / 2;
            tr.drawText(tab_name, rect.x + tab_pad, tab_text_y, SMALL_TEXT_SCALE, if (is_active) TAB_TEXT_ACTIVE else TAB_TEXT_INACTIVE);
        }

        // Y-level slider (right side)
        renderYSlider(qr, tr, y_level, viewport_w);
    }
}

fn renderYSlider(qr: *QuadRenderer, tr: *TextRenderer, y_level: i16, viewport_w: f32) void {
    // Use getSliderTrackRect for consistent positioning with hit-testing
    const track_rect = getSliderTrackRect(tr, viewport_w);
    const track_x = track_rect.x;
    const center_y = TOOLBAR_HEIGHT / 2;
    const small_text_y: f32 = (TOOLBAR_HEIGHT - tr.font_line_height * SMALL_TEXT_SCALE) / 2;

    // Label (before track)
    const label = "Y:";
    const label_w = tr.measureText(label, SMALL_TEXT_SCALE);
    tr.drawText(label, track_x - 6 - label_w, small_text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR);

    // Track
    const track_y = center_y - SLIDER_TRACK_H / 2;
    qr.drawQuad(track_x, track_y, SLIDER_WIDTH, SLIDER_TRACK_H, SLIDER_TRACK_COLOR);

    // Handle
    const t = (@as(f32, @floatFromInt(y_level)) - Y_MIN) / Y_RANGE;
    const handle_x = track_x + t * (SLIDER_WIDTH - SLIDER_HANDLE_W);
    const handle_y = center_y - SLIDER_HANDLE_H / 2;
    qr.drawQuad(handle_x, handle_y, SLIDER_HANDLE_W, SLIDER_HANDLE_H, SLIDER_HANDLE_COLOR);

    // Value text (after track)
    var buf: [8]u8 = undefined;
    const val_text = std.fmt.bufPrint(&buf, "{d}", .{y_level}) catch "";
    tr.drawText(val_text, track_x + SLIDER_WIDTH + 6, small_text_y, SMALL_TEXT_SCALE, TEXT_COLOR);
}

fn renderDropdown(qr: *QuadRenderer, tr: *TextRenderer, menu: MenuId, hover_item: ?u8) void {
    const header = menuHeaderRect(tr, @intFromEnum(menu));
    const items = getMenuItems(menu);
    const item_count: f32 = @floatFromInt(items.len);
    const dropdown_h = item_count * DROPDOWN_ITEM_HEIGHT + DROPDOWN_PAD * 2;
    const dropdown_x = header.x;
    const dropdown_y = TOOLBAR_HEIGHT;

    // Background
    qr.drawQuad(dropdown_x, dropdown_y, DROPDOWN_WIDTH, dropdown_h, DROPDOWN_BG);

    // Border
    const border_color = QuadRenderer.Color{ .r = 0.25, .g = 0.25, .b = 0.3, .a = 1.0 };
    qr.drawQuad(dropdown_x, dropdown_y, DROPDOWN_WIDTH, 1, border_color);
    qr.drawQuad(dropdown_x, dropdown_y + dropdown_h - 1, DROPDOWN_WIDTH, 1, border_color);
    qr.drawQuad(dropdown_x, dropdown_y, 1, dropdown_h, border_color);
    qr.drawQuad(dropdown_x + DROPDOWN_WIDTH - 1, dropdown_y, 1, dropdown_h, border_color);

    for (items, 0..) |item, i| {
        const item_y = dropdown_y + DROPDOWN_PAD + @as(f32, @floatFromInt(i)) * DROPDOWN_ITEM_HEIGHT;

        if (hover_item != null and hover_item.? == i) {
            qr.drawQuad(dropdown_x + 2, item_y, DROPDOWN_WIDTH - 4, DROPDOWN_ITEM_HEIGHT, HOVER_BG);
        }

        const item_text_y = item_y + (DROPDOWN_ITEM_HEIGHT - tr.font_line_height * SMALL_TEXT_SCALE) / 2;
        tr.drawText(item.label, dropdown_x + PADDING, item_text_y, SMALL_TEXT_SCALE, TEXT_COLOR);

        if (item.shortcut.len > 0) {
            const shortcut_w = tr.measureText(item.shortcut, SMALL_TEXT_SCALE);
            tr.drawText(item.shortcut, dropdown_x + DROPDOWN_WIDTH - shortcut_w - PADDING, item_text_y, SMALL_TEXT_SCALE, DIM_TEXT_COLOR);
        }
    }
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
        const txt = std.fmt.bufPrint(&buf, "Threads: {d}", .{thread_count}) catch "";
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
