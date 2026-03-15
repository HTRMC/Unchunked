const std = @import("std");
const mca = @import("mca.zig");
const chunk_renderer = @import("chunk_renderer.zig");

const Region = @This();

pub const ChunkState = enum(u8) {
    absent = 0,
    present = 1,
};

pub const REGION_PX = 512;
pub const PIXEL_DATA_SIZE = REGION_PX * REGION_PX * 4;

rx: i32,
rz: i32,
chunks: [32][32]ChunkState = .{.{.absent} ** 32} ** 32,
pixels: ?[]u8 = null, // 512*512*4 RGBA8

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
            }
        }
    }

    return region;
}

pub fn loadPixels(self: *Region, allocator: std.mem.Allocator, io: std.Io, mca_path: []const u8, header: *const mca.RegionHeader) void {
    if (self.pixels != null) return;
    self.pixels = allocator.alloc(u8, PIXEL_DATA_SIZE) catch return;
    @memset(self.pixels.?, 0);

    for (0..32) |z| {
        for (0..32) |x| {
            if (self.chunks[z][x] != .present) continue;

            const lx: u5 = @intCast(x);
            const lz: u5 = @intCast(z);

            const result = mca.readChunkNbt(allocator, io, mca_path, header, lx, lz) orelse continue;
            defer allocator.free(result.backing);

            var chunk_pixels: chunk_renderer.ChunkPixels = undefined;
            chunk_renderer.renderChunk(result.data, &chunk_pixels);

            // Copy into region pixel buffer
            const base_x: usize = @as(usize, lx) * 16;
            const base_z: usize = @as(usize, lz) * 16;

            for (0..16) |bz| {
                for (0..16) |bx| {
                    const idx = ((base_z + bz) * REGION_PX + (base_x + bx)) * 4;
                    const color = chunk_pixels[bz][bx];
                    self.pixels.?[idx + 0] = color[0];
                    self.pixels.?[idx + 1] = color[1];
                    self.pixels.?[idx + 2] = color[2];
                    self.pixels.?[idx + 3] = color[3];
                }
            }
        }
    }
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
    // Clear pixels for this chunk
    if (self.pixels) |px| {
        const base_x: usize = @as(usize, local_x) * 16;
        const base_z: usize = @as(usize, local_z) * 16;
        for (0..16) |bz| {
            const row_start = ((base_z + bz) * REGION_PX + base_x) * 4;
            @memset(px[row_start .. row_start + 16 * 4], 0);
        }
    }
}

pub fn deinit(self: *Region, allocator: std.mem.Allocator) void {
    if (self.pixels) |px| allocator.free(px);
    self.pixels = null;
}
