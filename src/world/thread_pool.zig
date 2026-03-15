const std = @import("std");

pub const ThreadPool = struct {
    const Job = struct {
        func: *const fn (*anyopaque) void,
        data: *anyopaque,
    };

    const QUEUE_SIZE = 512;

    threads: []std.Thread,
    queue: [QUEUE_SIZE]Job = undefined,
    head: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    tail: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    shutdown: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    active_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, thread_count: u32) !ThreadPool {
        var pool = ThreadPool{
            .threads = try allocator.alloc(std.Thread, thread_count),
            .allocator = allocator,
        };

        for (pool.threads) |*t| {
            t.* = try std.Thread.spawn(.{}, workerLoop, .{&pool});
        }

        std.log.info("Thread pool: {} workers", .{thread_count});
        return pool;
    }

    pub fn deinit(self: *ThreadPool) void {
        self.shutdown.store(true, .release);

        for (self.threads) |t| {
            t.join();
        }
        self.allocator.free(self.threads);
    }

    pub fn submitPtr(self: *ThreadPool, comptime func: anytype, ptr: anytype) void {
        const PtrType = @TypeOf(ptr);
        const Wrapper = struct {
            fn call(raw: *anyopaque) void {
                const typed: PtrType = @ptrCast(@alignCast(raw));
                func(typed);
            }
        };

        const t = self.tail.load(.acquire);
        const h = self.head.load(.acquire);
        const count = if (t >= h) t - h else QUEUE_SIZE - h + t;
        if (count >= QUEUE_SIZE - 1) return;

        self.queue[t % QUEUE_SIZE] = .{
            .func = Wrapper.call,
            .data = @ptrCast(@alignCast(ptr)),
        };
        self.tail.store((t + 1) % QUEUE_SIZE, .release);
    }

    pub fn threadCount(self: *const ThreadPool) u32 {
        return @intCast(self.threads.len);
    }

    pub fn resize(self: *ThreadPool, new_count: u32) void {
        if (new_count == self.threads.len or new_count == 0) return;

        self.waitIdle();

        // Shutdown old threads
        self.shutdown.store(true, .release);
        for (self.threads) |t| t.join();

        // Reset
        self.shutdown.store(false, .release);
        self.head.store(0, .release);
        self.tail.store(0, .release);
        self.active_count.store(0, .release);
        self.allocator.free(self.threads);

        self.threads = self.allocator.alloc(std.Thread, new_count) catch return;
        for (self.threads) |*t| {
            t.* = std.Thread.spawn(.{}, workerLoop, .{self}) catch return;
        }
        std.log.info("Thread pool resized to {} workers", .{new_count});
    }

    pub fn waitIdle(self: *ThreadPool) void {
        while (true) {
            const h = self.head.load(.acquire);
            const t = self.tail.load(.acquire);
            const active = self.active_count.load(.acquire);
            if (h == t and active == 0) break;
            std.Thread.yield() catch {};
        }
    }

    fn workerLoop(pool: *ThreadPool) void {
        while (!pool.shutdown.load(.acquire)) {
            const h = pool.head.load(.acquire);
            const t = pool.tail.load(.acquire);

            if (h == t) {
                // No work, spin briefly then yield
                std.Thread.yield() catch {};
                continue;
            }

            // Try to claim a job
            const next = (h + 1) % QUEUE_SIZE;
            if (pool.head.cmpxchgWeak(h, next, .acq_rel, .acquire)) |_| {
                continue; // another thread got it
            }

            const job = pool.queue[h % QUEUE_SIZE];
            _ = pool.active_count.fetchAdd(1, .acq_rel);
            job.func(job.data);
            _ = pool.active_count.fetchSub(1, .acq_rel);
        }
    }
};
