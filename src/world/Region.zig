const std = @import("std");
const mca = @import("mca.zig");

const Region = @This();

pub const ChunkState = enum(u8) {
    absent = 0,
    present = 1,
};

rx: i32,
rz: i32,
chunks: [32][32]ChunkState = .{.{.absent} ** 32} ** 32,
colors: [32][32][3]u8 = .{.{.{ 0, 0, 0 }} ** 32} ** 32,

pub fn loadFromHeader(rx: i32, rz: i32, header: *const mca.RegionHeader) Region {
    var region = Region{
        .rx = rx,
        .rz = rz,
    };

    for (0..32) |z| {
        for (0..32) |x| {
            const lx: u5 = @intCast(x);
            const lz: u5 = @intCast(z);
            if (mca.chunkExists(header, lx, lz)) {
                region.chunks[z][x] = .present;
                // Default green color, darker for variety
                region.colors[z][x] = .{ 60, 140, 60 };
            }
        }
    }

    return region;
}

pub fn chunkCount(self: *const Region) u32 {
    var count: u32 = 0;
    for (0..32) |z| {
        for (0..32) |x| {
            if (self.chunks[z][x] == .present) count += 1;
        }
    }
    return count;
}

pub fn setChunkAbsent(self: *Region, local_x: u5, local_z: u5) void {
    self.chunks[local_z][local_x] = .absent;
}
