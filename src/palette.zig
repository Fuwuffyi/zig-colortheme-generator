const std = @import("std");
const image = @import("image.zig");
const color = @import("color.zig");

pub const Palette = struct {
    pub const PaletteValue = struct { clr: color.ColorHSL, weight: u32 };

    values: []const PaletteValue,

    pub fn init(allocator: *const std.mem.Allocator, img: *const image.Image) !@This() {
        // Create list of colors
        var colors_hashmap: std.AutoHashMap(u96, u32) = std.AutoHashMap(u96, u32).init(allocator.*);
        defer colors_hashmap.deinit();
        try colors_hashmap.ensureTotalCapacity(@as(u32, @intCast(img.colors.len)));
        // Loop over the image colors
        for (img.colors) |clr| {
            // Convert rgba to bits and use it as key
            const key: u96 = @bitCast(clr);
            const gop = try colors_hashmap.getOrPut(key);
            // Increase weight for that color if existing
            if (!gop.found_existing) {
                gop.value_ptr.* = 1;
            } else {
                gop.value_ptr.* += 1;
            }
        }
        // Directly allocate the result slice with precise sizing
        const count: u32 = colors_hashmap.count();
        const values: []PaletteValue = try allocator.*.alloc(PaletteValue, count);
        // Populate the array directly using iterator
        var it = colors_hashmap.iterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) {
            values[i] = .{
                .clr = @as(color.ColorRGB, @bitCast(entry.key_ptr.*)).toHSL(),
                .weight = entry.value_ptr.*,
            };
        }
        return .{ .values = values };
    }

    pub fn deinit(self: *const @This(), allocator: *const std.mem.Allocator) void {
        allocator.*.free(self.values);
    }

    pub fn is_light(self: *const @This()) bool {
        var brightness_sum: f32 = 0;
        var brightness_weights: f32 = 0;
        for (self.values) |*palette_value| {
            brightness_sum += palette_value.clr.l;
            brightness_weights += @floatFromInt(palette_value.weight);
        }
        return (brightness_sum / brightness_weights) > 0.5;
    }
};
