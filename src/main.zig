const std = @import("std");
const os_module = @import("root.zig").os_module;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const username = try os_module.getUsername(allocator);

    try stdout.print("User: {s}\n", .{username});
    try bw.flush();
}
