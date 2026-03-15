const std = @import("std");
const block_colors = @import("block_colors.zig");

pub const Color = block_colors.Color;

pub const BiomeTint = struct {
    name: []const u8,
    grass: Color,
    foliage: Color,
    water: Color,
};

pub const TintType = enum { grass, foliage, water };

/// Blocks that get grass tint
pub fn isGrassTinted(name: []const u8) bool {
    const stripped = if (std.mem.startsWith(u8, name, "minecraft:")) name["minecraft:".len..] else name;
    return std.mem.eql(u8, stripped, "grass_block") or
        std.mem.eql(u8, stripped, "short_grass") or
        std.mem.eql(u8, stripped, "grass") or
        std.mem.eql(u8, stripped, "tall_grass") or
        std.mem.eql(u8, stripped, "fern") or
        std.mem.eql(u8, stripped, "large_fern") or
        std.mem.eql(u8, stripped, "bush") or
        std.mem.eql(u8, stripped, "melon_stem") or
        std.mem.eql(u8, stripped, "attached_melon_stem") or
        std.mem.eql(u8, stripped, "pumpkin_stem") or
        std.mem.eql(u8, stripped, "attached_pumpkin_stem");
}

/// Blocks that get foliage tint
pub fn isFoliageTinted(name: []const u8) bool {
    const stripped = if (std.mem.startsWith(u8, name, "minecraft:")) name["minecraft:".len..] else name;
    return std.mem.eql(u8, stripped, "oak_leaves") or
        std.mem.eql(u8, stripped, "acacia_leaves") or
        std.mem.eql(u8, stripped, "dark_oak_leaves") or
        std.mem.eql(u8, stripped, "jungle_leaves") or
        std.mem.eql(u8, stripped, "mangrove_leaves") or
        std.mem.eql(u8, stripped, "vine");
}

/// Blocks with fixed tint (not biome-dependent)
pub fn getStaticTint(name: []const u8) ?Color {
    const stripped = if (std.mem.startsWith(u8, name, "minecraft:")) name["minecraft:".len..] else name;
    if (std.mem.eql(u8, stripped, "birch_leaves")) return .{ .r = 0x80, .g = 0xa7, .b = 0x55 };
    if (std.mem.eql(u8, stripped, "spruce_leaves")) return .{ .r = 0x61, .g = 0x99, .b = 0x61 };
    if (std.mem.eql(u8, stripped, "lily_pad")) return .{ .r = 0x20, .g = 0x80, .b = 0x30 };
    return null;
}

/// Apply multiplicative tint: result = (tint * color) >> 8 per channel
pub fn applyTint(color: Color, tint: Color) Color {
    return .{
        .r = @intCast((@as(u16, tint.r) * @as(u16, color.r)) >> 8),
        .g = @intCast((@as(u16, tint.g) * @as(u16, color.g)) >> 8),
        .b = @intCast((@as(u16, tint.b) * @as(u16, color.b)) >> 8),
    };
}

/// Default plains biome tint
pub const PLAINS_GRASS = Color{ .r = 0x91, .g = 0xbd, .b = 0x59 };
pub const PLAINS_FOLIAGE = Color{ .r = 0x77, .g = 0xab, .b = 0x2f };
pub const DEFAULT_WATER = Color{ .r = 0x3f, .g = 0x76, .b = 0xe4 };

pub fn lookupBiome(name: []const u8) ?*const BiomeTint {
    for (&biome_table) |*entry| {
        if (std.mem.eql(u8, name, entry.name)) return entry;
    }
    return null;
}

pub fn getBiomeTint(biome_name: []const u8, tint_type: TintType) Color {
    if (lookupBiome(biome_name)) |biome| {
        return switch (tint_type) {
            .grass => biome.grass,
            .foliage => biome.foliage,
            .water => biome.water,
        };
    }
    return switch (tint_type) {
        .grass => PLAINS_GRASS,
        .foliage => PLAINS_FOLIAGE,
        .water => DEFAULT_WATER,
    };
}

const biome_table = [_]BiomeTint{
    .{ .name = "minecraft:badlands", .grass = .{ .r = 144, .g = 129, .b = 77 }, .foliage = .{ .r = 158, .g = 129, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:bamboo_jungle", .grass = .{ .r = 89, .g = 201, .b = 60 }, .foliage = .{ .r = 48, .g = 187, .b = 11 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:basalt_deltas", .grass = .{ .r = 191, .g = 183, .b = 85 }, .foliage = .{ .r = 174, .g = 164, .b = 42 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:beach", .grass = .{ .r = 145, .g = 189, .b = 89 }, .foliage = .{ .r = 119, .g = 171, .b = 47 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:birch_forest", .grass = .{ .r = 136, .g = 187, .b = 103 }, .foliage = .{ .r = 107, .g = 169, .b = 65 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:cherry_grove", .grass = .{ .r = 182, .g = 219, .b = 97 }, .foliage = .{ .r = 182, .g = 219, .b = 97 }, .water = .{ .r = 93, .g = 183, .b = 239 } },
    .{ .name = "minecraft:cold_ocean", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 61, .g = 87, .b = 214 } },
    .{ .name = "minecraft:crimson_forest", .grass = .{ .r = 191, .g = 183, .b = 85 }, .foliage = .{ .r = 174, .g = 164, .b = 42 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:dark_forest", .grass = .{ .r = 121, .g = 192, .b = 90 }, .foliage = .{ .r = 89, .g = 174, .b = 48 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:deep_cold_ocean", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 61, .g = 87, .b = 214 } },
    .{ .name = "minecraft:deep_dark", .grass = .{ .r = 145, .g = 189, .b = 89 }, .foliage = .{ .r = 119, .g = 171, .b = 47 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:deep_frozen_ocean", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 57, .g = 56, .b = 201 } },
    .{ .name = "minecraft:deep_lukewarm_ocean", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 69, .g = 173, .b = 242 } },
    .{ .name = "minecraft:deep_ocean", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:desert", .grass = .{ .r = 191, .g = 183, .b = 85 }, .foliage = .{ .r = 174, .g = 164, .b = 42 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:dripstone_caves", .grass = .{ .r = 145, .g = 189, .b = 89 }, .foliage = .{ .r = 119, .g = 171, .b = 47 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:end_barrens", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:end_highlands", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:end_midlands", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:eroded_badlands", .grass = .{ .r = 144, .g = 129, .b = 77 }, .foliage = .{ .r = 158, .g = 129, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:flower_forest", .grass = .{ .r = 121, .g = 192, .b = 90 }, .foliage = .{ .r = 89, .g = 174, .b = 48 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:forest", .grass = .{ .r = 121, .g = 192, .b = 90 }, .foliage = .{ .r = 89, .g = 174, .b = 48 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:frozen_ocean", .grass = .{ .r = 128, .g = 180, .b = 151 }, .foliage = .{ .r = 96, .g = 161, .b = 123 }, .water = .{ .r = 57, .g = 56, .b = 201 } },
    .{ .name = "minecraft:frozen_peaks", .grass = .{ .r = 128, .g = 180, .b = 151 }, .foliage = .{ .r = 96, .g = 161, .b = 123 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:frozen_river", .grass = .{ .r = 128, .g = 180, .b = 151 }, .foliage = .{ .r = 96, .g = 161, .b = 123 }, .water = .{ .r = 57, .g = 56, .b = 201 } },
    .{ .name = "minecraft:grove", .grass = .{ .r = 128, .g = 180, .b = 151 }, .foliage = .{ .r = 96, .g = 161, .b = 123 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:ice_spikes", .grass = .{ .r = 128, .g = 180, .b = 151 }, .foliage = .{ .r = 96, .g = 161, .b = 123 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:jagged_peaks", .grass = .{ .r = 128, .g = 180, .b = 151 }, .foliage = .{ .r = 96, .g = 161, .b = 123 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:jungle", .grass = .{ .r = 89, .g = 201, .b = 60 }, .foliage = .{ .r = 48, .g = 187, .b = 11 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:lukewarm_ocean", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 69, .g = 173, .b = 242 } },
    .{ .name = "minecraft:lush_caves", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:mangrove_swamp", .grass = .{ .r = 106, .g = 196, .b = 78 }, .foliage = .{ .r = 141, .g = 177, .b = 39 }, .water = .{ .r = 58, .g = 122, .b = 106 } },
    .{ .name = "minecraft:meadow", .grass = .{ .r = 131, .g = 187, .b = 109 }, .foliage = .{ .r = 100, .g = 169, .b = 72 }, .water = .{ .r = 14, .g = 78, .b = 207 } },
    .{ .name = "minecraft:mushroom_fields", .grass = .{ .r = 85, .g = 201, .b = 63 }, .foliage = .{ .r = 43, .g = 187, .b = 15 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:nether_wastes", .grass = .{ .r = 191, .g = 183, .b = 85 }, .foliage = .{ .r = 174, .g = 164, .b = 42 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:ocean", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:old_growth_birch_forest", .grass = .{ .r = 136, .g = 187, .b = 103 }, .foliage = .{ .r = 107, .g = 169, .b = 65 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:old_growth_pine_taiga", .grass = .{ .r = 134, .g = 184, .b = 127 }, .foliage = .{ .r = 104, .g = 165, .b = 95 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:old_growth_spruce_taiga", .grass = .{ .r = 134, .g = 183, .b = 131 }, .foliage = .{ .r = 104, .g = 164, .b = 100 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:pale_garden", .grass = .{ .r = 119, .g = 130, .b = 114 }, .foliage = .{ .r = 135, .g = 141, .b = 118 }, .water = .{ .r = 118, .g = 136, .b = 157 } },
    .{ .name = "minecraft:plains", .grass = .{ .r = 145, .g = 189, .b = 89 }, .foliage = .{ .r = 119, .g = 171, .b = 47 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:river", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:savanna", .grass = .{ .r = 191, .g = 183, .b = 85 }, .foliage = .{ .r = 174, .g = 164, .b = 42 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:savanna_plateau", .grass = .{ .r = 191, .g = 183, .b = 85 }, .foliage = .{ .r = 174, .g = 164, .b = 42 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:small_end_islands", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:snowy_beach", .grass = .{ .r = 131, .g = 181, .b = 147 }, .foliage = .{ .r = 100, .g = 162, .b = 120 }, .water = .{ .r = 61, .g = 87, .b = 214 } },
    .{ .name = "minecraft:snowy_plains", .grass = .{ .r = 128, .g = 180, .b = 151 }, .foliage = .{ .r = 96, .g = 161, .b = 123 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:snowy_slopes", .grass = .{ .r = 128, .g = 180, .b = 151 }, .foliage = .{ .r = 96, .g = 161, .b = 123 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:snowy_taiga", .grass = .{ .r = 128, .g = 180, .b = 151 }, .foliage = .{ .r = 96, .g = 161, .b = 123 }, .water = .{ .r = 61, .g = 87, .b = 214 } },
    .{ .name = "minecraft:soul_sand_valley", .grass = .{ .r = 191, .g = 183, .b = 85 }, .foliage = .{ .r = 174, .g = 164, .b = 42 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:sparse_jungle", .grass = .{ .r = 100, .g = 199, .b = 63 }, .foliage = .{ .r = 62, .g = 184, .b = 15 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:stony_peaks", .grass = .{ .r = 154, .g = 190, .b = 75 }, .foliage = .{ .r = 130, .g = 172, .b = 30 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:stony_shore", .grass = .{ .r = 138, .g = 182, .b = 137 }, .foliage = .{ .r = 109, .g = 163, .b = 107 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:sunflower_plains", .grass = .{ .r = 145, .g = 189, .b = 89 }, .foliage = .{ .r = 119, .g = 171, .b = 47 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:swamp", .grass = .{ .r = 106, .g = 196, .b = 78 }, .foliage = .{ .r = 106, .g = 112, .b = 57 }, .water = .{ .r = 97, .g = 123, .b = 100 } },
    .{ .name = "minecraft:taiga", .grass = .{ .r = 134, .g = 183, .b = 131 }, .foliage = .{ .r = 104, .g = 164, .b = 100 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:the_end", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:the_void", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:warm_ocean", .grass = .{ .r = 142, .g = 185, .b = 113 }, .foliage = .{ .r = 113, .g = 167, .b = 77 }, .water = .{ .r = 67, .g = 213, .b = 238 } },
    .{ .name = "minecraft:warped_forest", .grass = .{ .r = 191, .g = 183, .b = 85 }, .foliage = .{ .r = 174, .g = 164, .b = 42 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:windswept_forest", .grass = .{ .r = 138, .g = 182, .b = 137 }, .foliage = .{ .r = 109, .g = 163, .b = 107 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:windswept_gravelly_hills", .grass = .{ .r = 138, .g = 182, .b = 137 }, .foliage = .{ .r = 109, .g = 163, .b = 107 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:windswept_hills", .grass = .{ .r = 138, .g = 182, .b = 137 }, .foliage = .{ .r = 109, .g = 163, .b = 107 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:windswept_savanna", .grass = .{ .r = 191, .g = 183, .b = 85 }, .foliage = .{ .r = 174, .g = 164, .b = 42 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
    .{ .name = "minecraft:wooded_badlands", .grass = .{ .r = 144, .g = 129, .b = 77 }, .foliage = .{ .r = 158, .g = 129, .b = 77 }, .water = .{ .r = 63, .g = 118, .b = 228 } },
};
