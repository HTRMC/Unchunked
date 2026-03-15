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

/// Returns true for blocks that should be skipped when finding the top solid block.
/// Includes air, fluids, glass, leaves, flowers, small plants, redstone, rails, etc.
pub fn isTransparent(name: []const u8) bool {
    // Strip "minecraft:" prefix if present
    const stripped = if (std.mem.startsWith(u8, name, "minecraft:"))
        name["minecraft:".len..]
    else
        name;

    // Air variants
    if (std.mem.eql(u8, stripped, "air")) return true;
    if (std.mem.eql(u8, stripped, "cave_air")) return true;
    if (std.mem.eql(u8, stripped, "void_air")) return true;

    // Fluids
    if (std.mem.eql(u8, stripped, "water")) return true;
    if (std.mem.eql(u8, stripped, "lava")) return true;

    // Glass
    if (std.mem.eql(u8, stripped, "glass")) return true;
    if (std.mem.eql(u8, stripped, "glass_pane")) return true;
    if (std.mem.eql(u8, stripped, "tinted_glass")) return true;
    if (std.mem.endsWith(u8, stripped, "_stained_glass")) return true;
    if (std.mem.endsWith(u8, stripped, "_stained_glass_pane")) return true;

    // Leaves
    if (std.mem.endsWith(u8, stripped, "_leaves")) return true;

    // Saplings
    if (std.mem.endsWith(u8, stripped, "_sapling")) return true;

    // Flowers
    if (std.mem.eql(u8, stripped, "dandelion")) return true;
    if (std.mem.eql(u8, stripped, "poppy")) return true;
    if (std.mem.eql(u8, stripped, "blue_orchid")) return true;
    if (std.mem.eql(u8, stripped, "allium")) return true;
    if (std.mem.eql(u8, stripped, "azure_bluet")) return true;
    if (std.mem.eql(u8, stripped, "oxeye_daisy")) return true;
    if (std.mem.eql(u8, stripped, "cornflower")) return true;
    if (std.mem.eql(u8, stripped, "lily_of_the_valley")) return true;
    if (std.mem.eql(u8, stripped, "wither_rose")) return true;
    if (std.mem.eql(u8, stripped, "torchflower")) return true;
    if (std.mem.eql(u8, stripped, "pitcher_plant")) return true;
    if (std.mem.endsWith(u8, stripped, "_tulip")) return true;
    if (std.mem.eql(u8, stripped, "sunflower")) return true;
    if (std.mem.eql(u8, stripped, "lilac")) return true;
    if (std.mem.eql(u8, stripped, "rose_bush")) return true;
    if (std.mem.eql(u8, stripped, "peony")) return true;
    if (std.mem.eql(u8, stripped, "spore_blossom")) return true;

    // Small plants / vegetation
    if (std.mem.eql(u8, stripped, "short_grass")) return true;
    if (std.mem.eql(u8, stripped, "tall_grass")) return true;
    if (std.mem.eql(u8, stripped, "fern")) return true;
    if (std.mem.eql(u8, stripped, "large_fern")) return true;
    if (std.mem.eql(u8, stripped, "dead_bush")) return true;
    if (std.mem.eql(u8, stripped, "seagrass")) return true;
    if (std.mem.eql(u8, stripped, "tall_seagrass")) return true;
    if (std.mem.eql(u8, stripped, "kelp")) return true;
    if (std.mem.eql(u8, stripped, "kelp_plant")) return true;
    if (std.mem.eql(u8, stripped, "sugar_cane")) return true;
    if (std.mem.eql(u8, stripped, "bamboo")) return true;
    if (std.mem.eql(u8, stripped, "sweet_berry_bush")) return true;
    if (std.mem.eql(u8, stripped, "cave_vines")) return true;
    if (std.mem.eql(u8, stripped, "cave_vines_plant")) return true;
    if (std.mem.eql(u8, stripped, "glow_lichen")) return true;
    if (std.mem.eql(u8, stripped, "hanging_roots")) return true;
    if (std.mem.eql(u8, stripped, "small_dripleaf")) return true;
    if (std.mem.eql(u8, stripped, "big_dripleaf")) return true;
    if (std.mem.eql(u8, stripped, "big_dripleaf_stem")) return true;
    if (std.mem.eql(u8, stripped, "lily_pad")) return true;

    // Nether vegetation
    if (std.mem.eql(u8, stripped, "nether_sprouts")) return true;
    if (std.mem.eql(u8, stripped, "twisting_vines")) return true;
    if (std.mem.eql(u8, stripped, "twisting_vines_plant")) return true;
    if (std.mem.eql(u8, stripped, "weeping_vines")) return true;
    if (std.mem.eql(u8, stripped, "weeping_vines_plant")) return true;
    if (std.mem.eql(u8, stripped, "crimson_roots")) return true;
    if (std.mem.eql(u8, stripped, "warped_roots")) return true;
    if (std.mem.eql(u8, stripped, "crimson_fungus")) return true;
    if (std.mem.eql(u8, stripped, "warped_fungus")) return true;

    // Mushrooms
    if (std.mem.eql(u8, stripped, "red_mushroom")) return true;
    if (std.mem.eql(u8, stripped, "brown_mushroom")) return true;

    // Torches / lighting
    if (std.mem.eql(u8, stripped, "torch")) return true;
    if (std.mem.eql(u8, stripped, "wall_torch")) return true;
    if (std.mem.eql(u8, stripped, "soul_torch")) return true;
    if (std.mem.eql(u8, stripped, "soul_wall_torch")) return true;
    if (std.mem.eql(u8, stripped, "redstone_torch")) return true;
    if (std.mem.eql(u8, stripped, "redstone_wall_torch")) return true;
    if (std.mem.eql(u8, stripped, "lantern")) return true;
    if (std.mem.eql(u8, stripped, "soul_lantern")) return true;
    if (std.mem.eql(u8, stripped, "candle")) return true;
    if (std.mem.endsWith(u8, stripped, "_candle")) return true;
    if (std.mem.eql(u8, stripped, "end_rod")) return true;

    // Redstone components
    if (std.mem.eql(u8, stripped, "redstone_wire")) return true;
    if (std.mem.eql(u8, stripped, "repeater")) return true;
    if (std.mem.eql(u8, stripped, "comparator")) return true;
    if (std.mem.eql(u8, stripped, "lever")) return true;
    if (std.mem.eql(u8, stripped, "tripwire")) return true;
    if (std.mem.eql(u8, stripped, "tripwire_hook")) return true;

    // Rails
    if (std.mem.eql(u8, stripped, "rail")) return true;
    if (std.mem.eql(u8, stripped, "powered_rail")) return true;
    if (std.mem.eql(u8, stripped, "detector_rail")) return true;
    if (std.mem.eql(u8, stripped, "activator_rail")) return true;

    // Signs
    if (std.mem.endsWith(u8, stripped, "_sign")) return true;
    if (std.mem.endsWith(u8, stripped, "_wall_sign")) return true;
    if (std.mem.endsWith(u8, stripped, "_hanging_sign")) return true;
    if (std.mem.endsWith(u8, stripped, "_wall_hanging_sign")) return true;

    // Banners
    if (std.mem.endsWith(u8, stripped, "_banner")) return true;
    if (std.mem.endsWith(u8, stripped, "_wall_banner")) return true;

    // Buttons
    if (std.mem.endsWith(u8, stripped, "_button")) return true;

    // Pressure plates
    if (std.mem.endsWith(u8, stripped, "_pressure_plate")) return true;

    // Carpet
    if (std.mem.endsWith(u8, stripped, "_carpet")) return true;
    if (std.mem.eql(u8, stripped, "moss_carpet")) return true;

    // Other thin / non-solid
    if (std.mem.eql(u8, stripped, "ladder")) return true;
    if (std.mem.eql(u8, stripped, "vine")) return true;
    if (std.mem.eql(u8, stripped, "snow")) return true; // snow layer (not snow_block)
    if (std.mem.eql(u8, stripped, "chain")) return true;
    if (std.mem.eql(u8, stripped, "iron_bars")) return true;
    if (std.mem.eql(u8, stripped, "cobweb")) return true;
    if (std.mem.eql(u8, stripped, "scaffolding")) return true;
    if (std.mem.eql(u8, stripped, "lightning_rod")) return true;
    if (std.mem.eql(u8, stripped, "flower_pot")) return true;
    if (std.mem.eql(u8, stripped, "string")) return true;
    if (std.mem.eql(u8, stripped, "barrier")) return true;
    if (std.mem.eql(u8, stripped, "light")) return true;
    if (std.mem.eql(u8, stripped, "structure_void")) return true;

    // Doors, trapdoors, fence gates (non-solid for top-down view)
    if (std.mem.endsWith(u8, stripped, "_door")) return true;
    if (std.mem.endsWith(u8, stripped, "_trapdoor")) return true;
    if (std.mem.endsWith(u8, stripped, "_fence_gate")) return true;
    if (std.mem.endsWith(u8, stripped, "_fence")) return true;

    // Crops
    if (std.mem.eql(u8, stripped, "wheat")) return true;
    if (std.mem.eql(u8, stripped, "carrots")) return true;
    if (std.mem.eql(u8, stripped, "potatoes")) return true;
    if (std.mem.eql(u8, stripped, "beetroots")) return true;
    if (std.mem.eql(u8, stripped, "melon_stem")) return true;
    if (std.mem.eql(u8, stripped, "pumpkin_stem")) return true;
    if (std.mem.eql(u8, stripped, "attached_melon_stem")) return true;
    if (std.mem.eql(u8, stripped, "attached_pumpkin_stem")) return true;

    // Heads / skulls
    if (std.mem.endsWith(u8, stripped, "_head")) return true;
    if (std.mem.endsWith(u8, stripped, "_wall_head")) return true;
    if (std.mem.endsWith(u8, stripped, "_skull")) return true;
    if (std.mem.endsWith(u8, stripped, "_wall_skull")) return true;

    return false;
}

pub fn lookup(name: []const u8) ?Color {
    const Entry = struct { name: []const u8, color: Color };
    const entries = [_]Entry{
        // =====================================================================
        // Stone variants
        // =====================================================================
        .{ .name = "minecraft:stone", .color = .{ .r = 125, .g = 125, .b = 125 } }, // #7D7D7D
        .{ .name = "minecraft:smooth_stone", .color = .{ .r = 158, .g = 158, .b = 158 } }, // #9E9E9E
        .{ .name = "minecraft:granite", .color = .{ .r = 149, .g = 103, .b = 85 } }, // #956755
        .{ .name = "minecraft:polished_granite", .color = .{ .r = 154, .g = 106, .b = 89 } }, // #9A6A59
        .{ .name = "minecraft:diorite", .color = .{ .r = 188, .g = 188, .b = 188 } }, // #BCBCBC
        .{ .name = "minecraft:polished_diorite", .color = .{ .r = 192, .g = 192, .b = 192 } }, // #C0C0C0
        .{ .name = "minecraft:andesite", .color = .{ .r = 136, .g = 136, .b = 136 } }, // #888888
        .{ .name = "minecraft:polished_andesite", .color = .{ .r = 132, .g = 135, .b = 132 } }, // #848784
        .{ .name = "minecraft:deepslate", .color = .{ .r = 80, .g = 80, .b = 82 } }, // #505052
        .{ .name = "minecraft:cobbled_deepslate", .color = .{ .r = 77, .g = 77, .b = 80 } }, // #4D4D50
        .{ .name = "minecraft:polished_deepslate", .color = .{ .r = 72, .g = 72, .b = 73 } }, // #484849
        .{ .name = "minecraft:deepslate_bricks", .color = .{ .r = 70, .g = 70, .b = 72 } }, // #464648
        .{ .name = "minecraft:deepslate_tiles", .color = .{ .r = 54, .g = 54, .b = 55 } }, // #363637
        .{ .name = "minecraft:cracked_deepslate_bricks", .color = .{ .r = 64, .g = 64, .b = 65 } },
        .{ .name = "minecraft:cracked_deepslate_tiles", .color = .{ .r = 52, .g = 52, .b = 52 } },
        .{ .name = "minecraft:chiseled_deepslate", .color = .{ .r = 54, .g = 54, .b = 55 } },
        .{ .name = "minecraft:reinforced_deepslate", .color = .{ .r = 65, .g = 65, .b = 67 } },
        .{ .name = "minecraft:tuff", .color = .{ .r = 108, .g = 109, .b = 102 } }, // #6C6D66
        .{ .name = "minecraft:tuff_bricks", .color = .{ .r = 115, .g = 116, .b = 107 } },
        .{ .name = "minecraft:polished_tuff", .color = .{ .r = 111, .g = 112, .b = 105 } },
        .{ .name = "minecraft:chiseled_tuff", .color = .{ .r = 111, .g = 112, .b = 105 } },
        .{ .name = "minecraft:chiseled_tuff_bricks", .color = .{ .r = 113, .g = 114, .b = 107 } },
        .{ .name = "minecraft:calcite", .color = .{ .r = 223, .g = 224, .b = 220 } }, // #DFE0DC
        .{ .name = "minecraft:dripstone_block", .color = .{ .r = 134, .g = 107, .b = 80 } }, // #866B50

        // =====================================================================
        // Dirt / grass variants
        // =====================================================================
        .{ .name = "minecraft:grass_block", .color = .{ .r = 89, .g = 135, .b = 58 } }, // #59873A
        .{ .name = "minecraft:dirt", .color = .{ .r = 134, .g = 96, .b = 67 } }, // #866043
        .{ .name = "minecraft:coarse_dirt", .color = .{ .r = 119, .g = 85, .b = 59 } }, // #77553B
        .{ .name = "minecraft:rooted_dirt", .color = .{ .r = 144, .g = 103, .b = 76 } }, // #90674C
        .{ .name = "minecraft:mud", .color = .{ .r = 60, .g = 57, .b = 60 } }, // #3C393C
        .{ .name = "minecraft:packed_mud", .color = .{ .r = 142, .g = 106, .b = 79 } }, // #8E6A4F
        .{ .name = "minecraft:mud_bricks", .color = .{ .r = 137, .g = 104, .b = 75 } }, // #89684B
        .{ .name = "minecraft:mycelium", .color = .{ .r = 111, .g = 99, .b = 107 } }, // #6F636B
        .{ .name = "minecraft:podzol", .color = .{ .r = 122, .g = 81, .b = 38 } }, // #7A5126
        .{ .name = "minecraft:farmland", .color = .{ .r = 81, .g = 49, .b = 25 } }, // #513119
        .{ .name = "minecraft:dirt_path", .color = .{ .r = 148, .g = 121, .b = 65 } }, // #947941
        .{ .name = "minecraft:moss_block", .color = .{ .r = 89, .g = 109, .b = 45 } }, // #596D2D
        .{ .name = "minecraft:muddy_mangrove_roots", .color = .{ .r = 70, .g = 60, .b = 46 } },

        // =====================================================================
        // Sand / gravel / clay
        // =====================================================================
        .{ .name = "minecraft:sand", .color = .{ .r = 219, .g = 207, .b = 163 } }, // #DBCFA3
        .{ .name = "minecraft:red_sand", .color = .{ .r = 190, .g = 102, .b = 33 } }, // #BE6621
        .{ .name = "minecraft:sandstone", .color = .{ .r = 216, .g = 203, .b = 155 } }, // #D8CB9B
        .{ .name = "minecraft:smooth_sandstone", .color = .{ .r = 223, .g = 214, .b = 170 } },
        .{ .name = "minecraft:chiseled_sandstone", .color = .{ .r = 216, .g = 203, .b = 155 } },
        .{ .name = "minecraft:cut_sandstone", .color = .{ .r = 218, .g = 206, .b = 160 } },
        .{ .name = "minecraft:red_sandstone", .color = .{ .r = 186, .g = 99, .b = 29 } },
        .{ .name = "minecraft:smooth_red_sandstone", .color = .{ .r = 181, .g = 97, .b = 31 } },
        .{ .name = "minecraft:chiseled_red_sandstone", .color = .{ .r = 183, .g = 97, .b = 28 } },
        .{ .name = "minecraft:cut_red_sandstone", .color = .{ .r = 189, .g = 102, .b = 32 } },
        .{ .name = "minecraft:gravel", .color = .{ .r = 131, .g = 127, .b = 126 } }, // #837F7E
        .{ .name = "minecraft:clay", .color = .{ .r = 159, .g = 164, .b = 177 } }, // #9FA4B1
        .{ .name = "minecraft:soul_sand", .color = .{ .r = 81, .g = 62, .b = 50 } }, // #513E32
        .{ .name = "minecraft:soul_soil", .color = .{ .r = 75, .g = 57, .b = 46 } }, // #4B392E
        .{ .name = "minecraft:suspicious_sand", .color = .{ .r = 216, .g = 204, .b = 160 } },
        .{ .name = "minecraft:suspicious_gravel", .color = .{ .r = 131, .g = 127, .b = 126 } },

        // =====================================================================
        // Ores
        // =====================================================================
        .{ .name = "minecraft:coal_ore", .color = .{ .r = 105, .g = 105, .b = 105 } }, // #696969
        .{ .name = "minecraft:iron_ore", .color = .{ .r = 136, .g = 129, .b = 122 } }, // #88817A
        .{ .name = "minecraft:copper_ore", .color = .{ .r = 124, .g = 125, .b = 120 } }, // #7C7D78
        .{ .name = "minecraft:gold_ore", .color = .{ .r = 143, .g = 140, .b = 125 } }, // #8F8C7D
        .{ .name = "minecraft:redstone_ore", .color = .{ .r = 133, .g = 107, .b = 107 } }, // #856B6B
        .{ .name = "minecraft:emerald_ore", .color = .{ .r = 108, .g = 136, .b = 115 } }, // #6C8873
        .{ .name = "minecraft:lapis_ore", .color = .{ .r = 100, .g = 112, .b = 134 } }, // #647086
        .{ .name = "minecraft:diamond_ore", .color = .{ .r = 121, .g = 141, .b = 140 } }, // #798D8C
        .{ .name = "minecraft:nether_gold_ore", .color = .{ .r = 115, .g = 54, .b = 42 } },
        .{ .name = "minecraft:nether_quartz_ore", .color = .{ .r = 117, .g = 65, .b = 62 } },
        .{ .name = "minecraft:ancient_debris", .color = .{ .r = 94, .g = 66, .b = 56 } }, // #5E4238
        // Deepslate ore variants
        .{ .name = "minecraft:deepslate_coal_ore", .color = .{ .r = 74, .g = 74, .b = 76 } },
        .{ .name = "minecraft:deepslate_iron_ore", .color = .{ .r = 106, .g = 99, .b = 95 } },
        .{ .name = "minecraft:deepslate_copper_ore", .color = .{ .r = 92, .g = 93, .b = 89 } },
        .{ .name = "minecraft:deepslate_gold_ore", .color = .{ .r = 115, .g = 102, .b = 80 } },
        .{ .name = "minecraft:deepslate_redstone_ore", .color = .{ .r = 104, .g = 73, .b = 73 } },
        .{ .name = "minecraft:deepslate_emerald_ore", .color = .{ .r = 78, .g = 104, .b = 85 } },
        .{ .name = "minecraft:deepslate_lapis_ore", .color = .{ .r = 72, .g = 82, .b = 103 } },
        .{ .name = "minecraft:deepslate_diamond_ore", .color = .{ .r = 83, .g = 107, .b = 106 } },
        // Raw ore blocks
        .{ .name = "minecraft:raw_iron_block", .color = .{ .r = 166, .g = 135, .b = 107 } },
        .{ .name = "minecraft:raw_copper_block", .color = .{ .r = 154, .g = 105, .b = 73 } },
        .{ .name = "minecraft:raw_gold_block", .color = .{ .r = 221, .g = 169, .b = 46 } },

        // =====================================================================
        // Mineral blocks
        // =====================================================================
        .{ .name = "minecraft:iron_block", .color = .{ .r = 220, .g = 220, .b = 220 } }, // #DCDCDC
        .{ .name = "minecraft:gold_block", .color = .{ .r = 246, .g = 208, .b = 61 } }, // #F6D03D
        .{ .name = "minecraft:diamond_block", .color = .{ .r = 98, .g = 237, .b = 228 } }, // #62EDE4
        .{ .name = "minecraft:emerald_block", .color = .{ .r = 42, .g = 176, .b = 67 } }, // #2AB043
        .{ .name = "minecraft:lapis_block", .color = .{ .r = 30, .g = 67, .b = 140 } }, // #1E438C
        .{ .name = "minecraft:redstone_block", .color = .{ .r = 171, .g = 2, .b = 0 } }, // #AB0200
        .{ .name = "minecraft:netherite_block", .color = .{ .r = 66, .g = 61, .b = 63 } }, // #423D3F
        .{ .name = "minecraft:coal_block", .color = .{ .r = 16, .g = 15, .b = 15 } }, // #100F0F
        .{ .name = "minecraft:copper_block", .color = .{ .r = 192, .g = 107, .b = 79 } }, // #C06B4F
        .{ .name = "minecraft:exposed_copper", .color = .{ .r = 161, .g = 125, .b = 103 } },
        .{ .name = "minecraft:weathered_copper", .color = .{ .r = 109, .g = 145, .b = 107 } },
        .{ .name = "minecraft:oxidized_copper", .color = .{ .r = 82, .g = 162, .b = 132 } },
        .{ .name = "minecraft:cut_copper", .color = .{ .r = 191, .g = 106, .b = 80 } },
        .{ .name = "minecraft:exposed_cut_copper", .color = .{ .r = 154, .g = 121, .b = 101 } },
        .{ .name = "minecraft:weathered_cut_copper", .color = .{ .r = 109, .g = 137, .b = 108 } },
        .{ .name = "minecraft:oxidized_cut_copper", .color = .{ .r = 79, .g = 153, .b = 126 } },
        .{ .name = "minecraft:waxed_copper_block", .color = .{ .r = 192, .g = 107, .b = 79 } },
        .{ .name = "minecraft:amethyst_block", .color = .{ .r = 133, .g = 97, .b = 191 } }, // #8561BF
        .{ .name = "minecraft:budding_amethyst", .color = .{ .r = 132, .g = 96, .b = 186 } },
        .{ .name = "minecraft:quartz_block", .color = .{ .r = 235, .g = 229, .b = 222 } }, // #EBE5DE
        .{ .name = "minecraft:smooth_quartz", .color = .{ .r = 235, .g = 229, .b = 222 } },
        .{ .name = "minecraft:quartz_bricks", .color = .{ .r = 234, .g = 228, .b = 220 } },
        .{ .name = "minecraft:chiseled_quartz_block", .color = .{ .r = 231, .g = 226, .b = 218 } },
        .{ .name = "minecraft:quartz_pillar", .color = .{ .r = 235, .g = 230, .b = 224 } },

        // =====================================================================
        // Wood planks
        // =====================================================================
        .{ .name = "minecraft:oak_planks", .color = .{ .r = 162, .g = 130, .b = 78 } }, // #A2824E
        .{ .name = "minecraft:spruce_planks", .color = .{ .r = 114, .g = 84, .b = 48 } }, // #725430
        .{ .name = "minecraft:birch_planks", .color = .{ .r = 196, .g = 179, .b = 123 } }, // #C4B37B
        .{ .name = "minecraft:jungle_planks", .color = .{ .r = 160, .g = 115, .b = 80 } }, // #A07350
        .{ .name = "minecraft:acacia_planks", .color = .{ .r = 168, .g = 90, .b = 50 } }, // #A85A32
        .{ .name = "minecraft:dark_oak_planks", .color = .{ .r = 67, .g = 43, .b = 20 } }, // #432B14
        .{ .name = "minecraft:mangrove_planks", .color = .{ .r = 117, .g = 54, .b = 48 } }, // #753630
        .{ .name = "minecraft:cherry_planks", .color = .{ .r = 226, .g = 178, .b = 172 } }, // #E2B2AC
        .{ .name = "minecraft:bamboo_planks", .color = .{ .r = 194, .g = 175, .b = 82 } }, // #C2AF52
        .{ .name = "minecraft:bamboo_mosaic", .color = .{ .r = 192, .g = 173, .b = 79 } },
        .{ .name = "minecraft:crimson_planks", .color = .{ .r = 101, .g = 48, .b = 70 } }, // #653046
        .{ .name = "minecraft:warped_planks", .color = .{ .r = 43, .g = 104, .b = 99 } }, // #2B6863

        // =====================================================================
        // Wood logs (top texture)
        // =====================================================================
        .{ .name = "minecraft:oak_log", .color = .{ .r = 109, .g = 85, .b = 50 } }, // #6D5532
        .{ .name = "minecraft:spruce_log", .color = .{ .r = 108, .g = 80, .b = 46 } }, // #6C502E
        .{ .name = "minecraft:birch_log", .color = .{ .r = 196, .g = 179, .b = 123 } }, // #C4B37B
        .{ .name = "minecraft:jungle_log", .color = .{ .r = 149, .g = 109, .b = 61 } }, // #956D3D
        .{ .name = "minecraft:acacia_log", .color = .{ .r = 103, .g = 96, .b = 86 } }, // #676056
        .{ .name = "minecraft:dark_oak_log", .color = .{ .r = 60, .g = 46, .b = 26 } }, // #3C2E1A
        .{ .name = "minecraft:mangrove_log", .color = .{ .r = 84, .g = 56, .b = 40 } }, // #543828
        .{ .name = "minecraft:cherry_log", .color = .{ .r = 57, .g = 26, .b = 32 } }, // #391A20
        .{ .name = "minecraft:bamboo_block", .color = .{ .r = 126, .g = 141, .b = 32 } },
        .{ .name = "minecraft:crimson_stem", .color = .{ .r = 92, .g = 25, .b = 29 } }, // #5C191D
        .{ .name = "minecraft:warped_stem", .color = .{ .r = 26, .g = 72, .b = 72 } }, // #1A4848
        // Stripped logs
        .{ .name = "minecraft:stripped_oak_log", .color = .{ .r = 177, .g = 144, .b = 86 } },
        .{ .name = "minecraft:stripped_spruce_log", .color = .{ .r = 115, .g = 89, .b = 52 } },
        .{ .name = "minecraft:stripped_birch_log", .color = .{ .r = 196, .g = 176, .b = 118 } },
        .{ .name = "minecraft:stripped_jungle_log", .color = .{ .r = 171, .g = 132, .b = 84 } },
        .{ .name = "minecraft:stripped_acacia_log", .color = .{ .r = 174, .g = 92, .b = 59 } },
        .{ .name = "minecraft:stripped_dark_oak_log", .color = .{ .r = 96, .g = 75, .b = 46 } },
        .{ .name = "minecraft:stripped_mangrove_log", .color = .{ .r = 119, .g = 54, .b = 47 } },
        .{ .name = "minecraft:stripped_cherry_log", .color = .{ .r = 215, .g = 158, .b = 148 } },
        .{ .name = "minecraft:stripped_crimson_stem", .color = .{ .r = 137, .g = 61, .b = 82 } },
        .{ .name = "minecraft:stripped_warped_stem", .color = .{ .r = 57, .g = 150, .b = 148 } },
        // Wood (bark all around)
        .{ .name = "minecraft:oak_wood", .color = .{ .r = 109, .g = 85, .b = 50 } },
        .{ .name = "minecraft:spruce_wood", .color = .{ .r = 58, .g = 37, .b = 16 } },
        .{ .name = "minecraft:birch_wood", .color = .{ .r = 215, .g = 215, .b = 210 } },
        .{ .name = "minecraft:jungle_wood", .color = .{ .r = 85, .g = 67, .b = 25 } },
        .{ .name = "minecraft:acacia_wood", .color = .{ .r = 103, .g = 96, .b = 86 } },
        .{ .name = "minecraft:dark_oak_wood", .color = .{ .r = 60, .g = 46, .b = 26 } },
        .{ .name = "minecraft:mangrove_wood", .color = .{ .r = 84, .g = 56, .b = 40 } },
        .{ .name = "minecraft:cherry_wood", .color = .{ .r = 57, .g = 26, .b = 32 } },
        .{ .name = "minecraft:crimson_hyphae", .color = .{ .r = 92, .g = 25, .b = 29 } },
        .{ .name = "minecraft:warped_hyphae", .color = .{ .r = 26, .g = 72, .b = 72 } },

        // =====================================================================
        // Terracotta (plain + 16 colored)
        // =====================================================================
        .{ .name = "minecraft:terracotta", .color = .{ .r = 152, .g = 94, .b = 67 } }, // #985E43
        .{ .name = "minecraft:white_terracotta", .color = .{ .r = 209, .g = 178, .b = 161 } }, // #D1B2A1
        .{ .name = "minecraft:orange_terracotta", .color = .{ .r = 161, .g = 83, .b = 37 } }, // #A15325
        .{ .name = "minecraft:magenta_terracotta", .color = .{ .r = 149, .g = 88, .b = 108 } }, // #95586C
        .{ .name = "minecraft:light_blue_terracotta", .color = .{ .r = 113, .g = 108, .b = 137 } }, // #716C89
        .{ .name = "minecraft:yellow_terracotta", .color = .{ .r = 186, .g = 133, .b = 35 } }, // #BA8523
        .{ .name = "minecraft:lime_terracotta", .color = .{ .r = 103, .g = 117, .b = 52 } }, // #677534
        .{ .name = "minecraft:pink_terracotta", .color = .{ .r = 161, .g = 78, .b = 78 } }, // #A14E4E
        .{ .name = "minecraft:gray_terracotta", .color = .{ .r = 57, .g = 42, .b = 35 } }, // #392A23
        .{ .name = "minecraft:light_gray_terracotta", .color = .{ .r = 135, .g = 106, .b = 97 } }, // #876A61
        .{ .name = "minecraft:cyan_terracotta", .color = .{ .r = 86, .g = 91, .b = 91 } }, // #565B5B
        .{ .name = "minecraft:purple_terracotta", .color = .{ .r = 118, .g = 70, .b = 86 } }, // #764656
        .{ .name = "minecraft:blue_terracotta", .color = .{ .r = 74, .g = 59, .b = 91 } }, // #4A3B5B
        .{ .name = "minecraft:brown_terracotta", .color = .{ .r = 77, .g = 51, .b = 35 } }, // #4D3323
        .{ .name = "minecraft:green_terracotta", .color = .{ .r = 76, .g = 83, .b = 42 } }, // #4C532A
        .{ .name = "minecraft:red_terracotta", .color = .{ .r = 143, .g = 61, .b = 46 } }, // #8F3D2E
        .{ .name = "minecraft:black_terracotta", .color = .{ .r = 37, .g = 22, .b = 16 } }, // #251610
        // Glazed terracotta
        .{ .name = "minecraft:white_glazed_terracotta", .color = .{ .r = 188, .g = 212, .b = 202 } },
        .{ .name = "minecraft:orange_glazed_terracotta", .color = .{ .r = 154, .g = 147, .b = 91 } },
        .{ .name = "minecraft:magenta_glazed_terracotta", .color = .{ .r = 208, .g = 100, .b = 191 } },
        .{ .name = "minecraft:light_blue_glazed_terracotta", .color = .{ .r = 94, .g = 164, .b = 208 } },
        .{ .name = "minecraft:yellow_glazed_terracotta", .color = .{ .r = 234, .g = 192, .b = 88 } },
        .{ .name = "minecraft:lime_glazed_terracotta", .color = .{ .r = 162, .g = 197, .b = 55 } },
        .{ .name = "minecraft:pink_glazed_terracotta", .color = .{ .r = 235, .g = 154, .b = 181 } },
        .{ .name = "minecraft:gray_glazed_terracotta", .color = .{ .r = 83, .g = 90, .b = 93 } },
        .{ .name = "minecraft:light_gray_glazed_terracotta", .color = .{ .r = 144, .g = 166, .b = 167 } },
        .{ .name = "minecraft:cyan_glazed_terracotta", .color = .{ .r = 52, .g = 118, .b = 125 } },
        .{ .name = "minecraft:purple_glazed_terracotta", .color = .{ .r = 109, .g = 48, .b = 152 } },
        .{ .name = "minecraft:blue_glazed_terracotta", .color = .{ .r = 47, .g = 64, .b = 139 } },
        .{ .name = "minecraft:brown_glazed_terracotta", .color = .{ .r = 119, .g = 106, .b = 85 } },
        .{ .name = "minecraft:green_glazed_terracotta", .color = .{ .r = 117, .g = 142, .b = 67 } },
        .{ .name = "minecraft:red_glazed_terracotta", .color = .{ .r = 181, .g = 59, .b = 53 } },
        .{ .name = "minecraft:black_glazed_terracotta", .color = .{ .r = 67, .g = 30, .b = 32 } },

        // =====================================================================
        // Concrete (16 colors)
        // =====================================================================
        .{ .name = "minecraft:white_concrete", .color = .{ .r = 207, .g = 213, .b = 214 } }, // #CFD5D6
        .{ .name = "minecraft:orange_concrete", .color = .{ .r = 224, .g = 97, .b = 0 } }, // #E06100
        .{ .name = "minecraft:magenta_concrete", .color = .{ .r = 169, .g = 48, .b = 159 } }, // #A9309F
        .{ .name = "minecraft:light_blue_concrete", .color = .{ .r = 35, .g = 137, .b = 198 } }, // #2389C6
        .{ .name = "minecraft:yellow_concrete", .color = .{ .r = 240, .g = 175, .b = 21 } }, // #F0AF15
        .{ .name = "minecraft:lime_concrete", .color = .{ .r = 94, .g = 168, .b = 24 } }, // #5EA818
        .{ .name = "minecraft:pink_concrete", .color = .{ .r = 213, .g = 101, .b = 142 } }, // #D5658E
        .{ .name = "minecraft:gray_concrete", .color = .{ .r = 54, .g = 57, .b = 61 } }, // #36393D
        .{ .name = "minecraft:light_gray_concrete", .color = .{ .r = 125, .g = 125, .b = 115 } }, // #7D7D73
        .{ .name = "minecraft:cyan_concrete", .color = .{ .r = 21, .g = 119, .b = 136 } }, // #157788
        .{ .name = "minecraft:purple_concrete", .color = .{ .r = 100, .g = 31, .b = 156 } }, // #641F9C
        .{ .name = "minecraft:blue_concrete", .color = .{ .r = 44, .g = 46, .b = 143 } }, // #2C2E8F
        .{ .name = "minecraft:brown_concrete", .color = .{ .r = 96, .g = 59, .b = 31 } }, // #603B1F
        .{ .name = "minecraft:green_concrete", .color = .{ .r = 73, .g = 91, .b = 36 } }, // #495B24
        .{ .name = "minecraft:red_concrete", .color = .{ .r = 142, .g = 32, .b = 32 } }, // #8E2020
        .{ .name = "minecraft:black_concrete", .color = .{ .r = 8, .g = 10, .b = 15 } }, // #080A0F
        // Concrete powder
        .{ .name = "minecraft:white_concrete_powder", .color = .{ .r = 225, .g = 227, .b = 227 } },
        .{ .name = "minecraft:orange_concrete_powder", .color = .{ .r = 227, .g = 131, .b = 31 } },
        .{ .name = "minecraft:magenta_concrete_powder", .color = .{ .r = 192, .g = 83, .b = 184 } },
        .{ .name = "minecraft:light_blue_concrete_powder", .color = .{ .r = 74, .g = 180, .b = 213 } },
        .{ .name = "minecraft:yellow_concrete_powder", .color = .{ .r = 232, .g = 199, .b = 54 } },
        .{ .name = "minecraft:lime_concrete_powder", .color = .{ .r = 125, .g = 187, .b = 53 } },
        .{ .name = "minecraft:pink_concrete_powder", .color = .{ .r = 228, .g = 153, .b = 181 } },
        .{ .name = "minecraft:gray_concrete_powder", .color = .{ .r = 76, .g = 81, .b = 84 } },
        .{ .name = "minecraft:light_gray_concrete_powder", .color = .{ .r = 154, .g = 154, .b = 148 } },
        .{ .name = "minecraft:cyan_concrete_powder", .color = .{ .r = 36, .g = 147, .b = 157 } },
        .{ .name = "minecraft:purple_concrete_powder", .color = .{ .r = 131, .g = 55, .b = 177 } },
        .{ .name = "minecraft:blue_concrete_powder", .color = .{ .r = 70, .g = 73, .b = 166 } },
        .{ .name = "minecraft:brown_concrete_powder", .color = .{ .r = 127, .g = 85, .b = 51 } },
        .{ .name = "minecraft:green_concrete_powder", .color = .{ .r = 97, .g = 119, .b = 44 } },
        .{ .name = "minecraft:red_concrete_powder", .color = .{ .r = 168, .g = 54, .b = 50 } },
        .{ .name = "minecraft:black_concrete_powder", .color = .{ .r = 25, .g = 26, .b = 31 } },

        // =====================================================================
        // Wool (16 colors)
        // =====================================================================
        .{ .name = "minecraft:white_wool", .color = .{ .r = 233, .g = 236, .b = 236 } }, // #E9ECEC
        .{ .name = "minecraft:orange_wool", .color = .{ .r = 240, .g = 118, .b = 19 } }, // #F07613
        .{ .name = "minecraft:magenta_wool", .color = .{ .r = 189, .g = 68, .b = 179 } }, // #BD44B3
        .{ .name = "minecraft:light_blue_wool", .color = .{ .r = 58, .g = 175, .b = 217 } }, // #3AAFD9
        .{ .name = "minecraft:yellow_wool", .color = .{ .r = 248, .g = 197, .b = 39 } }, // #F8C527
        .{ .name = "minecraft:lime_wool", .color = .{ .r = 112, .g = 185, .b = 25 } }, // #70B919
        .{ .name = "minecraft:pink_wool", .color = .{ .r = 237, .g = 141, .b = 172 } }, // #ED8DAC
        .{ .name = "minecraft:gray_wool", .color = .{ .r = 62, .g = 68, .b = 71 } }, // #3E4447
        .{ .name = "minecraft:light_gray_wool", .color = .{ .r = 142, .g = 142, .b = 134 } }, // #8E8E86
        .{ .name = "minecraft:cyan_wool", .color = .{ .r = 21, .g = 137, .b = 145 } }, // #158991
        .{ .name = "minecraft:purple_wool", .color = .{ .r = 121, .g = 42, .b = 172 } }, // #792AAC
        .{ .name = "minecraft:blue_wool", .color = .{ .r = 53, .g = 57, .b = 157 } }, // #35399D
        .{ .name = "minecraft:brown_wool", .color = .{ .r = 114, .g = 71, .b = 40 } }, // #724728
        .{ .name = "minecraft:green_wool", .color = .{ .r = 84, .g = 109, .b = 27 } }, // #546D1B
        .{ .name = "minecraft:red_wool", .color = .{ .r = 160, .g = 39, .b = 34 } }, // #A02722
        .{ .name = "minecraft:black_wool", .color = .{ .r = 20, .g = 21, .b = 25 } }, // #141519

        // =====================================================================
        // Nether blocks
        // =====================================================================
        .{ .name = "minecraft:netherrack", .color = .{ .r = 97, .g = 38, .b = 38 } }, // #612626
        .{ .name = "minecraft:nether_bricks", .color = .{ .r = 44, .g = 21, .b = 26 } }, // #2C151A
        .{ .name = "minecraft:red_nether_bricks", .color = .{ .r = 69, .g = 7, .b = 9 } },
        .{ .name = "minecraft:cracked_nether_bricks", .color = .{ .r = 40, .g = 20, .b = 23 } },
        .{ .name = "minecraft:chiseled_nether_bricks", .color = .{ .r = 47, .g = 23, .b = 27 } },
        .{ .name = "minecraft:basalt", .color = .{ .r = 73, .g = 72, .b = 77 } }, // #49484D
        .{ .name = "minecraft:smooth_basalt", .color = .{ .r = 72, .g = 72, .b = 78 } },
        .{ .name = "minecraft:polished_basalt", .color = .{ .r = 100, .g = 100, .b = 99 } },
        .{ .name = "minecraft:blackstone", .color = .{ .r = 42, .g = 36, .b = 41 } }, // #2A2429
        .{ .name = "minecraft:polished_blackstone", .color = .{ .r = 53, .g = 48, .b = 56 } },
        .{ .name = "minecraft:polished_blackstone_bricks", .color = .{ .r = 48, .g = 42, .b = 49 } },
        .{ .name = "minecraft:chiseled_polished_blackstone", .color = .{ .r = 53, .g = 48, .b = 56 } },
        .{ .name = "minecraft:cracked_polished_blackstone_bricks", .color = .{ .r = 44, .g = 38, .b = 44 } },
        .{ .name = "minecraft:gilded_blackstone", .color = .{ .r = 55, .g = 42, .b = 38 } },
        .{ .name = "minecraft:crimson_nylium", .color = .{ .r = 130, .g = 31, .b = 31 } }, // #821F1F
        .{ .name = "minecraft:warped_nylium", .color = .{ .r = 43, .g = 114, .b = 101 } }, // #2B7265
        .{ .name = "minecraft:nether_wart_block", .color = .{ .r = 114, .g = 2, .b = 2 } }, // #720202
        .{ .name = "minecraft:warped_wart_block", .color = .{ .r = 22, .g = 119, .b = 121 } }, // #167779
        .{ .name = "minecraft:shroomlight", .color = .{ .r = 240, .g = 146, .b = 70 } }, // #F09246
        .{ .name = "minecraft:glowstone", .color = .{ .r = 171, .g = 131, .b = 84 } }, // #AB8354
        .{ .name = "minecraft:magma_block", .color = .{ .r = 142, .g = 63, .b = 31 } }, // #8E3F1F
        .{ .name = "minecraft:crying_obsidian", .color = .{ .r = 32, .g = 10, .b = 60 } }, // #200A3C
        .{ .name = "minecraft:respawn_anchor", .color = .{ .r = 28, .g = 8, .b = 62 } },

        // =====================================================================
        // End blocks
        // =====================================================================
        .{ .name = "minecraft:end_stone", .color = .{ .r = 219, .g = 222, .b = 158 } }, // #DBDE9E
        .{ .name = "minecraft:end_stone_bricks", .color = .{ .r = 218, .g = 224, .b = 162 } },
        .{ .name = "minecraft:purpur_block", .color = .{ .r = 169, .g = 125, .b = 169 } }, // #A97DA9
        .{ .name = "minecraft:purpur_pillar", .color = .{ .r = 171, .g = 129, .b = 171 } },
        .{ .name = "minecraft:chorus_plant", .color = .{ .r = 93, .g = 57, .b = 93 } },
        .{ .name = "minecraft:chorus_flower", .color = .{ .r = 151, .g = 120, .b = 151 } },

        // =====================================================================
        // Ice variants
        // =====================================================================
        .{ .name = "minecraft:ice", .color = .{ .r = 145, .g = 183, .b = 253 } }, // #91B7FD
        .{ .name = "minecraft:packed_ice", .color = .{ .r = 140, .g = 180, .b = 248 } }, // #8CB4F8
        .{ .name = "minecraft:blue_ice", .color = .{ .r = 116, .g = 167, .b = 253 } }, // #74A7FD
        .{ .name = "minecraft:frosted_ice", .color = .{ .r = 140, .g = 180, .b = 248 } },

        // =====================================================================
        // Prismarine variants
        // =====================================================================
        .{ .name = "minecraft:prismarine", .color = .{ .r = 99, .g = 156, .b = 151 } }, // #639C97
        .{ .name = "minecraft:prismarine_bricks", .color = .{ .r = 99, .g = 171, .b = 158 } }, // #63AB9E
        .{ .name = "minecraft:dark_prismarine", .color = .{ .r = 51, .g = 91, .b = 75 } }, // #335B4B
        .{ .name = "minecraft:sea_lantern", .color = .{ .r = 172, .g = 199, .b = 190 } }, // #ACC7BE

        // =====================================================================
        // Common building blocks
        // =====================================================================
        .{ .name = "minecraft:cobblestone", .color = .{ .r = 127, .g = 127, .b = 127 } }, // #7F7F7F
        .{ .name = "minecraft:mossy_cobblestone", .color = .{ .r = 110, .g = 127, .b = 93 } }, // #6E7F5D
        .{ .name = "minecraft:stone_bricks", .color = .{ .r = 122, .g = 121, .b = 122 } }, // #7A797A
        .{ .name = "minecraft:mossy_stone_bricks", .color = .{ .r = 115, .g = 121, .b = 105 } },
        .{ .name = "minecraft:cracked_stone_bricks", .color = .{ .r = 118, .g = 117, .b = 118 } },
        .{ .name = "minecraft:chiseled_stone_bricks", .color = .{ .r = 119, .g = 118, .b = 119 } },
        .{ .name = "minecraft:bricks", .color = .{ .r = 150, .g = 97, .b = 83 } }, // #966153
        .{ .name = "minecraft:stone_brick_stairs", .color = .{ .r = 122, .g = 121, .b = 122 } },
        .{ .name = "minecraft:cobblestone_stairs", .color = .{ .r = 127, .g = 127, .b = 127 } },
        .{ .name = "minecraft:brick_stairs", .color = .{ .r = 150, .g = 97, .b = 83 } },
        .{ .name = "minecraft:stone_slab", .color = .{ .r = 158, .g = 158, .b = 158 } },
        .{ .name = "minecraft:cobblestone_slab", .color = .{ .r = 127, .g = 127, .b = 127 } },
        .{ .name = "minecraft:stone_brick_slab", .color = .{ .r = 122, .g = 121, .b = 122 } },
        .{ .name = "minecraft:brick_slab", .color = .{ .r = 150, .g = 97, .b = 83 } },
        .{ .name = "minecraft:cobblestone_wall", .color = .{ .r = 127, .g = 127, .b = 127 } },
        .{ .name = "minecraft:stone_brick_wall", .color = .{ .r = 122, .g = 121, .b = 122 } },
        .{ .name = "minecraft:brick_wall", .color = .{ .r = 150, .g = 97, .b = 83 } },

        // =====================================================================
        // Misc blocks
        // =====================================================================
        .{ .name = "minecraft:obsidian", .color = .{ .r = 15, .g = 10, .b = 24 } }, // #0F0A18
        .{ .name = "minecraft:bedrock", .color = .{ .r = 85, .g = 85, .b = 85 } }, // #555555
        .{ .name = "minecraft:sponge", .color = .{ .r = 195, .g = 192, .b = 74 } }, // #C3C04A
        .{ .name = "minecraft:wet_sponge", .color = .{ .r = 171, .g = 181, .b = 70 } },
        .{ .name = "minecraft:tnt", .color = .{ .r = 219, .g = 68, .b = 44 } }, // #DB442C
        .{ .name = "minecraft:bookshelf", .color = .{ .r = 162, .g = 130, .b = 78 } }, // same as oak planks top
        .{ .name = "minecraft:chiseled_bookshelf", .color = .{ .r = 162, .g = 130, .b = 78 } },
        .{ .name = "minecraft:crafting_table", .color = .{ .r = 121, .g = 80, .b = 47 } }, // #794F2F
        .{ .name = "minecraft:furnace", .color = .{ .r = 129, .g = 129, .b = 129 } },
        .{ .name = "minecraft:blast_furnace", .color = .{ .r = 100, .g = 100, .b = 100 } },
        .{ .name = "minecraft:smoker", .color = .{ .r = 100, .g = 91, .b = 78 } },
        .{ .name = "minecraft:hay_block", .color = .{ .r = 166, .g = 138, .b = 36 } }, // #A68A24
        .{ .name = "minecraft:melon", .color = .{ .r = 111, .g = 144, .b = 30 } }, // #6F901E
        .{ .name = "minecraft:pumpkin", .color = .{ .r = 198, .g = 118, .b = 24 } }, // #C67618
        .{ .name = "minecraft:carved_pumpkin", .color = .{ .r = 198, .g = 118, .b = 24 } },
        .{ .name = "minecraft:jack_o_lantern", .color = .{ .r = 198, .g = 118, .b = 24 } },
        .{ .name = "minecraft:bone_block", .color = .{ .r = 229, .g = 225, .b = 207 } }, // #E5E1CF
        .{ .name = "minecraft:dried_kelp_block", .color = .{ .r = 50, .g = 58, .b = 37 } }, // #323A25
        .{ .name = "minecraft:honeycomb_block", .color = .{ .r = 229, .g = 148, .b = 29 } }, // #E5941D
        .{ .name = "minecraft:honey_block", .color = .{ .r = 251, .g = 186, .b = 55 } }, // #FBBA37
        .{ .name = "minecraft:slime_block", .color = .{ .r = 112, .g = 192, .b = 91 } }, // #70C05B
        .{ .name = "minecraft:snow_block", .color = .{ .r = 249, .g = 254, .b = 254 } }, // #F9FEFE
        .{ .name = "minecraft:powder_snow", .color = .{ .r = 248, .g = 253, .b = 253 } },
        .{ .name = "minecraft:sculk", .color = .{ .r = 12, .g = 30, .b = 36 } }, // #0C1E24
        .{ .name = "minecraft:sculk_catalyst", .color = .{ .r = 15, .g = 32, .b = 38 } },
        .{ .name = "minecraft:sculk_vein", .color = .{ .r = 12, .g = 30, .b = 36 } },
        .{ .name = "minecraft:sculk_shrieker", .color = .{ .r = 12, .g = 30, .b = 36 } },
        .{ .name = "minecraft:sculk_sensor", .color = .{ .r = 7, .g = 56, .b = 66 } },
        .{ .name = "minecraft:ochre_froglight", .color = .{ .r = 250, .g = 228, .b = 170 } },
        .{ .name = "minecraft:verdant_froglight", .color = .{ .r = 229, .g = 244, .b = 215 } },
        .{ .name = "minecraft:pearlescent_froglight", .color = .{ .r = 245, .g = 222, .b = 237 } },
        .{ .name = "minecraft:mushroom_stem", .color = .{ .r = 203, .g = 196, .b = 185 } },
        .{ .name = "minecraft:red_mushroom_block", .color = .{ .r = 200, .g = 46, .b = 45 } },
        .{ .name = "minecraft:brown_mushroom_block", .color = .{ .r = 149, .g = 111, .b = 81 } },
        .{ .name = "minecraft:cactus", .color = .{ .r = 85, .g = 127, .b = 43 } }, // #557F2B
        .{ .name = "minecraft:note_block", .color = .{ .r = 100, .g = 67, .b = 50 } },
        .{ .name = "minecraft:jukebox", .color = .{ .r = 100, .g = 67, .b = 50 } },
        .{ .name = "minecraft:enchanting_table", .color = .{ .r = 20, .g = 10, .b = 28 } },
        .{ .name = "minecraft:end_portal_frame", .color = .{ .r = 106, .g = 131, .b = 97 } },
        .{ .name = "minecraft:beacon", .color = .{ .r = 117, .g = 225, .b = 215 } },
        .{ .name = "minecraft:conduit", .color = .{ .r = 161, .g = 143, .b = 119 } },

        // Fluids (for non-transparent rendering modes)
        .{ .name = "minecraft:water", .color = .{ .r = 56, .g = 89, .b = 163 } }, // #3859A3
        .{ .name = "minecraft:lava", .color = .{ .r = 207, .g = 91, .b = 10 } }, // #CF5B0A

        // =====================================================================
        // Miscellaneous utility / redstone
        // =====================================================================
        .{ .name = "minecraft:dispenser", .color = .{ .r = 129, .g = 129, .b = 129 } },
        .{ .name = "minecraft:dropper", .color = .{ .r = 129, .g = 129, .b = 129 } },
        .{ .name = "minecraft:observer", .color = .{ .r = 100, .g = 100, .b = 100 } },
        .{ .name = "minecraft:piston", .color = .{ .r = 153, .g = 127, .b = 85 } },
        .{ .name = "minecraft:sticky_piston", .color = .{ .r = 142, .g = 163, .b = 101 } },
        .{ .name = "minecraft:hopper", .color = .{ .r = 73, .g = 73, .b = 73 } },
        .{ .name = "minecraft:chest", .color = .{ .r = 162, .g = 130, .b = 78 } },
        .{ .name = "minecraft:barrel", .color = .{ .r = 139, .g = 107, .b = 63 } },
        .{ .name = "minecraft:ender_chest", .color = .{ .r = 37, .g = 41, .b = 47 } },
        .{ .name = "minecraft:anvil", .color = .{ .r = 72, .g = 72, .b = 72 } },
        .{ .name = "minecraft:grindstone", .color = .{ .r = 142, .g = 142, .b = 142 } },
        .{ .name = "minecraft:stonecutter", .color = .{ .r = 146, .g = 140, .b = 136 } },
        .{ .name = "minecraft:cartography_table", .color = .{ .r = 104, .g = 80, .b = 48 } },
        .{ .name = "minecraft:fletching_table", .color = .{ .r = 194, .g = 175, .b = 120 } },
        .{ .name = "minecraft:smithing_table", .color = .{ .r = 57, .g = 57, .b = 70 } },
        .{ .name = "minecraft:loom", .color = .{ .r = 155, .g = 122, .b = 84 } },
        .{ .name = "minecraft:composter", .color = .{ .r = 101, .g = 72, .b = 32 } },
        .{ .name = "minecraft:lectern", .color = .{ .r = 168, .g = 126, .b = 69 } },
        .{ .name = "minecraft:cauldron", .color = .{ .r = 72, .g = 72, .b = 72 } },
        .{ .name = "minecraft:brewing_stand", .color = .{ .r = 122, .g = 100, .b = 63 } },
        .{ .name = "minecraft:bell", .color = .{ .r = 228, .g = 185, .b = 46 } },
        .{ .name = "minecraft:lodestone", .color = .{ .r = 148, .g = 149, .b = 152 } },
        .{ .name = "minecraft:target", .color = .{ .r = 226, .g = 184, .b = 167 } },
        .{ .name = "minecraft:beehive", .color = .{ .r = 182, .g = 147, .b = 86 } },
        .{ .name = "minecraft:bee_nest", .color = .{ .r = 188, .g = 149, .b = 72 } },

        // =====================================================================
        // Beds (top color)
        // =====================================================================
        .{ .name = "minecraft:white_bed", .color = .{ .r = 233, .g = 236, .b = 236 } },
        .{ .name = "minecraft:red_bed", .color = .{ .r = 160, .g = 39, .b = 34 } },
    };

    for (&entries) |e| {
        if (std.mem.eql(u8, name, e.name)) return e.color;
    }
    return null;
}

const std = @import("std");
