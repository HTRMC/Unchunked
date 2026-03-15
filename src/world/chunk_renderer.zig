const std = @import("std");
const block_colors = @import("block_colors.zig");
const biome_colors = @import("biome_colors.zig");

pub const ChunkPixels = [16][16][4]u8; // [z][x][rgba]

/// Get the top block name at a specific (bx, bz) position within a chunk.
/// Returns a slice into the nbt_data (valid as long as nbt_data is alive).
pub fn getTopBlockAt(nbt_data: []const u8, bx: u4, bz: u4) ?[]const u8 {
    var reader = NbtReader.init(nbt_data);

    const root_type = reader.readByte() orelse return null;
    if (root_type != 10) return null;
    reader.skipString();

    while (!reader.eof()) {
        const tag_type = reader.readByte() orelse break;
        if (tag_type == 0) break;
        const name = reader.readShortString() orelse break;

        if (tag_type == 9 and std.mem.eql(u8, name, "sections")) {
            const list_tag_type = reader.readByte() orelse return null;
            if (list_tag_type != 10) return null;
            const section_count = reader.readInt() orelse return null;

            const max_sections = 32;
            var sections: [max_sections]SectionData = undefined;
            var valid_sections: u32 = 0;

            var i: i32 = 0;
            while (i < section_count) : (i += 1) {
                if (valid_sections < max_sections) {
                    if (parseSingleSection(&reader)) |sec| {
                        sections[valid_sections] = sec;
                        valid_sections += 1;
                    }
                } else {
                    reader.skipTag(10);
                }
            }

            sortSectionsDescending(sections[0..valid_sections]);

            for (sections[0..valid_sections]) |*sec| {
                var y: i32 = 15;
                while (y >= 0) : (y -= 1) {
                    const block_name = getBlockAt(sec, bx, bz, y) orelse continue;
                    if (block_colors.isTransparent(block_name)) continue;
                    return block_name;
                }
            }
            return null;
        } else {
            reader.skipTag(tag_type);
        }
    }
    return null;
}

pub fn renderChunk(nbt_data: []const u8, pixels: *ChunkPixels) void {
    // Initialize to transparent
    for (pixels) |*row| {
        for (row) |*px| {
            px.* = .{ 0, 0, 0, 0 };
        }
    }

    // Track heights for shading
    var heights: [16][16]i32 = .{.{UNSET_HEIGHT} ** 16} ** 16;

    var reader = NbtReader.init(nbt_data);

    // Read root compound tag
    const root_type = reader.readByte() orelse return;
    if (root_type != 10) return; // must be compound
    reader.skipString(); // root name

    // Find "sections" list in root compound
    var found_sections = false;
    while (!reader.eof()) {
        const tag_type = reader.readByte() orelse break;
        if (tag_type == 0) break; // end of compound

        const name = reader.readShortString() orelse break;

        if (tag_type == 9 and std.mem.eql(u8, name, "sections")) {
            found_sections = true;
            parseSections(&reader, pixels, &heights);
            break;
        } else {
            reader.skipTag(tag_type);
        }
    }

    if (!found_sections) return;

    // Apply height shading
    applyHeightShading(pixels, &heights);
}

fn parseSections(reader: *NbtReader, pixels: *ChunkPixels, heights: *[16][16]i32) void {
    const list_tag_type = reader.readByte() orelse return;
    if (list_tag_type != 10) { // sections must be list of compounds
        return;
    }
    const section_count = reader.readInt() orelse return;

    // Parse all sections, collect them sorted by Y (high to low)
    const max_sections = 32;
    var sections: [max_sections]SectionData = undefined;
    var valid_sections: u32 = 0;

    var i: i32 = 0;
    while (i < section_count) : (i += 1) {
        if (valid_sections < max_sections) {
            if (parseSingleSection(reader)) |sec| {
                sections[valid_sections] = sec;
                valid_sections += 1;
            }
        } else {
            // Skip remaining sections
            reader.skipTag(10);
        }
    }

    // Sort by Y descending (top-down)
    sortSectionsDescending(sections[0..valid_sections]);

    // For each X/Z column, find topmost block with water overlay support
    for (0..16) |z| {
        for (0..16) |x| {
            var water_height: ?i32 = null;
            var water_biome: []const u8 = "";
            var found = false;

            for (sections[0..valid_sections]) |*sec| {
                if (found) break;

                const lx: u4 = @intCast(x);
                const lz: u4 = @intCast(z);

                // Scan Y levels in this section (top-down)
                var y: i32 = 15;
                while (y >= 0) : (y -= 1) {
                    const block_name = getBlockAt(sec, lx, lz, y) orelse continue;

                    if (block_colors.isTransparent(block_name)) continue;

                    const abs_y = @as(i32, sec.y) * 16 + y;

                    if (block_colors.isWater(block_name)) {
                        if (water_height == null) {
                            water_height = abs_y;
                            water_biome = getBiomeAt(sec, @intCast(x), y, @intCast(z));
                        }
                        continue;
                    }

                    // Solid terrain block found
                    const entry = block_colors.lookup(block_name) orelse
                        block_colors.BlockEntry{ .name = block_name, .color = .{ .r = 180, .g = 100, .b = 200 }, .tint = 0 };

                    const biome_name = getBiomeAt(sec, @intCast(x), y, @intCast(z));
                    var terrain_color = applyTintFlags(entry.color, entry.tint, block_name, biome_name);

                    heights[z][x] = abs_y;

                    if (water_height) |wh| {
                        // Get base water color and tint it with biome water tint
                        const water_base = if (block_colors.lookup("minecraft:water")) |we|
                            we.color
                        else
                            block_colors.Color{ .r = 176, .g = 176, .b = 176 };
                        const water_tint = biome_colors.getBiomeTint(water_biome, .water);
                        const tinted_water = biome_colors.applyTint(water_base, water_tint);

                        // Blend tinted water over terrain based on depth
                        const depth = wh - abs_y;
                        const ratio = 0.5 - 0.5 / 40.0 * @as(f32, @floatFromInt(@min(depth, 40)));
                        const inv_ratio = 1.0 - ratio;

                        const wr: f32 = @floatFromInt(tinted_water.r);
                        const wg: f32 = @floatFromInt(tinted_water.g);
                        const wb: f32 = @floatFromInt(tinted_water.b);
                        const tr: f32 = @floatFromInt(terrain_color.r);
                        const tg: f32 = @floatFromInt(terrain_color.g);
                        const tb: f32 = @floatFromInt(terrain_color.b);

                        pixels[z][x] = .{
                            @intFromFloat(wr * inv_ratio + tr * ratio),
                            @intFromFloat(wg * inv_ratio + tg * ratio),
                            @intFromFloat(wb * inv_ratio + tb * ratio),
                            255,
                        };
                    } else {
                        pixels[z][x] = .{ terrain_color.r, terrain_color.g, terrain_color.b, 255 };
                    }
                    found = true;
                    break;
                }
            }

            // Water with no terrain below (deep ocean, void)
            if (water_height != null and !found) {
                const water_base = if (block_colors.lookup("minecraft:water")) |we|
                    we.color
                else
                    block_colors.Color{ .r = 176, .g = 176, .b = 176 };
                const water_tint = biome_colors.getBiomeTint(water_biome, .water);
                const wc = biome_colors.applyTint(water_base, water_tint);
                pixels[z][x] = .{ wc.r, wc.g, wc.b, 255 };
                heights[z][x] = water_height.?;
            }
        }
    }
}

fn applyTintFlags(color: block_colors.Color, tint_flags: u8, block_name: []const u8, biome_name: []const u8) block_colors.Color {
    if (tint_flags == 0) return color;

    // Static tint (biome-independent: birch/spruce leaves, lily pad)
    if (tint_flags & block_colors.TINT_STATIC != 0) {
        if (biome_colors.getStaticTint(block_name)) |tint| {
            return biome_colors.applyTint(color, tint);
        }
        return color;
    }

    // Grass tint
    if (tint_flags & block_colors.TINT_GRASS != 0) {
        return biome_colors.applyTint(color, biome_colors.getBiomeTint(biome_name, .grass));
    }

    // Foliage tint
    if (tint_flags & block_colors.TINT_FOLIAGE != 0) {
        return biome_colors.applyTint(color, biome_colors.getBiomeTint(biome_name, .foliage));
    }

    // Dry foliage tint
    if (tint_flags & block_colors.TINT_DRY_FOLIAGE != 0) {
        return biome_colors.applyTint(color, biome_colors.getBiomeTint(biome_name, .dry_foliage));
    }

    return color;
}

fn getBlockAt(sec: *const SectionData, x: u4, z: u4, y: i32) ?[]const u8 {
    if (sec.palette_count == 0) return null;
    if (sec.palette_count == 1) return if (sec.palette_names[0].len > 0) sec.palette_names[0] else null;
    if (sec.data_longs == 0) return null;

    const block_index: u32 = @intCast(y * 256 + @as(i32, z) * 16 + @as(i32, x));
    const palette_idx = getBlockIndex(sec, block_index) orelse return null;
    if (palette_idx >= sec.palette_count) return null;

    const name = sec.palette_names[palette_idx];
    return if (name.len > 0) name else null;
}

const BlockResult = struct {
    name: []const u8,
    local_y: i32,
};

fn findTopBlock(sec: *const SectionData, x: u4, z: u4) ?BlockResult {
    if (sec.palette_count == 0) return null;

    // If palette has only 1 entry, the whole section is that block
    if (sec.palette_count == 1) {
        const name = sec.palette_names[0];
        if (name.len == 0 or block_colors.isTransparent(name)) return null;
        return .{ .name = name, .local_y = 15 };
    }

    // Check data array
    if (sec.data_longs == 0) return null;

    // Scan from top (y=15) to bottom (y=0)
    var y: i32 = 15;
    while (y >= 0) : (y -= 1) {
        const block_index: u32 = @intCast(y * 256 + @as(i32, z) * 16 + @as(i32, x));
        const palette_idx = getBlockIndex(sec, block_index) orelse continue;

        if (palette_idx < sec.palette_count) {
            const name = sec.palette_names[palette_idx];
            if (name.len > 0 and !block_colors.isTransparent(name)) {
                return .{ .name = name, .local_y = y };
            }
        }
    }
    return null;
}

fn getBlockIndex(sec: *const SectionData, block_index: u32) ?u32 {
    if (sec.bits_per_entry == 0 or sec.data_longs == 0) return null;

    const entries_per_long: u32 = 64 / sec.bits_per_entry;
    const long_index = block_index / entries_per_long;
    const bit_offset = (block_index % entries_per_long) * sec.bits_per_entry;

    if (long_index >= sec.data_longs) return null;

    // Read big-endian i64 from unaligned byte data
    const byte_offset = long_index * 8;
    const long_val = std.mem.readInt(u64, sec.data_ptr[byte_offset..][0..8], .big);
    const mask = (@as(u64, 1) << @intCast(sec.bits_per_entry)) - 1;
    return @intCast((long_val >> @intCast(bit_offset)) & mask);
}

const MAX_PALETTE = 256;

const MAX_BIOME_PALETTE = 64;

const SectionData = struct {
    y: i8 = 0,
    palette_names: [MAX_PALETTE][]const u8 = .{""} ** MAX_PALETTE,
    palette_count: u32 = 0,
    data_ptr: [*]const u8 = undefined,
    data_longs: u32 = 0,
    bits_per_entry: u32 = 0,
    // Biome data (4x4x4 resolution)
    biome_palette: [MAX_BIOME_PALETTE][]const u8 = .{""} ** MAX_BIOME_PALETTE,
    biome_palette_count: u32 = 0,
    biome_data_ptr: [*]const u8 = undefined,
    biome_data_longs: u32 = 0,
    biome_bits_per_entry: u32 = 0,
};

fn parseSingleSection(reader: *NbtReader) ?SectionData {
    var sec = SectionData{};
    var has_y = false;

    while (!reader.eof()) {
        const tag_type = reader.readByte() orelse break;
        if (tag_type == 0) break; // end of section compound

        const name = reader.readShortString() orelse break;

        if (tag_type == 1 and std.mem.eql(u8, name, "Y")) {
            // Byte tag
            const y_val = reader.readByte() orelse break;
            sec.y = @bitCast(y_val);
            has_y = true;
        } else if (tag_type == 10 and std.mem.eql(u8, name, "block_states")) {
            parseBlockStates(reader, &sec);
        } else if (tag_type == 10 and std.mem.eql(u8, name, "biomes")) {
            parseBiomes(reader, &sec);
        } else {
            reader.skipTag(tag_type);
        }
    }

    if (!has_y) return null;
    return sec;
}

fn parseBlockStates(reader: *NbtReader, sec: *SectionData) void {
    while (!reader.eof()) {
        const tag_type = reader.readByte() orelse break;
        if (tag_type == 0) break;

        const name = reader.readShortString() orelse break;

        if (tag_type == 9 and std.mem.eql(u8, name, "palette")) {
            // List of compound tags
            const elem_type = reader.readByte() orelse break;
            const count = reader.readInt() orelse break;

            if (elem_type != 10) {
                // Not compound, skip
                var j: i32 = 0;
                while (j < count) : (j += 1) reader.skipTag(elem_type);
                continue;
            }

            var j: u32 = 0;
            while (j < @as(u32, @intCast(count)) and j < MAX_PALETTE) : (j += 1) {
                sec.palette_names[j] = parsePaletteEntry(reader);
            }
            sec.palette_count = j;

            // Compute bits per entry
            if (sec.palette_count > 1) {
                var bits: u32 = 4; // minimum 4 bits
                const max_idx = sec.palette_count - 1;
                while ((@as(u32, 1) << @intCast(bits)) <= max_idx) bits += 1;
                sec.bits_per_entry = bits;
            }
        } else if (tag_type == 12 and std.mem.eql(u8, name, "data")) {
            // Long array
            const count = reader.readInt() orelse break;
            if (count <= 0) continue;
            const ucount: u32 = @intCast(count);

            // Point directly into the NBT data (longs are big-endian, need to convert)
            // Actually, we need to read the longs properly
            if (reader.pos + ucount * 8 <= reader.data.len) {
                sec.data_ptr = reader.data[reader.pos..].ptr;
                sec.data_longs = ucount;
                reader.pos += ucount * 8;
            } else {
                reader.pos = reader.data.len;
            }
        } else {
            reader.skipTag(tag_type);
        }
    }
}

fn parsePaletteEntry(reader: *NbtReader) []const u8 {
    var block_name: []const u8 = "";

    while (!reader.eof()) {
        const tag_type = reader.readByte() orelse break;
        if (tag_type == 0) break;

        const name = reader.readShortString() orelse break;

        if (tag_type == 8 and std.mem.eql(u8, name, "Name")) {
            block_name = reader.readShortString() orelse "";
        } else {
            reader.skipTag(tag_type);
        }
    }
    return block_name;
}

fn parseBiomes(reader: *NbtReader, sec: *SectionData) void {
    while (!reader.eof()) {
        const tag_type = reader.readByte() orelse break;
        if (tag_type == 0) break;

        const name = reader.readShortString() orelse break;

        if (tag_type == 9 and std.mem.eql(u8, name, "palette")) {
            // List of string tags (biome names)
            const elem_type = reader.readByte() orelse break;
            const count = reader.readInt() orelse break;

            if (elem_type != 8) { // must be string
                var j: i32 = 0;
                while (j < count) : (j += 1) reader.skipTag(elem_type);
                continue;
            }

            var j: u32 = 0;
            while (j < @as(u32, @intCast(count)) and j < MAX_BIOME_PALETTE) : (j += 1) {
                sec.biome_palette[j] = reader.readShortString() orelse "";
            }
            sec.biome_palette_count = j;

            if (sec.biome_palette_count > 1) {
                var bits: u32 = 1;
                const max_idx = sec.biome_palette_count - 1;
                while ((@as(u32, 1) << @intCast(bits)) <= max_idx) bits += 1;
                sec.biome_bits_per_entry = bits;
            }
        } else if (tag_type == 12 and std.mem.eql(u8, name, "data")) {
            const count = reader.readInt() orelse break;
            if (count <= 0) continue;
            const ucount: u32 = @intCast(count);
            if (reader.pos + ucount * 8 <= reader.data.len) {
                sec.biome_data_ptr = reader.data[reader.pos..].ptr;
                sec.biome_data_longs = ucount;
                reader.pos += ucount * 8;
            } else {
                reader.pos = reader.data.len;
            }
        } else {
            reader.skipTag(tag_type);
        }
    }
}

fn getBiomeAt(sec: *const SectionData, x: u4, y: i32, z: u4) []const u8 {
    if (sec.biome_palette_count == 0) return "";
    if (sec.biome_palette_count == 1) return sec.biome_palette[0];
    if (sec.biome_data_longs == 0) return sec.biome_palette[0];

    // Biomes are 4x4x4 within a 16x16x16 section
    const bx: u32 = @as(u32, x) >> 2;
    const by: u32 = @intCast(@as(u32, @intCast(y)) >> 2);
    const bz: u32 = @as(u32, z) >> 2;
    const index = by * 16 + bz * 4 + bx;

    const entries_per_long: u32 = 64 / sec.biome_bits_per_entry;
    const long_index = index / entries_per_long;
    const bit_offset = (index % entries_per_long) * sec.biome_bits_per_entry;

    if (long_index >= sec.biome_data_longs) return sec.biome_palette[0];

    const byte_offset = long_index * 8;
    const long_val = std.mem.readInt(u64, sec.biome_data_ptr[byte_offset..][0..8], .big);
    const mask = (@as(u64, 1) << @intCast(sec.biome_bits_per_entry)) - 1;
    const palette_idx: u32 = @intCast((long_val >> @intCast(bit_offset)) & mask);

    if (palette_idx >= sec.biome_palette_count) return sec.biome_palette[0];
    return sec.biome_palette[palette_idx];
}

fn sortSectionsDescending(sections: []SectionData) void {
    // Simple insertion sort by Y descending
    for (1..sections.len) |i| {
        var j = i;
        while (j > 0 and sections[j].y > sections[j - 1].y) {
            const tmp = sections[j];
            sections[j] = sections[j - 1];
            sections[j - 1] = tmp;
            j -= 1;
        }
    }
}

const UNSET_HEIGHT: i32 = std.math.minInt(i32);

fn applyHeightShading(pixels: *ChunkPixels, heights: *const [16][16]i32) void {
    for (0..16) |z| {
        for (0..16) |x| {
            if (pixels[z][x][3] == 0) continue;

            var shade: i32 = 0;
            var count: i32 = 0;
            // Compare with neighbors, only if neighbor has valid height
            if (z > 0 and heights[z - 1][x] != UNSET_HEIGHT) {
                shade += heights[z][x] - heights[z - 1][x];
                count += 1;
            }
            if (x > 0 and heights[z][x - 1] != UNSET_HEIGHT) {
                shade += heights[z][x] - heights[z][x - 1];
                count += 1;
            }

            if (count == 0) continue;
            shade = std.math.clamp(shade * 6, -30, 30);

            pixels[z][x][0] = @intCast(std.math.clamp(@as(i32, pixels[z][x][0]) + shade, 0, 255));
            pixels[z][x][1] = @intCast(std.math.clamp(@as(i32, pixels[z][x][1]) + shade, 0, 255));
            pixels[z][x][2] = @intCast(std.math.clamp(@as(i32, pixels[z][x][2]) + shade, 0, 255));
        }
    }
}

// Simple NBT reader that operates on raw bytes (already decompressed)
const NbtReader = struct {
    data: []const u8,
    pos: usize = 0,

    fn init(data: []const u8) NbtReader {
        return .{ .data = data, .pos = 0 };
    }

    fn eof(self: *const NbtReader) bool {
        return self.pos >= self.data.len;
    }

    fn readByte(self: *NbtReader) ?u8 {
        if (self.pos >= self.data.len) return null;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readShort(self: *NbtReader) ?u16 {
        if (self.pos + 2 > self.data.len) return null;
        const val = std.mem.readInt(u16, self.data[self.pos..][0..2], .big);
        self.pos += 2;
        return val;
    }

    fn readInt(self: *NbtReader) ?i32 {
        if (self.pos + 4 > self.data.len) return null;
        const val = std.mem.readInt(i32, self.data[self.pos..][0..4], .big);
        self.pos += 4;
        return val;
    }

    fn readShortString(self: *NbtReader) ?[]const u8 {
        const len = self.readShort() orelse return null;
        if (self.pos + len > self.data.len) return null;
        const str = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return str;
    }

    fn skipString(self: *NbtReader) void {
        _ = self.readShortString();
    }

    fn skipTag(self: *NbtReader, tag_type: u8) void {
        switch (tag_type) {
            0 => {}, // end
            1 => self.pos += 1, // byte
            2 => self.pos += 2, // short
            3 => self.pos += 4, // int
            4 => self.pos += 8, // long
            5 => self.pos += 4, // float
            6 => self.pos += 8, // double
            7 => { // byte array
                const len = self.readInt() orelse return;
                if (len > 0) self.pos += @intCast(len);
            },
            8 => self.skipString(), // string
            9 => { // list
                const elem_type = self.readByte() orelse return;
                const count = self.readInt() orelse return;
                var i: i32 = 0;
                while (i < count) : (i += 1) self.skipTag(elem_type);
            },
            10 => { // compound
                while (!self.eof()) {
                    const child_type = self.readByte() orelse return;
                    if (child_type == 0) break;
                    self.skipString();
                    self.skipTag(child_type);
                }
            },
            11 => { // int array
                const len = self.readInt() orelse return;
                if (len > 0) self.pos += @as(usize, @intCast(len)) * 4;
            },
            12 => { // long array
                const len = self.readInt() orelse return;
                if (len > 0) self.pos += @as(usize, @intCast(len)) * 8;
            },
            else => {},
        }
    }
};
