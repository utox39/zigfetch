const std = @import("std");
const c_sysinfo = @cImport(@cInclude("sys/sysinfo.h"));
const c_unistd = @cImport(@cInclude("unistd.h"));

/// Structure representing system uptime in days, hours, and minutes.
pub const SystemUptime = struct {
    days: i8,
    hours: i8,
    minutes: i8,
};

pub const CpuInfo = struct {
    cpu_name: []u8,
    cpu_cores: i32,
    cpu_max_freq: f32,
};

pub fn getUsername(allocator: std.mem.Allocator) ![]u8 {
    const username = try std.process.getEnvVarOwned(allocator, "USER");
    return username;
}

pub fn getHostname(allocator: std.mem.Allocator) ![]u8 {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostnameEnv = try std.posix.gethostname(&buf);

    const hostname = try allocator.dupe(u8, hostnameEnv);

    return hostname;
}

/// Returns the system uptime.
///
/// Uses `sysinfo` to fetch the system uptime and calculates the elapsed time.
pub fn getSystemUptime() !SystemUptime {
    const seconds_per_day: f64 = 86400.0;
    const hours_per_day: f64 = 24.0;
    const seconds_per_hour: f64 = 3600.0;
    const seconds_per_minute: f64 = 60.0;

    var info: c_sysinfo.struct_sysinfo = undefined;
    if (c_sysinfo.sysinfo(&info) != 0) {
        return error.SysinfoFailed;
    }

    const uptime_seconds: f64 = @as(f64, @floatFromInt(info.uptime));

    var remainig_seconds: f64 = uptime_seconds;
    const days: f64 = @floor(remainig_seconds / seconds_per_day);

    remainig_seconds = (remainig_seconds / seconds_per_day) - days;
    const hours = @floor(remainig_seconds * hours_per_day);

    remainig_seconds = (remainig_seconds * hours_per_day) - hours;
    const minutes = @floor((remainig_seconds * seconds_per_hour) / seconds_per_minute);

    return SystemUptime{
        .days = @as(i8, @intFromFloat(days)),
        .hours = @as(i8, @intFromFloat(hours)),
        .minutes = @as(i8, @intFromFloat(minutes)),
    };
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

pub fn getCpuInfo(allocator: std.mem.Allocator) !CpuInfo {
    const cpu_cores = c_unistd.sysconf(c_unistd._SC_NPROCESSORS_ONLN);

    // Reads /proc/cpuinfo
    const cpuinfo_path = "/proc/cpuinfo";
    var file = try std.fs.cwd().openFile(cpuinfo_path, .{});
    defer file.close();
    const cpuinfo_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(cpuinfo_data);

    // Parsing /proc/cpuinfo
    var model_name: ?[]const u8 = null;

    var lines = std.mem.split(u8, cpuinfo_data, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "model name") and model_name == null) {
            var parts = std.mem.split(u8, trimmed, ":");
            _ = parts.next(); // discards the key
            if (parts.next()) |value| {
                model_name = std.mem.trim(u8, value, " ");
                break;
            }
        }
    }

    // Reads /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq
    const cpuinfo_max_freq_path = "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq";
    var file2 = try std.fs.cwd().openFile(cpuinfo_max_freq_path, .{});
    defer file2.close();
    const cpuinfo_max_freq_data = try file2.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(cpuinfo_max_freq_data);

    // Parsing /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq
    const trimmed = std.mem.trim(u8, cpuinfo_max_freq_data, " \n\r");
    const cpu_max_freq_khz: f32 = try std.fmt.parseFloat(f32, trimmed);
    const cpu_max_freq: f32 = cpu_max_freq_khz / 1_000_000;

    return CpuInfo{
        .cpu_name = try allocator.dupe(u8, model_name orelse "Unknown"),
        .cpu_cores = @as(i32, @intCast(cpu_cores)),
        .cpu_max_freq = cpu_max_freq,
    };
}
