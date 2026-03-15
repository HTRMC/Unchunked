const std = @import("std");

pub const TagType = enum(u8) {
    end = 0,
    byte = 1,
    short = 2,
    int = 3,
    long = 4,
    float = 5,
    double = 6,
    byte_array = 7,
    string = 8,
    list = 9,
    compound = 10,
    int_array = 11,
    long_array = 12,
};

pub const NbtReader = struct {
    data: []const u8,
    pos: usize = 0,

    pub fn init(data: []const u8) NbtReader {
        return .{ .data = data };
    }

    pub fn readTagType(self: *NbtReader) !TagType {
        if (self.pos >= self.data.len) return error.EndOfData;
        const byte = self.data[self.pos];
        self.pos += 1;
        return std.meta.intToEnum(TagType, byte) catch error.InvalidTag;
    }

    pub fn readString(self: *NbtReader) ![]const u8 {
        const len = try self.readU16();
        if (self.pos + len > self.data.len) return error.EndOfData;
        const str = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return str;
    }

    pub fn readU16(self: *NbtReader) !u16 {
        if (self.pos + 2 > self.data.len) return error.EndOfData;
        const val = std.mem.readInt(u16, self.data[self.pos..][0..2], .big);
        self.pos += 2;
        return val;
    }

    pub fn readI32(self: *NbtReader) !i32 {
        if (self.pos + 4 > self.data.len) return error.EndOfData;
        const val = std.mem.readInt(i32, self.data[self.pos..][0..4], .big);
        self.pos += 4;
        return val;
    }

    pub fn readI64(self: *NbtReader) !i64 {
        if (self.pos + 8 > self.data.len) return error.EndOfData;
        const val = std.mem.readInt(i64, self.data[self.pos..][0..8], .big);
        self.pos += 8;
        return val;
    }

    pub fn skipTag(self: *NbtReader, tag_type: TagType) !void {
        switch (tag_type) {
            .end => {},
            .byte => self.pos += 1,
            .short => self.pos += 2,
            .int, .float => self.pos += 4,
            .long, .double => self.pos += 8,
            .byte_array => {
                const len = try self.readI32();
                self.pos += @intCast(len);
            },
            .string => {
                const len = try self.readU16();
                self.pos += len;
            },
            .list => {
                const elem_type = try self.readTagType();
                const count = try self.readI32();
                for (0..@intCast(count)) |_| {
                    try self.skipTag(elem_type);
                }
            },
            .compound => {
                while (true) {
                    const child_type = try self.readTagType();
                    if (child_type == .end) break;
                    _ = try self.readString(); // name
                    try self.skipTag(child_type);
                }
            },
            .int_array => {
                const len = try self.readI32();
                self.pos += @as(usize, @intCast(len)) * 4;
            },
            .long_array => {
                const len = try self.readI32();
                self.pos += @as(usize, @intCast(len)) * 8;
            },
        }
    }

    pub fn findCompoundKey(self: *NbtReader, target: []const u8) !?TagType {
        while (true) {
            const tag_type = try self.readTagType();
            if (tag_type == .end) return null;

            const name = try self.readString();
            if (std.mem.eql(u8, name, target)) {
                return tag_type;
            }

            try self.skipTag(tag_type);
        }
    }

    pub fn readLongArray(self: *NbtReader, allocator: std.mem.Allocator) ![]i64 {
        const len = try self.readI32();
        if (len <= 0) return &.{};

        const count: usize = @intCast(len);
        const arr = try allocator.alloc(i64, count);
        for (0..count) |i| {
            arr[i] = try self.readI64();
        }
        return arr;
    }
};

pub fn extractAverageHeight(heightmap_longs: []const i64) u8 {
    // Minecraft heightmaps pack 256 values (16x16) into long array
    // Each value is 9 bits for worlds up to y=320
    const bits_per_value: u6 = 9;
    const values_per_long: usize = 64 / bits_per_value; // 7
    const mask: u64 = (@as(u64, 1) << bits_per_value) - 1;

    var total: u64 = 0;
    var count: u64 = 0;

    for (heightmap_longs) |long_val| {
        const ulong: u64 = @bitCast(long_val);
        for (0..values_per_long) |j| {
            if (count >= 256) break;
            const shift: u6 = @intCast(j * bits_per_value);
            const height = (ulong >> shift) & mask;
            total += height;
            count += 1;
        }
    }

    if (count == 0) return 64;
    return @intCast(@min(total / count, 255));
}
