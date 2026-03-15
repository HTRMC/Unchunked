pub const Color = struct { r: u8, g: u8, b: u8 };

pub fn heightToGreen(height: u8) Color {
    // Map height 0-255 to green gradient
    // Darker = lower, brighter = higher
    const base: u8 = 30;
    const range: u16 = 180;
    const g: u8 = base + @as(u8, @intCast((@as(u16, height) * range) / 255));
    const r: u8 = base / 2 + @as(u8, @intCast((@as(u16, height) * 40) / 255));
    const b: u8 = base / 2 + @as(u8, @intCast((@as(u16, height) * 20) / 255));
    return .{ .r = r, .g = g, .b = b };
}

pub fn lookup(name: []const u8) ?Color {
    const entries = [_]struct { name: []const u8, color: Color }{
        .{ .name = "minecraft:grass_block", .color = .{ .r = 89, .g = 135, .b = 58 } },
        .{ .name = "minecraft:dirt", .color = .{ .r = 134, .g = 96, .b = 67 } },
        .{ .name = "minecraft:stone", .color = .{ .r = 125, .g = 125, .b = 125 } },
        .{ .name = "minecraft:water", .color = .{ .r = 56, .g = 89, .b = 163 } },
        .{ .name = "minecraft:sand", .color = .{ .r = 219, .g = 207, .b = 163 } },
        .{ .name = "minecraft:gravel", .color = .{ .r = 131, .g = 127, .b = 126 } },
        .{ .name = "minecraft:oak_log", .color = .{ .r = 109, .g = 85, .b = 50 } },
        .{ .name = "minecraft:oak_leaves", .color = .{ .r = 55, .g = 114, .b = 30 } },
        .{ .name = "minecraft:spruce_leaves", .color = .{ .r = 52, .g = 79, .b = 52 } },
        .{ .name = "minecraft:birch_leaves", .color = .{ .r = 80, .g = 126, .b = 52 } },
        .{ .name = "minecraft:snow_block", .color = .{ .r = 249, .g = 254, .b = 254 } },
        .{ .name = "minecraft:snow", .color = .{ .r = 249, .g = 254, .b = 254 } },
        .{ .name = "minecraft:ice", .color = .{ .r = 145, .g = 183, .b = 253 } },
        .{ .name = "minecraft:packed_ice", .color = .{ .r = 140, .g = 180, .b = 248 } },
        .{ .name = "minecraft:clay", .color = .{ .r = 159, .g = 164, .b = 177 } },
        .{ .name = "minecraft:sandstone", .color = .{ .r = 216, .g = 203, .b = 155 } },
        .{ .name = "minecraft:red_sand", .color = .{ .r = 190, .g = 102, .b = 33 } },
        .{ .name = "minecraft:terracotta", .color = .{ .r = 152, .g = 94, .b = 67 } },
        .{ .name = "minecraft:netherrack", .color = .{ .r = 97, .g = 38, .b = 38 } },
        .{ .name = "minecraft:soul_sand", .color = .{ .r = 81, .g = 62, .b = 50 } },
        .{ .name = "minecraft:end_stone", .color = .{ .r = 219, .g = 222, .b = 158 } },
        .{ .name = "minecraft:obsidian", .color = .{ .r = 15, .g = 10, .b = 24 } },
        .{ .name = "minecraft:bedrock", .color = .{ .r = 85, .g = 85, .b = 85 } },
        .{ .name = "minecraft:deepslate", .color = .{ .r = 80, .g = 80, .b = 82 } },
        .{ .name = "minecraft:cobblestone", .color = .{ .r = 127, .g = 127, .b = 127 } },
        .{ .name = "minecraft:mossy_cobblestone", .color = .{ .r = 110, .g = 127, .b = 93 } },
        .{ .name = "minecraft:oak_planks", .color = .{ .r = 162, .g = 130, .b = 78 } },
        .{ .name = "minecraft:mycelium", .color = .{ .r = 111, .g = 99, .b = 107 } },
        .{ .name = "minecraft:podzol", .color = .{ .r = 122, .g = 81, .b = 38 } },
        .{ .name = "minecraft:lava", .color = .{ .r = 207, .g = 91, .b = 10 } },
        .{ .name = "minecraft:basalt", .color = .{ .r = 73, .g = 72, .b = 77 } },
        .{ .name = "minecraft:blackstone", .color = .{ .r = 42, .g = 36, .b = 41 } },
        .{ .name = "minecraft:crimson_nylium", .color = .{ .r = 130, .g = 31, .b = 31 } },
        .{ .name = "minecraft:warped_nylium", .color = .{ .r = 43, .g = 114, .b = 101 } },
        .{ .name = "minecraft:moss_block", .color = .{ .r = 89, .g = 109, .b = 45 } },
        .{ .name = "minecraft:dripstone_block", .color = .{ .r = 134, .g = 107, .b = 80 } },
        .{ .name = "minecraft:copper_block", .color = .{ .r = 192, .g = 107, .b = 79 } },
        .{ .name = "minecraft:iron_ore", .color = .{ .r = 136, .g = 129, .b = 122 } },
        .{ .name = "minecraft:coal_ore", .color = .{ .r = 105, .g = 105, .b = 105 } },
        .{ .name = "minecraft:gold_ore", .color = .{ .r = 143, .g = 140, .b = 125 } },
        .{ .name = "minecraft:diamond_ore", .color = .{ .r = 121, .g = 141, .b = 140 } },
    };

    for (entries) |e| {
        if (std.mem.eql(u8, name, e.name)) return e.color;
    }
    return null;
}

const std = @import("std");
