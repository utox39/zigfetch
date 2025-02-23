const std = @import("std");

pub fn getUsername(allocator: std.mem.Allocator) ![]u8 {
    const username = try std.process.getEnvVarOwned(allocator, "USERNAME");
    return username;
}
