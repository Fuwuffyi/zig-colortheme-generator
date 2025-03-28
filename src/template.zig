const std = @import("std");
const builtin = @import("builtin");
const color = @import("color.zig");

pub const TemplateValue = struct {
    primary_color: color.Color,
    text_color: color.Color,
    accent_colors: []const color.Color
};

pub fn applyTemplate(template_path: []const u8, out_path: []const u8, colors: []const TemplateValue, command: ?[]const u8, allocator: std.mem.Allocator) !void {
    // Grab the configuration file
    const template_file: std.fs.File = try std.fs.openFileAbsolute(template_path, .{});
    defer template_file.close();
    // Read the contents of the configuration file
    const template_contents: []const u8 = try template_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(template_contents);
    // Process the template contents to replace placeholders
    var buffer: std.ArrayList(u8) = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var pos: usize = 0;
    // Process each placeholder sequentially
    while (findNextPlaceholderStart(template_contents, pos)) |start| {
        const end: usize = findPlaceholderEnd(template_contents, start + 2) orelse return error.UnterminatedPlaceholder;
        // Append content before the placeholder
        try buffer.appendSlice(template_contents[pos..start]);
        // Extract and process placeholder (e.g., "color0.pri.r")
        const placeholder_content: []const u8 = std.mem.trim(u8, template_contents[start + 2 .. end], &std.ascii.whitespace);
        const replacement: []const u8 = try processPlaceholder(placeholder_content, colors, allocator);
        defer allocator.free(replacement);
        try buffer.appendSlice(replacement);
        // Advance past the closing "}}"
        pos = end + 2;
    }
    // Append remaining content after last placeholder
    try buffer.appendSlice(template_contents[pos..]);
    const processed_contents: []const u8 = try buffer.toOwnedSlice();
    defer allocator.free(processed_contents);
    // Write the processed data to the out file
    const out_file: std.fs.File = try openOrCreateFile(out_path);
    defer out_file.close();
    try out_file.writeAll(processed_contents);
    // Run the command after applying the template and colors
    if (command) |cmd| {
        try runCommand(allocator, cmd);
    }
}

fn openOrCreateFile(path: []const u8) !std.fs.File {
    const existing_file: std.fs.File = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => return try std.fs.createFileAbsolute(path, .{}),
        else => return err,
    };
    return existing_file;
}

fn findNextPlaceholderStart(content: []const u8, start_pos: usize) ?usize {
    return std.mem.indexOfPos(u8, content, start_pos, "{{");
}

fn findPlaceholderEnd(content: []const u8, start_pos: usize) ?usize {
    return std.mem.indexOfPos(u8, content, start_pos, "}}");
}

fn processPlaceholder(placeholder: []const u8, colors: []const TemplateValue, allocator: std.mem.Allocator) ![]const u8 {
    var parts = std.mem.splitScalar(u8, placeholder, '.');
    const color_spec: []const u8 = parts.first();
    const color_index: usize = try parseColorIndex(color_spec, colors.len);
    const color_type: []const u8 = parts.next() orelse return error.InvalidPlaceholderFormat;
    const color_value: *const color.Color = try extractColorValue(color_type, &colors[color_index]);
    const property: []const u8 = parts.next() orelse return error.InvalidPlaceholderFormat;
    if (parts.next() != null) return error.InvalidPlaceholderFormat; // Too many parts
    return try formatColorProperty(color_value, property, allocator);
}

// Extracts color index from strings like "color3"
fn parseColorIndex(color_spec: []const u8, max_colors: usize) !usize {
    if (!std.mem.startsWith(u8, color_spec, "color")) return error.InvalidColorSpec;
    const index_str: []const u8 = color_spec["color".len..];
    const index: usize = std.fmt.parseInt(usize, index_str, std.math.maxInt(usize)) catch return error.InvalidColorIndex;
    if (index >= max_colors) return error.ColorIndexOutOfBounds;
    return index;
}

fn extractColorValue(color_type: []const u8, template_value: *const TemplateValue) !*const color.Color {
    if (std.mem.eql(u8, color_type, "pri")) {
        return &template_value.primary_color;
    } else if (std.mem.eql(u8, color_type, "txt")) {
        return &template_value.text_color;
    } else if (std.mem.startsWith(u8, color_type, "acc")) {
        const index_str: []const u8 = color_type["acc".len..];
        const index: usize = std.fmt.parseInt(usize, index_str, std.math.maxInt(usize)) catch return error.InvalidAccentIndex;
        if (index >= template_value.accent_colors.len) return error.AccentIndexOutOfBounds;
        return &template_value.accent_colors[index];
    } else {
        return error.UnknownColorType;
    }
}

fn formatColorProperty(color_value: *const color.Color, property: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const values: [3]f32 = color_value.values();
    const value_bytes: [3]u8 = .{ 
        @as(u8, @intFromFloat(values[0] * 255)),
        @as(u8, @intFromFloat(values[1] * 255)),
        @as(u8, @intFromFloat(values[2] * 255)),
    };
    if (std.mem.eql(u8, property, "r")) {
        return try std.fmt.allocPrint(allocator, "{d}", .{value_bytes[0]});
    } else if (std.mem.eql(u8, property, "g")) {
        return try std.fmt.allocPrint(allocator, "{d}", .{value_bytes[1]});
    } else if (std.mem.eql(u8, property, "b")) {
        return try std.fmt.allocPrint(allocator, "{d}", .{value_bytes[2]});
    } else if (std.mem.eql(u8, property, "rh")) {
        return try std.fmt.allocPrint(allocator, "{x:0>2}", .{value_bytes[0]});
    } else if (std.mem.eql(u8, property, "gh")) {
        return try std.fmt.allocPrint(allocator, "{x:0>2}", .{value_bytes[1]});
    } else if (std.mem.eql(u8, property, "bh")) {
        return try std.fmt.allocPrint(allocator, "{x:0>2}", .{value_bytes[2]});
    } else if (std.mem.eql(u8, property, "rgb")) {
        return try std.fmt.allocPrint(allocator, "{d}, {d}, {d}", .{value_bytes[0], value_bytes[1], value_bytes[2]});
    } else if (std.mem.eql(u8, property, "hex")) {
        return try std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}", .{value_bytes[0], value_bytes[1], value_bytes[2]});
    } else {
        return error.InvalidColorProperty;
    }
}

fn executeCommand(allocator: std.mem.Allocator, command: []const u8) !struct {stdout: []u8, stderr: []u8, term: std.process.Child.Term} {
    // Handle shell execution for string commands
    const shell_cmd: []const []const u8 = if (builtin.target.os.tag == .windows)
            &[_][]const u8{"cmd.exe", "/C", command} else
            &[_][]const u8{"/bin/sh", "-c", command};
    const argv: []const []const u8 = shell_cmd;
    var child: std.process.Child = std.process.Child.init(argv, allocator);
    // Capture output
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    // Read output streams
    const stdout = try child.stdout.?.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(stdout);
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(stderr);
    const term = try child.wait();
    return .{
        .stdout = stdout,
        .stderr = stderr,
        .term = term,
    };
}

fn runCommand(allocator: std.mem.Allocator, command: []const u8) !void {
    const result = try executeCommand(allocator, command);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.stdout.len > 0) {
        std.debug.print("{s}\n", .{result.stdout});
    }
    if (result.stderr.len > 0) {
        std.debug.print("ERROR: {s}\n", .{result.stderr});
    }
    switch (result.term) {
        .Exited => |code| if (code != 0) {
            return error.CommandFailed;
        },
        else => return error.CommandFailed,
    }
}
