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

pub fn readChunkNbt(allocator: std.mem.Allocator, io: Io, path: []const u8, header: *const RegionHeader, local_x: u5, local_z: u5) ?DecompressResult {
    const file = Dir.openFile(.cwd(), io, path, .{}) catch return null;
    defer file.close(io);
    return readChunkNbtFromFile(allocator, io, file, header, local_x, local_z);
}

pub fn readChunkNbtFromFile(allocator: std.mem.Allocator, io: Io, file: File, header: *const RegionHeader, local_x: u5, local_z: u5) ?DecompressResult {
    return readChunkNbtFromFileReuse(allocator, io, file, header, local_x, local_z, null);
}

pub fn readChunkNbtFromFileReuse(allocator: std.mem.Allocator, io: Io, file: File, header: *const RegionHeader, local_x: u5, local_z: u5, reuse_buf: ?[]u8) ?DecompressResult {
    const loc = header.locations[chunkIndex(local_x, local_z)];
    if (loc == 0) return null;

    const sector_offset: u64 = @as(u64, (loc >> 8) & 0xFFFFFF) * SECTOR_SIZE;

    // Read chunk header: 4-byte length + 1-byte compression type
    var chunk_header: [5]u8 = undefined;
    _ = file.readPositionalAll(io, &chunk_header, sector_offset) catch return null;

    const data_length = std.mem.readInt(u32, chunk_header[0..4], .big);
    const compression_type = chunk_header[4];

    if (data_length <= 1) return null;

    // Read compressed data
    const compressed_size: usize = data_length - 1;
    const compressed = allocator.alloc(u8, compressed_size) catch return null;
    defer allocator.free(compressed);

    const read_count = file.readPositionalAll(io, compressed, sector_offset + 5) catch {
        return null;
    };
    if (read_count < compressed_size) return null;

    // Decompress based on compression type
    return switch (compression_type) {
        2 => decompressZlibInto(allocator, compressed, reuse_buf),
        else => null,
    };
}

pub const DecompressResult = struct {
    data: []u8, // slice into backing allocation
    backing: []u8, // full allocation for freeing
};

pub fn decompressZlib(allocator: std.mem.Allocator, compressed: []const u8) ?DecompressResult {
    return decompressZlibInto(allocator, compressed, null);
}

/// Decompress zlib data, reusing `reuse_buf` if large enough. Falls back to allocating.
pub fn decompressZlibInto(allocator: std.mem.Allocator, compressed: []const u8, reuse_buf: ?[]u8) ?DecompressResult {
    if (compressed.len < 6) return null;

    const deflate_data = compressed[2..];

    const flate = std.compress.flate;
    var in_reader: std.Io.Reader = .fixed(deflate_data);
    var decomp_buf: [flate.max_window_len]u8 = undefined;
    var decomp = flate.Decompress.init(&in_reader, .raw, &decomp_buf);

    const max_output = 4 * 1024 * 1024;
    const output = reuse_buf orelse (allocator.alloc(u8, max_output) catch return null);

    var out_writer: std.Io.Writer = .fixed(output);
    const total = decomp.reader.streamRemaining(&out_writer) catch {
        if (reuse_buf == null) allocator.free(output);
        return null;
    };

    return .{ .data = output[0..total], .backing = output };
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
