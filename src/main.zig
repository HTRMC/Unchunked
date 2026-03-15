const std = @import("std");
const Window = @import("platform/Window.zig").Window;
const App = @import("app/App.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var window = try Window.init(.{
        .width = 1280,
        .height = 720,
        .title = "Unchunked",
    });
    defer window.deinit();

    var app = try App.init(allocator, init.io, init.environ_map, &window);
    defer app.deinit();
    app.setupCallbacks();

    // Check for CLI world path argument
    {
        var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
        defer args_iter.deinit();

        _ = args_iter.skip(); // skip program name

        if (args_iter.next()) |path| {
            app.openWorld(path);
        }
    }

    std.log.info("Entering main loop...", .{});

    while (!window.shouldClose()) {
        window.pollEvents();
        app.update() catch |err| {
            std.log.err("Frame error: {}", .{err});
        };
    }

    std.log.info("Shutting down...", .{});
}
