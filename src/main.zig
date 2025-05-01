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

    var buf: [1024]u8 = undefined;

    const username = try detection.user.getUsername(allocator);
    const hostname = try detection.system.getHostname(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "{s}@{s}", .{ username, hostname })));
    allocator.free(hostname);
    allocator.free(username);

    const separtor_buffer = try allocator.alloc(u8, username.len + hostname.len + 1);
    @memset(separtor_buffer, '-');
    try sys_info_list.append(separtor_buffer);

    const kernel_info = try detection.system.getKernelInfo(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try kernel_info.toStr(&buf)));
    allocator.free(kernel_info.kernel_name);
    allocator.free(kernel_info.kernel_release);

    const os_info = try detection.system.getOsInfo(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "OS: {s}", .{os_info})));
    allocator.free(os_info);

    const locale = try detection.system.getLocale(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "Locale: {s}", .{locale})));
    allocator.free(locale);

    const uptime = try detection.system.getSystemUptime();
    try sys_info_list.append(try allocator.dupe(u8, try uptime.toStr(&buf)));

    if (builtin.os.tag == .macos) {
        const packages_info = try detection.packages.getPackagesInfo(allocator);
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "Packages:{s}", .{packages_info})));
        allocator.free(packages_info);
    } else if (builtin.os.tag == .linux) {
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "Packages: WIP", .{})));
    }

    const shell = try detection.user.getShell(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "Shell: {s}", .{shell[0..(shell.len - 1)]})));
    allocator.free(shell);

    const cpu_info = try detection.hardware.getCpuInfo(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try cpu_info.toStr(&buf)));
    allocator.free(cpu_info.cpu_name);

    if (builtin.os.tag == .macos) {
        const gpu_info = try detection.hardware.getGpuInfo(allocator);
        try sys_info_list.append(try allocator.dupe(u8, try gpu_info.toStr(&buf)));
        allocator.free(gpu_info.gpu_name);
    } else if (builtin.os.tag == .linux) {
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "Gpu: WIP", .{})));
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
    try sys_info_list.append(try allocator.dupe(u8, try ram_info.toStr(&buf)));

    const swap_info = if (builtin.os.tag == .macos) try detection.hardware.getSwapInfo() else if (builtin.os.tag == .linux) try detection.hardware.getSwapInfo(allocator);
    if (swap_info) |s| {
        try sys_info_list.append(try allocator.dupe(u8, try s.toStr(&buf)));
    } else {
        try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "Swap: Disabled", .{})));
    }

    const disk_info = try detection.hardware.getDiskSize("/");
    try sys_info_list.append(try allocator.dupe(u8, try disk_info.toStr(&buf)));

    const terminal_name = try detection.user.getTerminalName(allocator);
    try sys_info_list.append(try allocator.dupe(u8, try std.fmt.bufPrint(&buf, "Terminal: {s}", .{terminal_name})));
    allocator.free(terminal_name);

    const net_info_list = try detection.network.getNetInfo(allocator);
    for (net_info_list.items) |n| {
        try sys_info_list.append(try allocator.dupe(u8, try n.toStr(&buf)));
        allocator.free(n.interface_name);
        allocator.free(n.ipv4_addr);
    }
    net_info_list.deinit();

    @memset(&buf, 0);

    try ascii.printAscii(allocator, sys_info_list);
}
