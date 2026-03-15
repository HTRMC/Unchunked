const std = @import("std");

const Selection = @This();

pub const ChunkKey = struct {
    x: i32,
    z: i32,
};

const ChunkKeyContext = struct {
    pub fn hash(_: @This(), key: ChunkKey) u64 {
        var h: u64 = 0;
        h = std.hash.Wyhash.hash(h, std.mem.asBytes(&key.x));
        h = std.hash.Wyhash.hash(h, std.mem.asBytes(&key.z));
        return h;
    }

    pub fn eql(_: @This(), a: ChunkKey, b: ChunkKey) bool {
        return a.x == b.x and a.z == b.z;
    }
};

const ChunkSet = std.HashMap(ChunkKey, void, ChunkKeyContext, std.hash_map.default_max_load_percentage);

chunks: ChunkSet,
// Box selection state
box_selecting: bool = false,
box_start_x: i32 = 0,
box_start_z: i32 = 0,
box_end_x: i32 = 0,
box_end_z: i32 = 0,

pub fn init(allocator: std.mem.Allocator) Selection {
    return .{
        .chunks = ChunkSet.init(allocator),
    };
}

pub fn deinit(self: *Selection) void {
    self.chunks.deinit();
}

pub fn toggle(self: *Selection, cx: i32, cz: i32) void {
    const key = ChunkKey{ .x = cx, .z = cz };
    if (self.chunks.contains(key)) {
        _ = self.chunks.remove(key);
    } else {
        self.chunks.put(key, {}) catch {};
    }
}

pub fn toggleRegion(self: *Selection, rx: i32, rz: i32) void {
    // Toggle all 1024 chunks in a region
    const base_x = rx * 32;
    const base_z = rz * 32;

    // Check if any chunk in the region is selected
    var any_selected = false;
    var cx: i32 = 0;
    while (cx < 32) : (cx += 1) {
        var cz: i32 = 0;
        while (cz < 32) : (cz += 1) {
            if (self.isSelected(base_x + cx, base_z + cz)) {
                any_selected = true;
                break;
            }
        }
        if (any_selected) break;
    }

    // If any selected, deselect all; otherwise select all
    cx = 0;
    while (cx < 32) : (cx += 1) {
        var cz: i32 = 0;
        while (cz < 32) : (cz += 1) {
            const key = ChunkKey{ .x = base_x + cx, .z = base_z + cz };
            if (any_selected) {
                _ = self.chunks.remove(key);
            } else {
                self.chunks.put(key, {}) catch {};
            }
        }
    }
}

pub fn addBox(self: *Selection, x1: i32, z1: i32, x2: i32, z2: i32) void {
    const min_x = @min(x1, x2);
    const max_x = @max(x1, x2);
    const min_z = @min(z1, z2);
    const max_z = @max(z1, z2);

    var cx = min_x;
    while (cx <= max_x) : (cx += 1) {
        var cz = min_z;
        while (cz <= max_z) : (cz += 1) {
            self.chunks.put(ChunkKey{ .x = cx, .z = cz }, {}) catch {};
        }
    }
}

pub fn clear(self: *Selection) void {
    self.chunks.clearRetainingCapacity();
}

pub fn isSelected(self: *const Selection, cx: i32, cz: i32) bool {
    return self.chunks.contains(ChunkKey{ .x = cx, .z = cz });
}

pub fn count(self: *const Selection) u32 {
    return self.chunks.count();
}

pub fn startBoxSelect(self: *Selection, cx: i32, cz: i32) void {
    self.box_selecting = true;
    self.box_start_x = cx;
    self.box_start_z = cz;
    self.box_end_x = cx;
    self.box_end_z = cz;
}

pub fn updateBoxSelect(self: *Selection, cx: i32, cz: i32) void {
    if (self.box_selecting) {
        self.box_end_x = cx;
        self.box_end_z = cz;
    }
}

pub fn endBoxSelect(self: *Selection) void {
    if (self.box_selecting) {
        self.addBox(self.box_start_x, self.box_start_z, self.box_end_x, self.box_end_z);
        self.box_selecting = false;
    }
}

pub const ChunkCoord = struct { cx: i32, cz: i32 };

pub fn getSelectedChunks(self: *const Selection, allocator: std.mem.Allocator) ![]ChunkCoord {
    var list: std.ArrayListUnmanaged(ChunkCoord) = .empty;
    var it = self.chunks.keyIterator();
    while (it.next()) |key| {
        try list.append(allocator, .{ .cx = key.x, .cz = key.z });
    }
    return list.toOwnedSlice(allocator);
}
