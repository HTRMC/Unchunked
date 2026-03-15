const std = @import("std");

const Camera = @This();

center_x: f64 = 0,
center_z: f64 = 0,
scale: f64 = 16,
viewport_width: f64 = 1280,
viewport_height: f64 = 720,

// Pan state
panning: bool = false,
pan_start_x: f64 = 0,
pan_start_z: f64 = 0,
pan_start_mouse_x: f64 = 0,
pan_start_mouse_y: f64 = 0,

pub const ChunkRange = struct {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
};

pub fn screenToWorld(self: *const Camera, screen_x: f64, screen_y: f64) struct { x: f64, z: f64 } {
    const world_x = self.center_x + (screen_x - self.viewport_width / 2.0) / self.scale;
    const world_z = self.center_z + (screen_y - self.viewport_height / 2.0) / self.scale;
    return .{ .x = world_x, .z = world_z };
}

pub fn worldToScreen(self: *const Camera, world_x: f64, world_z: f64) struct { x: f64, y: f64 } {
    const screen_x = (world_x - self.center_x) * self.scale + self.viewport_width / 2.0;
    const screen_y = (world_z - self.center_z) * self.scale + self.viewport_height / 2.0;
    return .{ .x = screen_x, .y = screen_y };
}

pub fn getViewProjection(self: *const Camera) [16]f32 {
    // Orthographic projection: map world coords to NDC [-1,1]
    const half_w = self.viewport_width / (2.0 * self.scale);
    const half_h = self.viewport_height / (2.0 * self.scale);

    const left: f32 = @floatCast(self.center_x - half_w);
    const right: f32 = @floatCast(self.center_x + half_w);
    const top: f32 = @floatCast(self.center_z - half_h);
    const bottom: f32 = @floatCast(self.center_z + half_h);

    // Column-major orthographic projection matrix
    return ortho(left, right, top, bottom, -1.0, 1.0);
}

pub fn visibleChunkRange(self: *const Camera) ChunkRange {
    const half_w = self.viewport_width / (2.0 * self.scale);
    const half_h = self.viewport_height / (2.0 * self.scale);

    return .{
        .min_x = @intFromFloat(@floor(self.center_x - half_w) - 1),
        .max_x = @intFromFloat(@ceil(self.center_x + half_w) + 1),
        .min_z = @intFromFloat(@floor(self.center_z - half_h) - 1),
        .max_z = @intFromFloat(@ceil(self.center_z + half_h) + 1),
    };
}

pub fn zoom(self: *Camera, scroll_y: f64, mouse_x: f64, mouse_y: f64) void {
    // Zoom centered on cursor position
    const world_before = self.screenToWorld(mouse_x, mouse_y);

    const factor: f64 = if (scroll_y > 0) 1.15 else 1.0 / 1.15;
    self.scale = std.math.clamp(self.scale * factor, 0.5, 512.0);

    const world_after = self.screenToWorld(mouse_x, mouse_y);
    self.center_x += world_before.x - world_after.x;
    self.center_z += world_before.z - world_after.z;
}

pub fn startPan(self: *Camera, mouse_x: f64, mouse_y: f64) void {
    self.panning = true;
    self.pan_start_x = self.center_x;
    self.pan_start_z = self.center_z;
    self.pan_start_mouse_x = mouse_x;
    self.pan_start_mouse_y = mouse_y;
}

pub fn updatePan(self: *Camera, mouse_x: f64, mouse_y: f64) void {
    if (!self.panning) return;
    const dx = (mouse_x - self.pan_start_mouse_x) / self.scale;
    const dy = (mouse_y - self.pan_start_mouse_y) / self.scale;
    self.center_x = self.pan_start_x - dx;
    self.center_z = self.pan_start_z - dy;
}

pub fn endPan(self: *Camera) void {
    self.panning = false;
}

pub fn setViewportSize(self: *Camera, width: u32, height: u32) void {
    self.viewport_width = @floatFromInt(width);
    self.viewport_height = @floatFromInt(height);
}

pub fn goTo(self: *Camera, chunk_x: f64, chunk_z: f64) void {
    self.center_x = chunk_x;
    self.center_z = chunk_z;
}

fn ortho(left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) [16]f32 {
    const rl = right - left;
    const bt = bottom - top;
    const fn_ = far - near;

    return .{
        2.0 / rl,         0,                 0,                 0,
        0,                 2.0 / bt,          0,                 0,
        0,                 0,                 -2.0 / fn_,        0,
        -(right + left) / rl, -(bottom + top) / bt, -(far + near) / fn_, 1.0,
    };
}
