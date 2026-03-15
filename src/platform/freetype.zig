const std = @import("std");
const ft = @import("c.zig").ft;

pub const Library = ft.FT_Library;
pub const Face = ft.FT_Face;
pub const GlyphSlot = ft.FT_GlyphSlot;
pub const Error = ft.FT_Error;

pub const FT_LOAD_RENDER = ft.FT_LOAD_RENDER;
pub const FT_LOAD_DEFAULT = ft.FT_LOAD_DEFAULT;

pub const FreetypeError = error{
    InitFailed,
    FaceLoadFailed,
    SizeSetFailed,
    GlyphLoadFailed,
};

pub fn initLibrary() FreetypeError!Library {
    var lib: Library = null;
    if (ft.FT_Init_FreeType(&lib) != 0) return error.InitFailed;
    return lib;
}

pub fn doneLibrary(lib: Library) void {
    _ = ft.FT_Done_FreeType(lib);
}

pub fn newFace(lib: Library, path: [*:0]const u8) FreetypeError!Face {
    var face: Face = null;
    if (ft.FT_New_Face(lib, path, 0, &face) != 0) return error.FaceLoadFailed;
    return face;
}

pub fn newMemoryFace(lib: Library, data: []const u8) FreetypeError!Face {
    var face: Face = null;
    if (ft.FT_New_Memory_Face(lib, data.ptr, @intCast(data.len), 0, &face) != 0) return error.FaceLoadFailed;
    return face;
}

pub fn doneFace(face: Face) void {
    _ = ft.FT_Done_Face(face);
}

pub fn setPixelSizes(face: Face, width: u32, height: u32) FreetypeError!void {
    if (ft.FT_Set_Pixel_Sizes(face, width, height) != 0) return error.SizeSetFailed;
}

pub fn loadChar(face: Face, char_code: u32, flags: i32) FreetypeError!void {
    if (ft.FT_Load_Char(face, char_code, flags) != 0) return error.GlyphLoadFailed;
}

pub const GlyphInfo = struct {
    width: u32,
    height: u32,
    bearing_x: i32,
    bearing_y: i32,
    advance_x: i32,
    bitmap: [*]const u8,
    pitch: i32,
};

pub fn getGlyphInfo(face: Face) GlyphInfo {
    const g = face.*.glyph;
    const empty: [1]u8 = .{0};
    return .{
        .width = g.*.bitmap.width,
        .height = g.*.bitmap.rows,
        .bearing_x = @intCast(g.*.bitmap_left),
        .bearing_y = @intCast(g.*.bitmap_top),
        .advance_x = @intCast(g.*.advance.x >> 6),
        .bitmap = g.*.bitmap.buffer orelse &empty,
        .pitch = g.*.bitmap.pitch,
    };
}

pub fn findSystemFont() ?[*:0]const u8 {
    const builtin = @import("builtin");
    if (comptime builtin.os.tag == .windows) {
        // Segoe UI — present on all Windows 10+
        return "C:\\Windows\\Fonts\\segoeui.ttf";
    } else {
        // Common Linux font paths
        const paths = [_][*:0]const u8{
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/TTF/DejaVuSans.ttf",
            "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/noto/NotoSans-Regular.ttf",
        };
        for (paths) |p| {
            // Can't check file existence easily without Io, just return first
            return p;
        }
        return null;
    }
}
