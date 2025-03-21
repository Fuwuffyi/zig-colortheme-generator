const std = @import("std");
const color = @import("color.zig");

pub const ModulationCurve = struct {
    pub const ColorSpace = enum { rgb, hsl, xyz, lab }; // Enum to identify target space
    curve_values: []const Value,
    color_space: ColorSpace, // Stores which color space to modulate

    pub const Value = struct { a_mod: ?f32, b_mod: ?f32, c_mod: ?f32 };

    pub fn init(color_space: ColorSpace, curve_values: []const Value) ModulationCurve {
        return .{
            .color_space = color_space,
            .curve_values = curve_values,
        };
    }

    pub fn applyCurve(self: *const @This(), allocator: std.mem.Allocator, clr: *const color.Color) ![]color.Color {
        const colors: []color.Color = try allocator.alloc(color.Color, self.curve_values.len);
        // Convert input color to the target color space (e.g., RGB/HSL/XYZ/LAB)
        const converted_color = switch (self.color_space) {
            .rgb => clr.toRGB(),
            .hsl => clr.toHSL(),
            .xyz => clr.toXYZ(),
            .lab => clr.toLAB(),
        };
        // Extract component values as an array (e.g., [r, g, b] for RGB)
        const components: [3]f32 = converted_color.values();
        for (self.curve_values, 0..) |mod_value, i| {
            var modulated_components: [3]f32 = components;
            // Apply modulations to each component based on the curve
            if (mod_value.a_mod) |a| modulated_components[0] *= a;
            if (mod_value.b_mod) |b| modulated_components[1] *= b;
            if (mod_value.c_mod) |c| modulated_components[2] *= c;
            // Reconstruct modulated color in the target space using the union’s tagged value
            colors[i] = switch (self.color_space) {
                .rgb => color.Color{ .rgb = .{
                    .r = modulated_components[0],
                    .g = modulated_components[1],
                    .b = modulated_components[2],
                } },
                .hsl => color.Color{ .hsl = .{
                    .h = modulated_components[0],
                    .s = modulated_components[1],
                    .l = modulated_components[2],
                } },
                .xyz => color.Color{ .xyz = .{
                    .x = modulated_components[0],
                    .y = modulated_components[1],
                    .z = modulated_components[2],
                } },
                .lab => color.Color{ .lab = .{
                    .l = modulated_components[0],
                    .a = modulated_components[1],
                    .b = modulated_components[2],
                } },
            };
        }
        return colors;
    }
};
