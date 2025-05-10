const std = @import("std");
const builtin = @import("builtin");
const detection = @import("detection.zig").os_module;
const ascii = @import("ascii.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var sys_info_list = std.ArrayList([]u8).init(allocator);
    defer sys_info_list.deinit();

    var buf1: [1024]u8 = undefined;
    var buf2: [1024]u8 = undefined;

    const username = try detection.user.getUsername(allocator);
    const hostname = try detection.system.getHostname(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}{s}{s}@{s}{s}{s}", .{
        ascii.Yellow,
        username,
        ascii.Reset,
        ascii.Magenta,
        hostname,
        ascii.Reset,
    })));
    allocator.free(hostname);
    allocator.free(username);

    const separtor_buffer = try allocator.alloc(u8, username.len + hostname.len + 1);
    @memset(separtor_buffer, '-');
    try sys_info_list.append(separtor_buffer);

    const kernel_info = try detection.system.getKernelInfo(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Kernel:{s} {s}", .{ ascii.Yellow, ascii.Reset, try kernel_info.toStr(&buf2) })));
    allocator.free(kernel_info.kernel_name);
    allocator.free(kernel_info.kernel_release);

    const os_info = try detection.system.getOsInfo(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}OS:{s} {s}", .{ ascii.Yellow, ascii.Reset, os_info })));
    allocator.free(os_info);

    const locale = try detection.system.getLocale(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Locale:{s} {s}", .{ ascii.Yellow, ascii.Reset, locale })));
    allocator.free(locale);

    const uptime = try detection.system.getSystemUptime();
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Uptime:{s} {s}", .{ ascii.Yellow, ascii.Reset, try uptime.toStr(&buf2) })));

    if (builtin.os.tag == .macos) {
        const packages_info = try detection.packages.getPackagesInfo(allocator);
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Packages:{s}{s}", .{ ascii.Yellow, ascii.Reset, packages_info })));
        allocator.free(packages_info);
    } else if (builtin.os.tag == .linux) {
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Packages:{s} WIP", .{ ascii.Yellow, ascii.Reset })));
    }

    const shell = try detection.user.getShell(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Shell:{s} {s}", .{ ascii.Yellow, ascii.Reset, shell[0..(shell.len - 1)] })));
    allocator.free(shell);

    const cpu_info = try detection.hardware.getCpuInfo(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Cpu:{s} {s}", .{ ascii.Yellow, ascii.Reset, try cpu_info.toStr(&buf2) })));
    allocator.free(cpu_info.cpu_name);

    if (builtin.os.tag == .macos) {
        const gpu_info = try detection.hardware.getGpuInfo(allocator);
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Gpu:{s} {s}", .{ ascii.Yellow, ascii.Reset, try gpu_info.toStr(&buf2) })));
        allocator.free(gpu_info.gpu_name);
    } else if (builtin.os.tag == .linux) {
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Gpu:{s} WIP", .{ ascii.Yellow, ascii.Reset })));
    }

    var ram_info = detection.hardware.RamInfo{
        .ram_size = 0.0,
        .ram_usage = 0.0,
        .ram_usage_percentage = 0,
    };
    if (builtin.os.tag == .macos) {
        ram_info = try detection.hardware.getRamInfo();
    } else if (builtin.os.tag == .linux) {
        ram_info = try detection.hardware.getRamInfo(allocator);
    }
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Ram:{s} {s}", .{ ascii.Yellow, ascii.Reset, try ram_info.toStr(&buf2) })));

    const swap_info = if (builtin.os.tag == .macos) try detection.hardware.getSwapInfo() else if (builtin.os.tag == .linux) try detection.hardware.getSwapInfo(allocator);
    if (swap_info) |s| {
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Swap:{s} {s}", .{ ascii.Yellow, ascii.Reset, try s.toStr(&buf2) })));
    } else {
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Swap:{s} Disabled", .{ ascii.Yellow, ascii.Reset })));
    }

    const disk_info = try detection.hardware.getDiskSize("/");
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Disk{s} {s}", .{ ascii.Yellow, ascii.Reset, try disk_info.toStr(&buf2) })));

    const terminal_name = try detection.user.getTerminalName(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Terminal:{s} {s}", .{ ascii.Yellow, ascii.Reset, terminal_name })));
    allocator.free(terminal_name);

    const net_info_list = try detection.network.getNetInfo(allocator);
    for (net_info_list.items) |n| {
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf1, "{s}Local IP {s}{s}", .{ ascii.Yellow, ascii.Reset, try n.toStr(&buf2) })));
        allocator.free(n.interface_name);
        allocator.free(n.ipv4_addr);
    }
    net_info_list.deinit();

    @memset(&buf1, 0);
    @memset(&buf2, 0);

    try ascii.printAscii(allocator, sys_info_list);
}
