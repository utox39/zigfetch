const builtin = @import("builtin");
const std = @import("std");
const display = @import("display.zig");
const detection = @import("detection.zig").os_module;

const Result = union(enum) {
    string: []u8,
    string_arraylist: std.array_list.Managed([]u8),
};

pub const FormatterContext = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    environ: std.process.Environ,
};

pub const formatters = [_]*const fn (fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) anyerror!Result{
    &getFormattedOsInfo,
    &getFormattedKernelInfo,
    &getFormattedUptimeInfo,
    &getFormattedPackagesInfo,
    &getFormattedShellInfo,
    &getFormattedCpuInfo,
    &getFormattedGpuInfo,
    &getFormattedRamInfo,
    &getFormattedSwapInfo,
    &getFormattedDiskInfo,
    &getFormattedNetInfo,
    &getFormattedWindowManagerInfo,
    &getFormattedTerminalNameInfo,
    &getFormattedLocaleInfo,
    &getFormattedCustom,
};

pub const default_formatters = [_]*const fn (fmt_ctx: FormatterContext) anyerror!Result{
    &getDefaultFormattedOsInfo,
    &getDefaultFormattedKernelInfo,
    &getDefaultFormattedUptimeInfo,
    &getDefaultFormattedPackagesInfo,
    &getDefaultFormattedShellInfo,
    &getDefaultFormattedCpuInfo,
    &getDefaultFormattedGpuInfo,
    &getDefaultFormattedRamInfo,
    &getDefaultFormattedSwapInfo,
    &getDefaultFormattedDiskInfo,
    &getDefaultFormattedNetInfo,
    &getDefaultFormattedWindowManagerInfo,
    &getDefaultFormattedTerminalNameInfo,
    &getDefaultFormattedLocaleInfo,
};

pub fn getFormattedUsernameHostname(gpa: std.mem.Allocator, color: []const u8, username: []const u8, hostname: []const u8) ![]u8 {
    return try std.mem.Allocator.print(gpa, "{s}{s}{s}@{s}{s}{s}", .{
        color,
        username,
        display.Reset,
        color,
        hostname,
        display.Reset,
    });
}

pub fn getDefaultFormattedKernelInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedKernelInfo(fmt_ctx, "Kernel", display.Yellow);
}

pub fn getFormattedKernelInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;

    const kernel_info = try detection.system.getKernelInfo(allocator);
    defer allocator.free(kernel_info.kernel_name);
    defer allocator.free(kernel_info.kernel_release);

    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s} {s}", .{
        key_color,
        key,
        display.Reset,
        kernel_info.kernel_name,
        kernel_info.kernel_release,
    }) };
}

pub fn getDefaultFormattedOsInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedOsInfo(fmt_ctx, "OS", display.Yellow);
}

pub fn getFormattedOsInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const io = fmt_ctx.io;

    const os_info = if (builtin.os.tag == .macos) try detection.system.getOsInfo(allocator) else if (builtin.os.tag == .linux) try detection.system.getOsInfo(allocator, io);
    defer allocator.free(os_info);
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s}", .{
        key_color,
        key,
        display.Reset,
        os_info,
    }) };
}

pub fn getDefaultFormattedLocaleInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedLocaleInfo(fmt_ctx, "Locale", display.Yellow);
}

pub fn getFormattedLocaleInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const environ = fmt_ctx.environ;

    const locale = try detection.system.getLocale(allocator, environ);
    defer allocator.free(locale);
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s}", .{
        key_color,
        key,
        display.Reset,
        locale,
    }) };
}

pub fn getDefaultFormattedUptimeInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedUptimeInfo(fmt_ctx, "Uptime", display.Yellow);
}

pub fn getFormattedUptimeInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const io = fmt_ctx.io;

    const uptime = detection.system.getSystemUptime(io);
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {} days, {} hours, {} minutes", .{
        key_color,
        key,
        display.Reset,
        uptime.days,
        uptime.hours,
        uptime.minutes,
    }) };
}

pub fn getDefaultFormattedPackagesInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedPackagesInfo(fmt_ctx, "Packages", display.Yellow);
}

pub fn getFormattedPackagesInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const io = fmt_ctx.io;
    const environ = fmt_ctx.environ;

    const packages_info = if (builtin.os.tag == .macos) try detection.packages.getPackagesInfo(allocator, io) else if (builtin.os.tag == .linux) try detection.packages.getPackagesInfo(allocator, io, environ);
    defer allocator.free(packages_info);
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s}{s}", .{
        key_color,
        key,
        display.Reset,
        packages_info,
    }) };
}

pub fn getDefaultFormattedShellInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedShellInfo(fmt_ctx, "Shell", display.Yellow);
}

pub fn getFormattedShellInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const io = fmt_ctx.io;
    const environ = fmt_ctx.environ;

    const shell = try detection.user.getShell(allocator, io, environ);
    defer allocator.free(shell);
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s}", .{
        key_color,
        key,
        display.Reset,
        shell[0..(shell.len - 1)],
    }) };
}

pub fn getDefaultFormattedCpuInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedCpuInfo(fmt_ctx, "Cpu", display.Yellow);
}

pub fn getFormattedCpuInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const io = fmt_ctx.io;

    const cpu_info = if (builtin.os.tag == .macos) try detection.hardware.getCpuInfo(allocator) else if (builtin.os.tag == .linux) try detection.hardware.getCpuInfo(allocator, io);
    defer allocator.free(cpu_info.cpu_name);
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s} ({}) @ {d:.2} GHz", .{
        key_color,
        key,
        display.Reset,
        cpu_info.cpu_name,
        cpu_info.cpu_cores,
        cpu_info.cpu_max_freq,
    }) };
}

pub fn getDefaultFormattedGpuInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedGpuInfo(fmt_ctx, "Gpu", display.Yellow);
}

pub fn getFormattedGpuInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;

    if (builtin.os.tag == .macos) {
        const gpu_info = try detection.hardware.getGpuInfo(allocator);
        defer allocator.free(gpu_info.gpu_name);
        return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s} ({}) @ {d:.2} GHz", .{
            key_color,
            key,
            display.Reset,
            gpu_info.gpu_name,
            gpu_info.gpu_cores,
            gpu_info.gpu_freq,
        }) };
    } else if (builtin.os.tag == .linux) {
        var formatted_gpu_info_list = std.array_list.Managed([]u8).init(allocator);

        const gpu_info_list = try detection.hardware.getGpuInfo(allocator);

        for (gpu_info_list.items) |g| {
            var formatted_gpu_info: []u8 = undefined;
            if ((g.gpu_cores == 0) or (g.gpu_freq == 0.0)) {
                formatted_gpu_info = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s}", .{
                    key_color,
                    key,
                    display.Reset,
                    g.gpu_name,
                });
            } else {
                formatted_gpu_info = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s} ({}) @ {d:.2} GHz", .{
                    key_color,
                    key,
                    display.Reset,
                    g.gpu_name,
                    g.gpu_cores,
                    g.gpu_freq,
                });
            }
            try formatted_gpu_info_list.append(formatted_gpu_info);
            allocator.free(g.gpu_name);
        }
        gpu_info_list.deinit();

        return Result{ .string_arraylist = formatted_gpu_info_list };
    }
}

pub fn getDefaultFormattedRamInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedRamInfo(fmt_ctx, "Ram", display.Yellow);
}

pub fn getFormattedRamInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const io = fmt_ctx.io;

    const ram_info = if (builtin.os.tag == .macos) try detection.hardware.getRamInfo() else if (builtin.os.tag == .linux) try detection.hardware.getRamInfo(allocator, io);
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {d:.2} / {d:.2} GiB ({}%)", .{
        key_color,
        key,
        display.Reset,
        ram_info.ram_usage,
        ram_info.ram_size,
        ram_info.ram_usage_percentage,
    }) };
}

pub fn getDefaultFormattedSwapInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedSwapInfo(fmt_ctx, "Swap", display.Yellow);
}

pub fn getFormattedSwapInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const io = fmt_ctx.io;

    const swap_info = if (builtin.os.tag == .macos) try detection.hardware.getSwapInfo() else if (builtin.os.tag == .linux) try detection.hardware.getSwapInfo(allocator, io);
    if (swap_info) |s| {
        return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {d:.2} / {d:.2} GiB ({}%)", .{
            key_color,
            key,
            display.Reset,
            s.swap_usage,
            s.swap_size,
            s.swap_usage_percentage,
        }) };
    } else {
        return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} Disabled", .{ key_color, key, display.Reset }) };
    }
}

pub fn getDefaultFormattedDiskInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedDiskInfo(fmt_ctx, "Disk", display.Yellow);
}

pub fn getFormattedDiskInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;

    const disk_info = try detection.hardware.getDiskSize("/");
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s} ({s}):{s} {d:.2} / {d:.2} GB ({}%)", .{
        key_color,
        key,
        disk_info.disk_path,
        display.Reset,
        disk_info.disk_usage,
        disk_info.disk_size,
        disk_info.disk_usage_percentage,
    }) };
}

pub fn getDefaultFormattedWindowManagerInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedWindowManagerInfo(fmt_ctx, "WM", display.Yellow);
}

pub fn getFormattedWindowManagerInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const io = fmt_ctx.io;

    const wm = if (builtin.os.tag == .macos) try detection.system.getWindowManagerInfo(allocator) else if (builtin.os.tag == .linux) try detection.system.getWindowManagerInfo(allocator, io);
    defer allocator.free(wm);
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s}", .{ key_color, key, display.Reset, wm }) };
}

pub fn getDefaultFormattedTerminalNameInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedTerminalNameInfo(fmt_ctx, "Terminal", display.Yellow);
}

pub fn getFormattedTerminalNameInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;
    const environ = fmt_ctx.environ;

    const terminal_name = try detection.user.getTerminalName(allocator, environ);
    defer allocator.free(terminal_name);
    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}:{s} {s}", .{ key_color, key, display.Reset, terminal_name }) };
}

pub fn getDefaultFormattedNetInfo(fmt_ctx: FormatterContext) !Result {
    return try getFormattedNetInfo(fmt_ctx, "Local IP", display.Yellow);
}

pub fn getFormattedNetInfo(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;

    var formatted_net_info_list = std.array_list.Managed([]u8).init(allocator);

    var net_info_list = try detection.network.getNetInfo(allocator);
    for (net_info_list.items) |n| {
        try formatted_net_info_list.append(try std.mem.Allocator.print(allocator, "{s}{s} ({s}):{s} {s}", .{
            key_color,
            key,
            n.interface_name,
            display.Reset,
            n.ipv4_addr,
        }));
        allocator.free(n.interface_name);
        allocator.free(n.ipv4_addr);
    }
    net_info_list.deinit();

    return Result{ .string_arraylist = formatted_net_info_list };
}

pub fn getFormattedCustom(fmt_ctx: FormatterContext, key: []const u8, key_color: []const u8) !Result {
    const allocator = fmt_ctx.gpa;

    return Result{ .string = try std.mem.Allocator.print(allocator, "{s}{s}{s}", .{ key_color, key, display.Reset }) };
}
