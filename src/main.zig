const std = @import("std");
const builtin = @import("builtin");
const detection = @import("detection.zig").os_module;
const display = @import("display.zig");
const config = @import("config.zig");
const formatters = @import("formatters.zig");
const utils = @import("utils.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const home = try std.process.Environ.getAlloc(init.minimal.environ, allocator, "HOME");
    defer allocator.free(home);

    const config_abs_path = try std.mem.concat(allocator, u8, &.{ home, "/.config/zigfetch/config.json" });
    defer allocator.free(config_abs_path);

    var modules_list = std.array_list.Managed([]u8).init(allocator);
    defer modules_list.deinit();

    errdefer {
        for (modules_list.items) |info| {
            allocator.free(info);
        }
    }

    const conf = try config.readConfigFile(allocator, io, config_abs_path);
    defer if (conf) |c| c.deinit();

    const modules_types = try config.getModulesTypes(allocator, conf);
    defer modules_types.deinit();

    const username = try detection.user.getUsername(allocator, init.minimal.environ);
    const hostname = try detection.system.getHostname(allocator);

    const username_hostname_color = if (config.getUsernameHostnameColor(conf)) |color| blk: {
        var buf: [32]u8 = undefined;
        const rgb = try display.hexColorToRgb(color);
        const formatted_color = try std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b });
        break :blk formatted_color;
    } else display.Yellow;

    try modules_list.append(try formatters.getFormattedUsernameHostname(allocator, username_hostname_color, username, hostname));
    allocator.free(hostname);
    allocator.free(username);

    const separtor_buffer = try allocator.alloc(u8, username.len + hostname.len + 1);
    @memset(separtor_buffer, '-');
    try modules_list.append(separtor_buffer);

    const fmt_ctx = formatters.FormatterContext{
        .gpa = allocator,
        .environ = init.minimal.environ,
        .io = init.io,
    };

    if (modules_types.items.len == 0) {
        inline for (0..formatters.default_formatters.len) |i| {
            const result = try formatters.default_formatters[i](fmt_ctx);
            switch (result) {
                .string => |r| try modules_list.append(r),
                .string_arraylist => |r| {
                    defer r.deinit();
                    try modules_list.appendSlice(r.items);
                },
            }
        }
    } else if (conf) |c| {
        for (modules_types.items, c.value.modules) |module_type, module| {
            var buf: [32]u8 = undefined;
            const rgb = try display.hexColorToRgb(module.key_color);
            const key_color = try std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b });

            const result = try formatters.formatters[@intFromEnum(module_type)](fmt_ctx, module.key, key_color);
            switch (result) {
                .string => |r| try modules_list.append(r),
                .string_arraylist => |r| {
                    defer r.deinit();
                    try modules_list.appendSlice(r.items);
                },
            }
        }
    }

    // If both the `images` and `ascii_abs_path` fields are specified, the images are prioritized
    const config_images = config.getImages(conf);
    if (!utils.supportsKittyProtocol(io) or (config_images == null)) {
        try display.printAsciiAndModules(
            allocator,
            io,
            config.getAsciiPaths(conf),
            modules_list,
        );
    } else if (config_images) |images| {
        if (images.len != 0) {
            try display.printImageAndModules(
                allocator,
                io,
                modules_list,
                images,
            );
        } else {
            return error.NoImagesInTheArray;
        }
    }
}
