const std = @import("std");

fn libName(b: *std.Build, name: []const u8) []const u8 {
    return b.fmt("lib{s}.a", .{name});
}

fn linkDependencies(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const target = exe.root_module.resolved_target.?;
    const t = target.result;

    exe.root_module.link_libc = true;
    exe.root_module.link_libcpp = true;

    const deps_name = b.fmt("unchunked_deps_{s}-{s}-{s}", .{
        @tagName(t.cpu.arch),
        @tagName(t.os.tag),
        @tagName(t.abi),
    });

    const headers_dep = b.lazyDependency("unchunked_deps_headers", .{}) orelse {
        std.log.info("Downloading headers...", .{});
        return;
    };
    exe.root_module.addIncludePath(headers_dep.path(""));

    const lib_dep = b.lazyDependency(deps_name, .{}) orelse {
        std.log.info("Downloading {s}...", .{deps_name});
        return;
    };
    exe.root_module.addObjectFile(lib_dep.path(libName(b, "glfw")));
    exe.root_module.addObjectFile(lib_dep.path(libName(b, "volk")));
    exe.root_module.addObjectFile(lib_dep.path(libName(b, "stb_image")));
    exe.root_module.addObjectFile(lib_dep.path(libName(b, "shaderc_combined")));

    // FreeType — compiled from source
    linkFreetype(b, exe);

    if (t.os.tag == .windows) {
        exe.root_module.linkSystemLibrary("gdi32", .{});
        exe.root_module.linkSystemLibrary("user32", .{});
        exe.root_module.linkSystemLibrary("shell32", .{});
        exe.root_module.linkSystemLibrary("opengl32", .{});
        exe.root_module.linkSystemLibrary("dwmapi", .{});
    }
}

fn linkFreetype(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const target = exe.root_module.resolved_target.?;

    const freetype_dep = b.lazyDependency("freetype", .{}) orelse {
        std.log.info("Downloading freetype...", .{});
        return;
    };

    const freetype_lib = b.addLibrary(.{
        .name = "freetype",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
    });

    freetype_lib.root_module.addCMacro("FT2_BUILD_LIBRARY", "1");
    freetype_lib.root_module.addIncludePath(freetype_dep.path("include"));

    const freetype_sources = [_][]const u8{
        "src/base/ftsystem.c",
        "src/base/ftinit.c",
        "src/base/ftdebug.c",
        "src/base/ftbase.c",
        "src/base/ftbbox.c",
        "src/base/ftbitmap.c",
        "src/base/ftglyph.c",
        "src/base/ftstroke.c",
        "src/base/ftsynth.c",
        "src/base/ftmm.c",
        "src/truetype/truetype.c",
        "src/cff/cff.c",
        "src/cid/type1cid.c",
        "src/type1/type1.c",
        "src/type42/type42.c",
        "src/pfr/pfr.c",
        "src/winfonts/winfnt.c",
        "src/pcf/pcf.c",
        "src/bdf/bdf.c",
        "src/sfnt/sfnt.c",
        "src/autofit/autofit.c",
        "src/pshinter/pshinter.c",
        "src/raster/raster.c",
        "src/smooth/smooth.c",
        "src/psaux/psaux.c",
        "src/psnames/psnames.c",
        "src/gzip/ftgzip.c",
        "src/lzw/ftlzw.c",
        "src/sdf/sdf.c",
        "src/svg/svg.c",
    };

    freetype_lib.root_module.addCSourceFiles(.{
        .root = freetype_dep.path(""),
        .files = &freetype_sources,
    });

    exe.root_module.addIncludePath(freetype_dep.path("include"));
    exe.root_module.linkLibrary(freetype_lib);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Unchunked",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const console_enabled = b.option(bool, "console", "Show console window on Windows") orelse false;

    linkDependencies(b, exe);

    // Hide the console window on Windows unless -Dconsole=true
    if (exe.root_module.resolved_target.?.result.os.tag == .windows and !console_enabled) {
        exe.subsystem = .windows;
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
