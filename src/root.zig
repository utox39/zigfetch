const std = @import("std");

pub const os_module = switch (@import("builtin").os.tag) {
    .linux => @import("linux/linux.zig"),
    .macos => @import("macos/macos.zig"),
    .windows => @import("windows/windows.zig"),
    else => @compileError("Unsupported operating system"),
};
