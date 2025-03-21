const std = @import("std");
const palette = @import("palette.zig");
const color = @import("color.zig");

const iter_threshold: comptime_float = 1e-6;

pub fn kmeans(allocator: std.mem.Allocator, pal: *const palette.Palette, k: u32, iters: u32) ![]color.Color {
    var random_generator: std.Random.Xoshiro256 = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const random: std.Random = random_generator.random();
    // Error checking
    const k_usize: usize = @intCast(k);
    if (pal.values.len == 0) return error.EmptyPalette;
    if (k_usize == 0) return error.InvalidK;
    // Generate "random" centroids
    const centroids: []color.Color = try allocator.alloc(color.Color, k_usize);
    errdefer allocator.free(centroids);
    for (centroids) |*centroid| {
        centroid.* = pal.values[@mod(random.int(usize), pal.values.len)].clr;
    }
    const color_space: std.meta.Tag(color.Color) = std.meta.activeTag(centroids[0]);
    // Preallocate accumulators
    var sum_a: []f32 = try allocator.alloc(f32, k_usize);
    defer allocator.free(sum_a);
    var sum_b: []f32 = try allocator.alloc(f32, k_usize);
    defer allocator.free(sum_b);
    var sum_c: []f32 = try allocator.alloc(f32, k_usize);
    defer allocator.free(sum_c);
    var total_weight: []f32 = try allocator.alloc(f32, k_usize);
    defer allocator.free(total_weight);
    // Create array to store the cluster the color appartains to
    for (0..iters) |_| {
        // Reset accumulators
        @memset(sum_a, 0.0);
        @memset(sum_b, 0.0);
        @memset(sum_c, 0.0);
        @memset(total_weight, 0.0);
        // Loop through palette
        for (pal.values) |value| {
            // Update cluster values based on closest one to cluster center
            var best_idx: usize = 0;
            var min_dist: f32 = std.math.floatMax(f32);
            const weight: f32 = @as(f32, @floatFromInt(value.weight));
            for (centroids, 0..) |*centroid, idx| {
                const dist_sq: f32 = value.clr.dst(centroid);
                const weighted_dist: f32 = weight * dist_sq;
                if (weighted_dist < min_dist) {
                    min_dist = weighted_dist;
                    best_idx = idx;
                }
            }
            // Increase accumulators
            const color_values: [3]f32 = value.clr.values();
            sum_a[best_idx] += color_values[0] * weight;
            sum_b[best_idx] += color_values[1] * weight;
            sum_c[best_idx] += color_values[2] * weight;
            total_weight[best_idx] += weight;
        }
        // Update centroids
        var threshold_exit: bool = true;
        for (centroids, 0..) |*centroid, i| {
            const tw: f32 = total_weight[i];
            if (tw == 0) continue;
            const new_vals: [3]f32 = .{
                sum_a[i] / tw,
                sum_b[i] / tw,
                sum_c[i] / tw,
            };
            const old_col: color.Color = centroid.*;
            centroid.* = switch (color_space) {
                .rgb => .{ .rgb = .{ .r = new_vals[0], .g = new_vals[1], .b = new_vals[2] } },
                .hsl => .{ .hsl = .{ .h = new_vals[0], .s = new_vals[1], .l = new_vals[2] } },
                .xyz => .{ .xyz = .{ .x = new_vals[0], .y = new_vals[1], .z = new_vals[2] } },
                .lab => .{ .lab = .{ .l = new_vals[0], .a = new_vals[1], .b = new_vals[2] } },
            };
            // Check for threshold for early exit
            if (old_col.dst(centroid) > iter_threshold) {
                threshold_exit = false;
            }
        }
        // Early exit when threshold met
        if (threshold_exit) {
            break;
        }
    }
    return centroids;
}
