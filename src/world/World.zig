const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const mca = @import("mca.zig");
const Region = @import("Region.zig");
const Selection = @import("../app/Selection.zig");

const World = @This();

pub const Dimension = enum {
    overworld,
    nether,
    the_end,

    pub fn regionPath(self: Dimension) []const u8 {
        return switch (self) {
            .overworld => "region",
            .nether => "DIM-1/region",
            .the_end => "DIM1/region",
        };
    }
};

pub const RegionKey = struct {
    x: i32,
    z: i32,
};

const RegionMap = std.HashMap(RegionKey, Region, RegionKeyContext, std.hash_map.default_max_load_percentage);

const RegionKeyContext = struct {
    pub fn hash(_: @This(), key: RegionKey) u64 {
        var h: u64 = 0;
        h = std.hash.Wyhash.hash(h, std.mem.asBytes(&key.x));
        h = std.hash.Wyhash.hash(h, std.mem.asBytes(&key.z));
        return h;
    }

    pub fn eql(_: @This(), a: RegionKey, b: RegionKey) bool {
        return a.x == b.x and a.z == b.z;
    }
};

path: []const u8,
dimension: Dimension = .overworld,
regions: RegionMap,
allocator: std.mem.Allocator,
io: Io,

pub fn init(allocator: std.mem.Allocator, io: Io, path: []const u8) World {
    return .{
        .path = path,
        .regions = RegionMap.init(allocator),
        .allocator = allocator,
        .io = io,
    };
}

pub fn deinit(self: *World) void {
    var it = self.regions.valueIterator();
    while (it.next()) |region| {
        region.deinit(self.allocator);
    }
    self.regions.deinit();
}

pub fn scanRegions(self: *World) !void {
    self.regions.clearRetainingCapacity();

    const region_path = try self.buildRegionPath();
    defer self.allocator.free(region_path);

    var dir = Dir.openDir(.cwd(), self.io, region_path, .{ .iterate = true }) catch |err| {
        std.log.warn("Cannot open region directory: {s} ({})", .{ region_path, err });
        return;
    };
    defer dir.close(self.io);

    var iter = dir.iterate();
    while (iter.next(self.io) catch null) |entry| {
        if (entry.kind != .file) continue;

        const name = entry.name;
        if (!std.mem.endsWith(u8, name, ".mca")) continue;

        const parsed = mca.parseRegionFilename(name) orelse continue;

        const mca_path = try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ region_path, std.fs.path.sep, name });
        defer self.allocator.free(mca_path);

        const header = mca.readRegionHeader(self.io, mca_path) catch |err| {
            std.log.warn("Failed to read {s}: {}", .{ name, err });
            continue;
        };

        var region = Region.loadFromHeader(parsed.x, parsed.z, &header);
        region.loadPixels(self.allocator, self.io, mca_path, &header);
        const key = RegionKey{ .x = parsed.x, .z = parsed.z };
        self.regions.put(key, region) catch continue;
    }

    std.log.info("Loaded {} regions for {s}", .{ self.regions.count(), @tagName(self.dimension) });
}

pub fn setDimension(self: *World, dim: Dimension) !void {
    self.dimension = dim;
    try self.scanRegions();
}

pub fn getRegion(self: *const World, rx: i32, rz: i32) ?*const Region {
    const key = RegionKey{ .x = rx, .z = rz };
    return if (self.regions.getPtr(key)) |ptr| ptr else null;
}

pub fn getRegionMut(self: *World, rx: i32, rz: i32) ?*Region {
    const key = RegionKey{ .x = rx, .z = rz };
    return self.regions.getPtr(key);
}

pub fn deleteChunks(self: *World, chunks: []const Selection.ChunkCoord) !u32 {
    // Group chunks by region
    var region_chunks = std.AutoHashMap(RegionKey, std.ArrayListUnmanaged(mca.LocalChunk)).init(self.allocator);
    defer {
        var it = region_chunks.valueIterator();
        while (it.next()) |list| list.deinit(self.allocator);
        region_chunks.deinit();
    }

    for (chunks) |chunk| {
        const rx = @divFloor(chunk.cx, 32);
        const rz = @divFloor(chunk.cz, 32);
        const lx: u5 = @intCast(@mod(chunk.cx, 32));
        const lz: u5 = @intCast(@mod(chunk.cz, 32));

        const key = RegionKey{ .x = rx, .z = rz };
        const entry = try region_chunks.getOrPut(key);
        if (!entry.found_existing) {
            entry.value_ptr.* = .empty;
        }
        try entry.value_ptr.append(self.allocator, .{ .x = lx, .z = lz });
    }

    var deleted: u32 = 0;

    var it = region_chunks.iterator();
    while (it.next()) |entry| {
        const rkey = entry.key_ptr.*;
        const chunk_list = entry.value_ptr.items;

        // Build MCA path
        const region_path = try self.buildRegionPath();
        defer self.allocator.free(region_path);

        const sep = std.fs.path.sep;

        const mca_path = try std.fmt.allocPrint(self.allocator, "{s}{c}r.{d}.{d}.mca", .{ region_path, sep, rkey.x, rkey.z });
        defer self.allocator.free(mca_path);

        // Delete from MCA
        mca.deleteChunks(self.io, mca_path, chunk_list) catch |err| {
            std.log.warn("Failed to delete chunks from r.{d}.{d}.mca: {}", .{ rkey.x, rkey.z, err });
            continue;
        };

        // Also try to delete from .entities and .poi directories
        for ([_][]const u8{ "entities", "poi" }) |sub| {
            const parent_path = try self.buildDimensionPath();
            defer self.allocator.free(parent_path);
            const sub_path = std.fmt.allocPrint(self.allocator, "{s}{c}{s}{c}r.{d}.{d}.mca", .{ parent_path, sep, sub, sep, rkey.x, rkey.z }) catch continue;
            defer self.allocator.free(sub_path);
            mca.deleteChunks(self.io, sub_path, chunk_list) catch {};
        }

        // Update in-memory model
        if (self.getRegionMut(rkey.x, rkey.z)) |region| {
            for (chunk_list) |lc| {
                region.setChunkAbsent(lc.x, lc.z);
                deleted += 1;
            }
        }
    }

    return deleted;
}

pub fn totalChunkCount(self: *const World) u32 {
    var count: u32 = 0;
    var it = self.regions.valueIterator();
    while (it.next()) |region| {
        count += region.chunkCount();
    }
    return count;
}

fn buildRegionPath(self: *const World) ![]const u8 {
    return try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ self.path, std.fs.path.sep, self.dimension.regionPath() });
}

fn buildDimensionPath(self: *const World) ![]const u8 {
    const dim_prefix: []const u8 = switch (self.dimension) {
        .overworld => "",
        .nether => "DIM-1",
        .the_end => "DIM1",
    };
    if (dim_prefix.len == 0) return try self.allocator.dupe(u8, self.path);
    return try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ self.path, std.fs.path.sep, dim_prefix });
}

pub fn extractWorldName(path: []const u8) []const u8 {
    const trimmed = std.mem.trimEnd(u8, path, "/\\");
    if (std.mem.lastIndexOfAny(u8, trimmed, "/\\")) |idx| {
        return trimmed[idx + 1 ..];
    }
    return trimmed;
}
