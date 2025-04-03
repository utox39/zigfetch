const std = @import("std");

// TODO: (2) WIP

// pub fn getUsername(allocator: std.mem.Allocator) ![]u8 {
//     const username = try std.process.getEnvVarOwned(allocator, "USERNAME");
//     return username;
// }

// pub fn getHostname(allocator: std.mem.Allocator) ![]u8 {
//     var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
//     const hostnameEnv = try std.posix.gethostname(&buf);

//     const hostname = try allocator.dupe(u8, hostnameEnv);

//     return hostname;
// }
