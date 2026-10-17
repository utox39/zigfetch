const std = @import("std");

pub const os_module = switch (@import("builtin").target.os.tag) {
    .linux => @import("linux/linux.zig"),
    .macos => @import("macos/macos.zig"),
    .windows => @compileError("Windows: WIP"),
    else => @compileError("Unsupported operating system"),
};
