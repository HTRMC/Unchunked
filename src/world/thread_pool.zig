const std = @import("std");

pub const ThreadPool = struct {
    const QUEUE_SIZE = 8192;

    const Job = struct {
        func: *const fn (*anyopaque) void,
        data: *anyopaque,
    };

    // Vyukov bounded MPMC queue — each slot has a sequence counter
    const Slot = struct {
        sequence: std.atomic.Value(usize),
        job: Job,
    };

    slots: []Slot = undefined,
    enqueue_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    dequeue_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    threads: []std.Thread,
    allocator: std.mem.Allocator,
    shutdown: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    active_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    pub fn init(self: *ThreadPool, allocator: std.mem.Allocator, thread_count: u32) !void {
        const slots = try allocator.alloc(Slot, QUEUE_SIZE);
        for (slots, 0..) |*slot, i| {
            slot.* = .{
                .sequence = std.atomic.Value(usize).init(i),
                .job = undefined,
            };
        }

        self.* = .{
            .slots = slots,
            .threads = try allocator.alloc(std.Thread, thread_count),
            .allocator = allocator,
        };

        for (self.threads) |*t| {
            t.* = try std.Thread.spawn(.{}, workerLoop, .{self});
        }

        std.log.info("Thread pool: {} workers", .{thread_count});
    }

    pub fn deinit(self: *ThreadPool) void {
        self.shutdown.store(true, .release);
        for (self.threads) |t| t.detach();
        self.allocator.free(self.threads);
        self.allocator.free(self.slots);
    }

    pub fn submitPtr(self: *ThreadPool, comptime func: anytype, ptr: anytype) void {
        const PtrType = @TypeOf(ptr);
        const Wrapper = struct {
            fn call(raw: *anyopaque) void {
                const typed: PtrType = @ptrCast(@alignCast(raw));
                func(typed);
            }
        };

        self.enqueue(.{ .func = Wrapper.call, .data = @ptrCast(@alignCast(ptr)) });
    }

    fn enqueue(self: *ThreadPool, job: Job) void {
        var pos = self.enqueue_pos.load(.monotonic);
        while (true) {
            const slot = &self.slots[pos % QUEUE_SIZE];
            const seq = slot.sequence.load(.acquire);
            const diff = @as(isize, @intCast(seq)) - @as(isize, @intCast(pos));

            if (diff == 0) {
                // Slot is ready for writing
                if (self.enqueue_pos.cmpxchgWeak(pos, pos + 1, .acq_rel, .monotonic)) |updated| {
                    pos = updated;
                    continue;
                }
                slot.job = job;
                slot.sequence.store(pos + 1, .release);
                return;
            } else if (diff < 0) {
                // Queue is full
                return;
            } else {
                // Another enqueuer beat us, reload
                pos = self.enqueue_pos.load(.monotonic);
            }
        }
    }

    fn dequeue(self: *ThreadPool) ?Job {
        var pos = self.dequeue_pos.load(.monotonic);
        while (true) {
            const slot = &self.slots[pos % QUEUE_SIZE];
            const seq = slot.sequence.load(.acquire);
            const diff = @as(isize, @intCast(seq)) - @as(isize, @intCast(pos + 1));

            if (diff == 0) {
                // Slot has data ready
                if (self.dequeue_pos.cmpxchgWeak(pos, pos + 1, .acq_rel, .monotonic)) |updated| {
                    pos = updated;
                    continue;
                }
                const job = slot.job;
                slot.sequence.store(pos + QUEUE_SIZE, .release);
                return job;
            } else if (diff < 0) {
                // Queue is empty
                return null;
            } else {
                pos = self.dequeue_pos.load(.monotonic);
            }
        }
    }

    pub fn threadCount(self: *const ThreadPool) u32 {
        return @intCast(self.threads.len);
    }

    pub fn resize(self: *ThreadPool, new_count: u32) void {
        if (new_count == self.threads.len or new_count == 0) return;

        // Signal shutdown and join all threads
        self.shutdown.store(true, .release);
        for (self.threads) |t| t.join();

        // Drain remaining queue items (just skip them)
        self.shutdown.store(false, .release);
        self.enqueue_pos.store(0, .release);
        self.dequeue_pos.store(0, .release);
        self.active_count.store(0, .release);
        for (self.slots, 0..) |*slot, i| {
            slot.sequence.store(i, .release);
        }
        self.allocator.free(self.threads);

        self.threads = self.allocator.alloc(std.Thread, new_count) catch return;
        for (self.threads) |*t| {
            t.* = std.Thread.spawn(.{}, workerLoop, .{self}) catch return;
        }
        std.log.info("Thread pool resized to {} workers", .{new_count});
    }

    pub fn waitIdle(self: *ThreadPool) void {
        while (true) {
            const e = self.enqueue_pos.load(.acquire);
            const d = self.dequeue_pos.load(.acquire);
            const active = self.active_count.load(.acquire);
            if (e == d and active == 0) break;
            std.Thread.yield() catch {};
        }
    }

    fn workerLoop(pool: *ThreadPool) void {
        while (!pool.shutdown.load(.acquire)) {
            if (pool.dequeue()) |job| {
                _ = pool.active_count.fetchAdd(1, .acq_rel);
                job.func(job.data);
                _ = pool.active_count.fetchSub(1, .acq_rel);
            } else {
                std.Thread.yield() catch {};
            }
        }
    }
};
