const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const mca = @import("mca.zig");
const Region = @import("Region.zig");
const Selection = @import("../app/Selection.zig");
pub const ThreadPool = @import("thread_pool.zig").ThreadPool;

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

const LoadJob = struct {
    region: *Region,
    mca_path: []u8,
    allocator: std.mem.Allocator,
    key: RegionKey,
    pixels: ?[]u8 = null,
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

const MAX_INFLIGHT = 128;

path: []u8,
dimension: Dimension = .overworld,
regions: RegionMap,
allocator: std.mem.Allocator,
io: Io,
region_dir_path: ?[]u8 = null,
pool: *ThreadPool,
pending_jobs: [MAX_INFLIGHT]?*LoadJob = .{null} ** MAX_INFLIGHT,

pub fn init(allocator: std.mem.Allocator, io: Io, path: []u8, pool: *ThreadPool) World {
    return .{
        .path = path,
        .regions = RegionMap.init(allocator),
        .allocator = allocator,
        .io = io,
        .pool = pool,
    };
}

pub fn deinit(self: *World) void {
    // Don't wait — just clean up pending jobs (pool shutdown handles thread joining)
    for (&self.pending_jobs) |*slot| {
        if (slot.*) |job| {
            self.allocator.free(job.mca_path);
            self.allocator.destroy(job);
            slot.* = null;
        }
    }
    var it = self.regions.valueIterator();
    while (it.next()) |region| {
        region.deinit(self.allocator);
    }
    self.regions.deinit();
    if (self.region_dir_path) |p| self.allocator.free(p);
    self.allocator.free(self.path);
}

pub fn scanRegions(self: *World) !void {
    self.pool.waitIdle();
    for (&self.pending_jobs) |*slot| {
        if (slot.*) |job| {
            self.allocator.free(job.mca_path);
            self.allocator.destroy(job);
            slot.* = null;
        }
    }
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

        const key = RegionKey{ .x = parsed.x, .z = parsed.z };
        const region = Region{ .rx = parsed.x, .rz = parsed.z };
        self.regions.put(key, region) catch continue;
    }

    std.log.info("Scanned {} regions for {s}", .{ self.regions.count(), @tagName(self.dimension) });
}

fn loadJobWorker(job: *LoadJob) void {
    const io = Io.Threaded.global_single_threaded.io();
    const header = mca.readRegionHeader(io, job.mca_path) catch {
        job.done.store(true, .release);
        return;
    };
    const px = job.allocator.alloc(u8, Region.PIXEL_DATA_SIZE) catch {
        job.done.store(true, .release);
        return;
    };
    Region.renderPixels(px, job.allocator, io, job.mca_path, &header, job.region);
    job.pixels = px;
    job.done.store(true, .release);
}

pub const CompletedRegion = struct {
    key: RegionKey,
    pixels: []u8,
};

pub fn loadRegions(
    self: *World,
    center_rx: i32,
    center_rz: i32,
    completed: *std.ArrayListUnmanaged(CompletedRegion),
) void {
    // Collect completed jobs
    for (&self.pending_jobs) |*slot| {
        const job = slot.* orelse continue;
        if (!job.done.load(.acquire)) continue;

        if (job.pixels) |px| {
            job.region.pixels = px;
            completed.append(self.allocator, .{ .key = job.key, .pixels = px }) catch {};
        }
        job.region.loading = false;
        self.allocator.free(job.mca_path);
        self.allocator.destroy(job);
        slot.* = null;
    }

    // Count active
    var active: u32 = 0;
    for (self.pending_jobs) |slot| {
        if (slot != null) active += 1;
    }
    if (active >= MAX_INFLIGHT) return;

    // Collect unloaded regions, sort by distance
    const max_pending = 512;
    var pending: [max_pending]RegionKey = undefined;
    var pending_count: u32 = 0;

    var region_it = self.regions.iterator();
    while (region_it.next()) |entry| {
        if (pending_count >= max_pending) break;
        const region = entry.value_ptr;
        if (region.pixels != null or region.loading) continue;
        pending[pending_count] = entry.key_ptr.*;
        pending_count += 1;
    }

    if (pending_count == 0) return;

    const SortCtx = struct {
        cx: i32,
        cz: i32,
        pub fn lessThan(ctx: @This(), a: RegionKey, b: RegionKey) bool {
            const da = (a.x - ctx.cx) * (a.x - ctx.cx) + (a.z - ctx.cz) * (a.z - ctx.cz);
            const db = (b.x - ctx.cx) * (b.x - ctx.cx) + (b.z - ctx.cz) * (b.z - ctx.cz);
            return da < db;
        }
    };
    std.mem.sortUnstable(RegionKey, pending[0..pending_count], SortCtx{ .cx = center_rx, .cz = center_rz }, SortCtx.lessThan);

    const region_path = self.region_dir_path orelse return;

    for (pending[0..pending_count]) |rk| {
        if (active >= MAX_INFLIGHT) return;

        const region = self.regions.getPtr(rk) orelse continue;
        if (region.pixels != null or region.loading) continue;

        const mca_path = std.fmt.allocPrint(self.allocator, "{s}{c}r.{d}.{d}.mca", .{
            region_path, std.fs.path.sep, rk.x, rk.z,
        }) catch continue;

        const job = self.allocator.create(LoadJob) catch {
            self.allocator.free(mca_path);
            continue;
        };
        job.* = .{
            .region = region,
            .mca_path = mca_path,
            .allocator = self.allocator,
            .key = rk,
        };

        var slot_idx: ?usize = null;
        for (self.pending_jobs, 0..) |slot, i| {
            if (slot == null) {
                slot_idx = i;
                break;
            }
        }
        if (slot_idx == null) {
            self.allocator.free(mca_path);
            self.allocator.destroy(job);
            continue;
        }

        self.pending_jobs[slot_idx.?] = job;

        if (!self.pool.submitPtr(loadJobWorker, job)) {
            self.pending_jobs[slot_idx.?] = null;
            self.allocator.free(mca_path);
            self.allocator.destroy(job);
            continue;
        }

        region.loading = true;
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
