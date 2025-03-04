const std = @import("std");
const os_module = @import("root.zig").os_module;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

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
}
