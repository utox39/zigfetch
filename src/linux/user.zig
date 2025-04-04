const std = @import("std");

pub fn getUsername(allocator: std.mem.Allocator) ![]u8 {
    const username = try std.process.getEnvVarOwned(allocator, "USER");
    return username;
}

pub fn getShell(allocator: std.mem.Allocator) ![]u8 {
    const shell = try std.process.getEnvVarOwned(allocator, "SHELL");

    var child = std.process.Child.init(&[_][]const u8{ shell, "--version" }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const output = try child.stdout.?.reader().readAllAlloc(allocator, 1024 * 1024);

    _ = try child.wait();

    return output;
}

pub fn getTerminalName(allocator: std.mem.Allocator) ![]u8 {
    const term_progrm = std.process.getEnvVarOwned(allocator, "TERM_PROGRAM") catch |err| if (err == error.EnvironmentVariableNotFound) {
        return allocator.dupe(u8, "Unknown");
    } else return err;
    return term_progrm;
}
