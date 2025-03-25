const std = @import("std");
const utils = @import("utils.zig");

pub fn getPackagesInfo(allocator: std.mem.Allocator) ![]const u8 {
    var packages_info = std.ArrayList(u8).init(allocator);
    defer packages_info.deinit();

    const homebrew_packages = try countHomebrewPackages();
    const homebrew_casks = try countHomebrewCasks();

    var buffer: [10]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    if (homebrew_packages > 0) {
        try std.fmt.formatInt(homebrew_packages, 10, .lower, .{}, fbs.writer());
        try packages_info.appendSlice("brew: ");
        try packages_info.appendSlice(fbs.getWritten());
    }

    if (homebrew_casks > 0) {
        fbs.reset();
        try std.fmt.formatInt(homebrew_casks, 10, .lower, .{}, fbs.writer());
        try packages_info.appendSlice(" brew-cask: ");
        try packages_info.appendSlice(fbs.getWritten());
    }

    return try allocator.dupe(u8, packages_info.items);
}

fn countHomebrewPackages() !usize {
    return try utils.countEntries("/opt/homebrew/Cellar");
}

fn countHomebrewCasks() !usize {
    return try utils.countEntries("/opt/homebrew/Caskroom");
}
