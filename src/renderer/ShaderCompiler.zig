const std = @import("std");
const shaderc = @import("../platform/shaderc.zig");

const ShaderCompiler = @This();

compiler: shaderc.shaderc_compiler_t,

pub const Error = error{
    CompilerInitFailed,
    CompilationFailed,
};

pub fn init() Error!ShaderCompiler {
    const compiler = shaderc.compiler_initialize();
    if (compiler == null) return error.CompilerInitFailed;
    return .{ .compiler = compiler };
}

pub fn deinit(self: *ShaderCompiler) void {
    shaderc.compiler_release(self.compiler);
}

pub fn compile(
    self: *ShaderCompiler,
    source: [*:0]const u8,
    source_len: usize,
    kind: shaderc.shaderc_shader_kind,
    filename: [*:0]const u8,
) Error![]const u32 {
    const result = shaderc.compile_into_spv(
        self.compiler,
        source,
        source_len,
        kind,
        filename,
        "main",
        null,
    );
    defer shaderc.result_release(result);

    if (shaderc.result_get_compilation_status(result) != shaderc.shaderc_compilation_status_success) {
        const err_msg = shaderc.result_get_error_message(result);
        std.log.err("Shader compilation failed ({s}): {s}", .{ filename, err_msg });
        return error.CompilationFailed;
    }

    const bytes = shaderc.result_get_bytes(result);
    const length = shaderc.result_get_length(result);
    const word_count = length / 4;

    // Copy SPIR-V data (result is freed on defer)
    const words: [*]const u32 = @ptrCast(@alignCast(bytes));
    const owned = std.heap.page_allocator.alloc(u32, word_count) catch return error.CompilationFailed;
    @memcpy(owned, words[0..word_count]);

    return owned;
}

pub fn free(spirv: []const u32) void {
    std.heap.page_allocator.free(spirv);
}
