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
            .nether => "DIM-1" ++ std.fs.path.sep_str ++ "region",
            .the_end => "DIM1" ++ std.fs.path.sep_str ++ "region",
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

path: []u8,
dimension: Dimension = .overworld,
regions: RegionMap,
allocator: std.mem.Allocator,
io: Io,
region_dir_path: ?[]u8 = null,
bg_jobs: [MAX_BG_JOBS]?*BgJob = .{null} ** MAX_BG_JOBS,

pub fn init(allocator: std.mem.Allocator, io: Io, path: []u8) World {
    return .{
        .path = path,
        .regions = RegionMap.init(allocator),
        .allocator = allocator,
        .io = io,
    };
}

pub fn deinit(self: *World) void {
    self.waitForBgJobs();
    var it = self.regions.valueIterator();
    while (it.next()) |region| {
        region.deinit(self.allocator);
    }
    self.regions.deinit();
    if (self.region_dir_path) |p| self.allocator.free(p);
    self.allocator.free(self.path);
}

fn waitForBgJobs(self: *World) void {
    for (&self.bg_jobs) |*slot| {
        const job = slot.* orelse continue;
        if (job.thread) |t| t.join();
        self.allocator.free(job.mca_path);
        self.allocator.destroy(job);
        slot.* = null;
    }
}

/// Phase 1: Scan directory for region files and read headers only (fast, no pixel loading)
pub fn scanRegions(self: *World) !void {
    self.waitForBgJobs();
    var cleanup_it = self.regions.valueIterator();
    while (cleanup_it.next()) |region| {
        region.deinit(self.allocator);
    }
    self.regions.clearRetainingCapacity();

    if (self.region_dir_path) |p| self.allocator.free(p);
    self.region_dir_path = try self.buildRegionPath();

    const region_path = self.region_dir_path.?;

    var dir = Dir.openDir(.cwd(), self.io, region_path, .{ .iterate = true }) catch |err| {
        std.log.warn("Cannot open region directory: {s} ({})", .{ region_path, err });
        return;
    };
    defer dir.close(self.io);

    var iter = dir.iterate();
    while (iter.next(self.io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".mca")) continue;

        const parsed = mca.parseRegionFilename(entry.name) orelse continue;

        const mca_path = std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ region_path, std.fs.path.sep, entry.name }) catch continue;
        defer self.allocator.free(mca_path);

        const header = mca.readRegionHeader(self.io, mca_path) catch continue;
        const region = Region.loadFromHeader(parsed.x, parsed.z, &header);
        const key = RegionKey{ .x = parsed.x, .z = parsed.z };
        self.regions.put(key, region) catch continue;
    }

    std.log.info("Scanned {} regions for {s}", .{ self.regions.count(), @tagName(self.dimension) });
}

const MAX_BG_JOBS = 8;

const BgJob = struct {
    region: *Region,
    header: mca.RegionHeader,
    mca_path: []u8,
    allocator: std.mem.Allocator,
    key: RegionKey,
    thread: ?std.Thread = null,
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

fn bgWorker(job: *BgJob) void {
    const io = Io.Threaded.global_single_threaded.io();
    job.region.loadPixels(job.allocator, io, job.mca_path, &job.header);
    job.done.store(true, .release);
}

/// Called each frame: spawns background loaders for visible unloaded regions,
/// and collects completed ones into new_keys for atlas upload.
pub fn loadVisibleRegions(
    self: *World,
    min_rx: i32,
    max_rx: i32,
    min_rz: i32,
    max_rz: i32,
    new_keys: *std.ArrayListUnmanaged(RegionKey),
) void {
    // Collect completed background jobs
    for (&self.bg_jobs) |*slot| {
        const job = slot.* orelse continue;
        if (!job.done.load(.acquire)) continue;

        // Join thread
        if (job.thread) |t| t.join();

        // Report completion
        if (job.region.pixels != null) {
            new_keys.append(self.allocator, job.key) catch {};
        }

        // Clean up
        self.allocator.free(job.mca_path);
        self.allocator.destroy(job);
        slot.* = null;
    }

    // Count active jobs
    var active: u32 = 0;
    for (self.bg_jobs) |slot| {
        if (slot != null) active += 1;
    }

    // Spawn new jobs for visible unloaded regions (iterate existing regions, not coordinates)
    const region_path = self.region_dir_path orelse return;

    var region_it = self.regions.iterator();
    while (region_it.next()) |entry| {
        if (active >= MAX_BG_JOBS) return;

        const rx = entry.key_ptr.x;
        const rz = entry.key_ptr.z;

        // Skip if not visible
        if (rx < min_rx or rx > max_rx or rz < min_rz or rz > max_rz) continue;

        const region = entry.value_ptr;
        if (region.pixels != null) continue;
        if (region.loading) continue;

        const mca_path = std.fmt.allocPrint(self.allocator, "{s}{c}r.{d}.{d}.mca", .{
            region_path, std.fs.path.sep, rx, rz,
        }) catch continue;

            const header = mca.readRegionHeader(self.io, mca_path) catch {
                self.allocator.free(mca_path);
                continue;
            };

            const job = self.allocator.create(BgJob) catch {
                self.allocator.free(mca_path);
                continue;
            };
            job.* = .{
                .region = region,
                .header = header,
                .mca_path = mca_path,
                .allocator = self.allocator,
                .key = .{ .x = rx, .z = rz },
            };

            // Find free slot
            var found_slot = false;
            for (&self.bg_jobs) |*slot| {
                if (slot.* == null) {
                    slot.* = job;
                    found_slot = true;
                    break;
                }
            }
            if (!found_slot) {
                self.allocator.free(mca_path);
                self.allocator.destroy(job);
                continue;
            }

            region.loading = true;
            job.thread = std.Thread.spawn(.{}, bgWorker, .{job}) catch {
                region.loading = false;
                self.allocator.free(mca_path);
                self.allocator.destroy(job);
                continue;
            };
            active += 1;
    }
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

        const region_path = self.region_dir_path orelse continue;
        const sep = std.fs.path.sep;

        const mca_path = std.fmt.allocPrint(self.allocator, "{s}{c}r.{d}.{d}.mca", .{ region_path, sep, rkey.x, rkey.z }) catch continue;
        defer self.allocator.free(mca_path);

        mca.deleteChunks(self.io, mca_path, chunk_list) catch |err| {
            std.log.warn("Failed to delete chunks from r.{d}.{d}.mca: {}", .{ rkey.x, rkey.z, err });
            continue;
        };

        for ([_][]const u8{ "entities", "poi" }) |sub| {
            const parent_path = self.buildDimensionPath() catch continue;
            defer self.allocator.free(parent_path);
            const sub_path = std.fmt.allocPrint(self.allocator, "{s}{c}{s}{c}r.{d}.{d}.mca", .{ parent_path, sep, sub, sep, rkey.x, rkey.z }) catch continue;
            defer self.allocator.free(sub_path);
            mca.deleteChunks(self.io, sub_path, chunk_list) catch {};
        }

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

fn buildRegionPath(self: *const World) ![]u8 {
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
