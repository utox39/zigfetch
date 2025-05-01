const std = @import("std");

pub fn selectAscii() void {}

pub fn printAscii(allocator: std.mem.Allocator, sys_info_list: std.ArrayList([]u8)) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    // const ascii_art_path = "./assets/ascii/guy_fawks.txt";
    // var file = try std.fs.cwd().openFile(ascii_art_path, .{});
    // defer file.close();
    // const ascii_art_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    // defer allocator.free(ascii_art_data);

    const ascii_art_data = @embedFile("./assets/ascii/guy_fawks.txt");

    var lines = std.mem.splitScalar(u8, ascii_art_data, '\n');

    var ascii_art_content_list = std.ArrayList([]const u8).init(allocator);
    defer ascii_art_content_list.deinit();

    while (lines.next()) |line| {
        try ascii_art_content_list.append(line);
    }

    const ascii_art_items = ascii_art_content_list.items;
    const sys_info_items = sys_info_list.items;

    const ascii_art_len: usize = ascii_art_items.len;
    const sys_info_len: usize = sys_info_items.len;
    const max_len: usize = if (ascii_art_len > sys_info_len) ascii_art_len else sys_info_len;

    var i: usize = 0;
    while (i < max_len) : (i += 1) {
        if (i < ascii_art_len) {
            try stdout.print("{s:<40} \t", .{ascii_art_items[i]});
        } else {
            try stdout.print("{s:<40}", .{""});
        }
        try bw.flush();

        if (i < sys_info_len) {
            try stdout.print("{s}\n", .{sys_info_items[i]});
        } else {
            try stdout.print("\n", .{});
        }
        try bw.flush();
    }

    for (sys_info_list.items) |item| {
        allocator.free(item);
    }
}
