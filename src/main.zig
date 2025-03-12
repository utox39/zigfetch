const std = @import("std");
const os_module = @import("root.zig").os_module;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const os_info = try os_module.getOsInfo(allocator);
    try stdout.print("OS: {s}\n", .{os_info});
    try bw.flush();
    allocator.free(os_info);

    const username = try os_module.getUsername(allocator);
    try stdout.print("User: {s}\n", .{username});
    try bw.flush();
    allocator.free(username);

    const hostname = try os_module.getHostname(allocator);
    try stdout.print("Hostname: {s}\n", .{hostname});
    try bw.flush();
    allocator.free(hostname);

    const uptime = try os_module.getSystemUptime();
    try stdout.print("Uptime: {} days, {} hours, {} minutes\n", .{ uptime.days, uptime.hours, uptime.minutes });
    try bw.flush();

    const shell = try os_module.getShell(allocator);
    try stdout.print("Shell: {s}", .{shell});
    try bw.flush();
    allocator.free(shell);

    const cpu_info = try os_module.getCpuInfo(allocator);
    try stdout.print("cpu: {s} ({})\n", .{ cpu_info.cpu_name, cpu_info.cpu_cores });
    try bw.flush();
    allocator.free(cpu_info.cpu_name);

    const gpu_info = try os_module.getGpuInfo(allocator);
    try stdout.print("gpu: {s} ({})\n", .{ gpu_info.gpu_name, gpu_info.gpu_cores });
    try bw.flush();
    allocator.free(gpu_info.gpu_name);

    const ram_info = try os_module.getRamInfo();
    try stdout.print("ram: {d:.2} / {d:.2} GB ({}%)\n", .{ ram_info.ram_usage, ram_info.ram_size, ram_info.ram_usage_percentage });
    try bw.flush();

    const swap_info = try os_module.getSwapInfo();
    if (swap_info) |s| {
        try stdout.print("Swap: {d:.2} / {d:.2} GB ({}%)\n", .{ s.swap_usage, s.swap_size, s.swap_usage_percentage });
    } else {
        try stdout.print("Swap: Disabled\n", .{});
    }
    try bw.flush();

    const diskInfo = try os_module.getDiskSize("/");
    try stdout.print("disk ({s}): {d:.2} / {d:.2} GB ({}%)\n", .{ diskInfo.disk_path, diskInfo.disk_usage, diskInfo.disk_size, diskInfo.disk_usage_percentage });
    try bw.flush();

    const terminal_name = try os_module.getTerminalName(allocator);
    try stdout.print("terminal: {s}\n", .{terminal_name});
    try bw.flush();
    allocator.free(terminal_name);
}
