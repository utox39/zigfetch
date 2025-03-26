const std = @import("std");
const detection = @import("detection.zig").os_module;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const kernel_info = try detection.system.getKernelInfo(allocator);
    try stdout.print("Kernel: {s} {s}\n", .{ kernel_info.kernel_name, kernel_info.kernel_release });
    try bw.flush();
    allocator.free(kernel_info.kernel_name);
    allocator.free(kernel_info.kernel_release);

    const os_info = try detection.system.getOsInfo(allocator);
    try stdout.print("OS: {s}\n", .{os_info});
    try bw.flush();
    allocator.free(os_info);

    const username = try detection.user.getUsername(allocator);
    try stdout.print("User: {s}\n", .{username});
    try bw.flush();
    allocator.free(username);

    const hostname = try detection.system.getHostname(allocator);
    try stdout.print("Hostname: {s}\n", .{hostname});
    try bw.flush();
    allocator.free(hostname);

    const locale = try detection.system.getLocale(allocator);
    try stdout.print("Locale: {s}\n", .{locale});
    try bw.flush();
    allocator.free(locale);

    const uptime = try detection.system.getSystemUptime();
    try stdout.print("Uptime: {} days, {} hours, {} minutes\n", .{ uptime.days, uptime.hours, uptime.minutes });
    try bw.flush();

    const packages_info = try detection.packages.getPackagesInfo(allocator);
    try stdout.print("packages:{s}\n", .{packages_info});
    try bw.flush();
    allocator.free(packages_info);

    const shell = try detection.user.getShell(allocator);
    try stdout.print("Shell: {s}", .{shell});
    try bw.flush();
    allocator.free(shell);

    const cpu_info = try detection.hardware.getCpuInfo(allocator);
    try stdout.print("cpu: {s} ({}) @ {d:.2} GHz\n", .{ cpu_info.cpu_name, cpu_info.cpu_cores, cpu_info.cpu_max_freq });
    try bw.flush();
    allocator.free(cpu_info.cpu_name);

    const gpu_info = try detection.hardware.getGpuInfo(allocator);
    try stdout.print("gpu: {s} ({}) @ {d:.2} GHz\n", .{ gpu_info.gpu_name, gpu_info.gpu_cores, gpu_info.gpu_freq });
    try bw.flush();
    allocator.free(gpu_info.gpu_name);

    const ram_info = try detection.hardware.getRamInfo();
    try stdout.print("ram: {d:.2} / {d:.2} GB ({}%)\n", .{ ram_info.ram_usage, ram_info.ram_size, ram_info.ram_usage_percentage });
    try bw.flush();

    const swap_info = try detection.hardware.getSwapInfo();
    if (swap_info) |s| {
        try stdout.print("Swap: {d:.2} / {d:.2} GB ({}%)\n", .{ s.swap_usage, s.swap_size, s.swap_usage_percentage });
    } else {
        try stdout.print("Swap: Disabled\n", .{});
    }
    try bw.flush();

    const diskInfo = try detection.hardware.getDiskSize("/");
    try stdout.print("disk ({s}): {d:.2} / {d:.2} GB ({}%)\n", .{ diskInfo.disk_path, diskInfo.disk_usage, diskInfo.disk_size, diskInfo.disk_usage_percentage });
    try bw.flush();

    const terminal_name = try detection.user.getTerminalName(allocator);
    try stdout.print("terminal: {s}\n", .{terminal_name});
    try bw.flush();
    allocator.free(terminal_name);

    const net_info_list = try detection.network.getNetInfo(allocator);
    for (net_info_list.items) |n| {
        try stdout.print("Local IP ({s}): {s}\n", .{ n.interface_name, n.ipv4_addr });
        try bw.flush();
        allocator.free(n.interface_name);
        allocator.free(n.ipv4_addr);
    }
    net_info_list.deinit();
}
