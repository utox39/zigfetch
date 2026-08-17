const std = @import("std");
const config = @import("./config.zig");
const utils = @import("./utils.zig");

pub const Reset = "\x1b[0m";
pub const Bold = "\x1b[1m";
pub const Red = "\x1b[31m";
pub const Green = "\x1b[32m";
pub const Yellow = "\x1b[33m";
pub const Blue = "\x1b[34m";
pub const Magenta = "\x1b[35m";
pub const Cyan = "\x1b[36m";
pub const White = "\x1b[37m";

pub fn selectAscii() void {}

inline fn parseHexChar(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidHexChar,
    };
}

fn parseHexByte(s: []const u8) !u8 {
    if (s.len != 2) return error.InvalidHexByteLength;

    const hi = try parseHexChar(s[0]);
    const lo = try parseHexChar(s[1]);

    // Example: ff
    // hi = 0b00001111 (15)
    // lo = 0b00001111 (15)
    //
    // hi << 4 -> 0b11110000 (240)
    //
    // (hi << 4) | lo -> 0b11110000 | 0b00001111
    // => 0b11111111 (255)

    return (hi << 4) | lo;
}

/// Converts a hex color to rgb
pub fn hexColorToRgb(color: []const u8) !struct { r: u8, g: u8, b: u8 } {
    if (color.len < 6 or color.len > 7) return error.InvalidHexColorLength;

    var start: usize = 0;

    if (color[0] == '#') start = 1;

    return .{
        .r = try parseHexByte(color[start .. start + 2]),
        .g = try parseHexByte(color[start + 2 .. start + 4]),
        .b = try parseHexByte(color[start + 4 ..]),
    };
}

test "parse #ffffff" {
    const result = try hexColorToRgb("#ffffff");
    try std.testing.expect((result.r == 255) and (result.g == 255) and (result.b == 255));
}

test "parse ffffff" {
    const result = try hexColorToRgb("ffffff");
    try std.testing.expect((result.r == 255) and (result.g == 255) and (result.b == 255));
}

/// Displays an image next to system info using the Kitty terminal graphics protocol.
///
/// If the user spicifies multiple images in the config file, one will be selected
/// pseudo-randomly.
///
/// The image is transmitted as raw PNG data (f=100) in 4096-byte base64 chunks.
/// `image_cols` controls the image width in terminal columns; height is derived from
/// the sys_info list so the image and info are the same number of rows.
///
/// Falls back silently if the image file cannot be displayed (e.g. non-kitty terminal).
pub fn printImageAndModules(gpa: std.mem.Allocator, io: std.Io, sys_info_list: std.array_list.Managed([]u8), images: []const config.Image) !void {
    var image: config.Image = undefined;
    if (images.len > 1) {
        // Choose a random image
        var seed: u64 = undefined;
        io.random(std.mem.asBytes(&seed));
        var prng = std.Random.DefaultPrng.init(seed);
        image = images[prng.random().uintLessThan(usize, images.len)];
    } else {
        image = images[0];
    }

    // Check if the image is a png.
    // Reading the file twice might seem like an overhead, but this function reads
    // only 8 bytes and saves resources if the file isn't a PNG.
    if (!(try utils.isFilePng(gpa, io, image.abs_path))) return error.ImageIsNotPng;

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    const sys_info_items = sys_info_list.items;
    const sys_info_len: usize = sys_info_items.len;

    // Make the image exactly as tall as the output (sys_info rows + 1 blank + 2 color rows) if the user
    // has not specified it.
    const image_rows: u8 = image.height orelse @intCast(sys_info_len + 3);

    // NOTE: After doing some testing, I think 35 is a good compromise for the default image columns
    const image_cols: u8 = image.width orelse 35;

    const spacing: usize = 3;
    const terminal_size = utils.getTerminalSize() catch utils.TermSize{ .height = 50, .width = 50 };
    const terminal_width: usize = @intCast(terminal_size.width);

    const longest_sys_info_string_len = utils.getLongestSysInfoStringLen(sys_info_items);

    const can_print_image: bool = terminal_width > image_cols + longest_sys_info_string_len + spacing;

    // Print the image if the width of the terminal is greater than the image columns + the longest sys info string length + the spacing (3)
    if (can_print_image) {
        const image_file = try std.Io.Dir.openFileAbsolute(io, image.abs_path, .{ .mode = .read_only });
        defer image_file.close(io);
        const file_size = (try image_file.stat(io)).size;
        const image_data = try utils.readFile(gpa, io, image_file, file_size);
        defer gpa.free(image_data);

        const base64_encoder = std.base64.standard.Encoder;
        const base64_len = base64_encoder.calcSize(image_data.len);
        const base64_data = try gpa.alloc(u8, base64_len);
        defer gpa.free(base64_data);
        _ = base64_encoder.encode(base64_data, image_data);

        // Transmit image via Kitty graphics protocol.
        //   a=T  – transmit and display immediately
        //   f=100 – payload is raw PNG (no decode needed)
        //   c, r  – size in terminal columns / rows
        //   q=2  – suppress terminal acknowledgement responses
        //   m=1  – more chunks follow; m=0 on the last chunk
        const chunk_size: usize = 4096;
        var offset: usize = 0;
        var first_chunk = true;

        try stdout.print("\n", .{});
        try stdout.flush();

        while (offset < base64_data.len) {
            const end = @min(offset + chunk_size, base64_data.len);
            const chunk = base64_data[offset..end];
            const more: u8 = if (end < base64_data.len) 1 else 0;

            if (first_chunk) {
                try stdout.print(
                    "\x1b_Ga=T,f=100,c={d},r={d},q=2,m={d};{s}\x1b\\",
                    .{ image_cols, image_rows, more, chunk },
                );
                first_chunk = false;
            } else {
                try stdout.print("\x1b_Gm={d};{s}\x1b\\", .{ more, chunk });
            }
            try stdout.flush();

            offset = end;
        }

        // NOTE: After transmission the cursor sits at the first column of the row "after" the image.
        // Move back up to the first image row so we can print sys_info alongside it.
        try stdout.print("\x1b[{d}A", .{image_rows});
        try stdout.flush();
    }

    var i: usize = 0;
    while (i < image_rows) : (i += 1) {
        // \r resets to column 0 (cursor-up preserves the column, so the first row
        // would otherwise inherit whatever column the image transmission left behind).
        if (can_print_image) {
            try stdout.print("\r\x1b[{d}C", .{image_cols + spacing});
        }

        if (i < sys_info_len) {
            try stdout.print("{s}\n", .{sys_info_items[i]});
        } else if (i == sys_info_len + 1) {
            // Print the first row of colors
            for (0..8) |j| {
                try stdout.print("\x1b[48;5;{d}m  \x1b[0m", .{j});
            }
            try stdout.print("\n", .{});
        } else if (i == sys_info_len + 2) {
            // Print the second row of colors
            for (8..16) |j| {
                try stdout.print("\x1b[48;5;{d}m  \x1b[0m", .{j});
            }
            try stdout.print("\n", .{});
        } else {
            try stdout.print("\n", .{});
        }
        try stdout.flush();
    }

    try stdout.print("\n", .{});
    try stdout.flush();

    for (sys_info_list.items) |item| {
        gpa.free(item);
    }
}

pub fn printAsciiAndModules(gpa: std.mem.Allocator, io: std.Io, ascii_art_paths: ?[][]const u8, sys_info_list: std.array_list.Managed([]u8)) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var ascii_art_data: []const u8 = undefined;
    if (ascii_art_paths) |ascii_paths| {
        var ascii_art_path: []const u8 = undefined;
        if (ascii_paths.len > 1) {
            // Choose a random Ascii art
            var seed: u64 = undefined;
            io.random(std.mem.asBytes(&seed));
            var prng = std.Random.DefaultPrng.init(seed);
            ascii_art_path = ascii_paths[prng.random().uintLessThan(usize, ascii_paths.len)];
        } else {
            ascii_art_path = ascii_paths[0];
        }

        const ascii_file = try std.Io.Dir.cwd().openFile(io, ascii_art_path, .{ .mode = .read_only });
        defer ascii_file.close(io);
        const file_size = (try ascii_file.stat(io)).size;
        ascii_art_data = try utils.readFile(gpa, io, ascii_file, file_size);
    } else {
        ascii_art_data = @embedFile("./assets/ascii/guy_fawks.txt");
    }

    defer if (ascii_art_paths != null) {
        gpa.free(ascii_art_data);
    };

    var lines = std.mem.splitScalar(u8, ascii_art_data, '\n');

    var ascii_art_content_list = std.array_list.Managed([]const u8).init(gpa);
    defer ascii_art_content_list.deinit();

    while (lines.next()) |line| {
        try ascii_art_content_list.append(line);
    }

    const ascii_art_items = ascii_art_content_list.items;
    const sys_info_items = sys_info_list.items;

    const terminal_size = utils.getTerminalSize() catch utils.TermSize{ .height = 50, .width = 50 };
    const terminal_width: usize = @intCast(terminal_size.width);

    const spacing: usize = 5;

    const longest_ascii_art_row_len: usize = try utils.getLongestAsciiArtRowLen(ascii_art_items);
    const longest_sys_info_string_len = utils.getLongestSysInfoStringLen(sys_info_items);

    const can_print_ascii_art: bool = terminal_width > longest_ascii_art_row_len + longest_sys_info_string_len + spacing;

    const ascii_art_rows: usize = ascii_art_items.len;
    const sys_info_len: usize = sys_info_items.len;

    // NOTE: sys_info_len + 3 to be able to print the colors
    const max_len: usize = if ((ascii_art_rows > sys_info_len) and can_print_ascii_art) ascii_art_rows else sys_info_len + 3;

    var i: usize = 0;
    while (i < max_len) : (i += 1) {
        // Print the ascii art if the width of the terminal is greater than the spacing (5) + the longest ascii art row length + the longest sys info string length
        if (can_print_ascii_art) {
            const alignment_buffer = try gpa.alloc(u8, if (i < ascii_art_rows) longest_ascii_art_row_len - (try utils.countCodepoints(ascii_art_items[i])) + spacing else longest_ascii_art_row_len + spacing);
            @memset(alignment_buffer, ' ');

            if (i < ascii_art_rows) {
                try stdout.print("{s}{s}", .{ ascii_art_items[i], alignment_buffer });
            } else {
                try stdout.print("{s}", .{alignment_buffer});
            }

            gpa.free(alignment_buffer);

            try stdout.flush();
        }

        if (i < sys_info_len) {
            try stdout.print("{s}\n", .{sys_info_items[i]});
        } else if (i == sys_info_len + 1) {
            // Print the first row of colors
            for (0..8) |j| {
                try stdout.print("\x1b[48;5;{d}m  \x1b[0m", .{j});
            }
            try stdout.print("\n", .{});
        } else if (i == sys_info_len + 2) {
            // Print the second row of colors
            for (8..16) |j| {
                try stdout.print("\x1b[48;5;{d}m  \x1b[0m", .{j});
            }
            try stdout.print("\n", .{});
        } else {
            try stdout.print("\n", .{});
        }
        try stdout.flush();
    }

    for (sys_info_list.items) |item| {
        gpa.free(item);
    }
}
