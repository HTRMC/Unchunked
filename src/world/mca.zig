const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;

pub const SECTOR_SIZE = 4096;
pub const HEADER_SIZE = SECTOR_SIZE * 2;

pub const RegionHeader = struct {
    locations: [1024]u32 = .{0} ** 1024,
    timestamps: [1024]u32 = .{0} ** 1024,
};

pub fn chunkIndex(local_x: u5, local_z: u5) u10 {
    return @as(u10, local_x) + @as(u10, local_z) * 32;
}

pub fn chunkExists(header: *const RegionHeader, local_x: u5, local_z: u5) bool {
    return header.locations[chunkIndex(local_x, local_z)] != 0;
}

pub fn readRegionHeader(io: Io, path: []const u8) !RegionHeader {
    const file = Dir.openFile(.cwd(), io, path, .{}) catch return error.InvalidFormat;
    defer file.close(io);

    var header = RegionHeader{};

    // Read locations (4096 bytes = 1024 * 4-byte big-endian)
    var loc_bytes: [4096]u8 = undefined;
    const loc_read = file.readPositionalAll(io, &loc_bytes, 0) catch return error.InvalidFormat;
    if (loc_read < 4096) return error.InvalidFormat;

    for (0..1024) |i| {
        header.locations[i] = std.mem.readInt(u32, loc_bytes[i * 4 ..][0..4], .big);
    }

    // Read timestamps
    var ts_bytes: [4096]u8 = undefined;
    const ts_read = file.readPositionalAll(io, &ts_bytes, 4096) catch return error.InvalidFormat;
    if (ts_read < 4096) return error.InvalidFormat;

    for (0..1024) |i| {
        header.timestamps[i] = std.mem.readInt(u32, ts_bytes[i * 4 ..][0..4], .big);
    }

    return header;
}

pub const LocalChunk = struct { x: u5, z: u5 };

pub fn deleteChunks(
    io: Io,
    path: []const u8,
    chunks: []const LocalChunk,
) !void {
    const file = Dir.openFile(.cwd(), io, path, .{ .mode = .read_write }) catch return;
    defer file.close(io);

    // Read header
    var loc_bytes: [4096]u8 = undefined;
    _ = file.readPositionalAll(io, &loc_bytes, 0) catch return;

    var ts_bytes: [4096]u8 = undefined;
    _ = file.readPositionalAll(io, &ts_bytes, 4096) catch return;

    // Zero out selected entries
    for (chunks) |chunk| {
        const idx = chunkIndex(chunk.x, chunk.z);
        std.mem.writeInt(u32, loc_bytes[idx * 4 ..][0..4], 0, .big);
        std.mem.writeInt(u32, ts_bytes[idx * 4 ..][0..4], 0, .big);
    }

    // Write back
    _ = file.writePositionalAll(io, &loc_bytes, 0) catch return;
    _ = file.writePositionalAll(io, &ts_bytes, 4096) catch return;
}

pub fn parseRegionFilename(name: []const u8) ?struct { x: i32, z: i32 } {
    // Parse "r.X.Z.mca"
    if (!std.mem.startsWith(u8, name, "r.")) return null;
    if (!std.mem.endsWith(u8, name, ".mca")) return null;

    const inner = name[2 .. name.len - 4]; // strip "r." and ".mca"
    const dot_pos = std.mem.indexOfScalar(u8, inner, '.') orelse return null;

    const x_str = inner[0..dot_pos];
    const z_str = inner[dot_pos + 1 ..];

    const x = std.fmt.parseInt(i32, x_str, 10) catch return null;
    const z = std.fmt.parseInt(i32, z_str, 10) catch return null;

    return .{ .x = x, .z = z };
}
