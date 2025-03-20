const std = @import("std");
const c_sysinfo = @cImport(@cInclude("sys/sysinfo.h"));
const c_utsname = @cImport(@cInclude("sys/utsname.h"));

/// Structure representing system uptime in days, hours, and minutes.
pub const SystemUptime = struct {
    days: i8,
    hours: i8,
    minutes: i8,
};

pub const KernelInfo = struct {
    kernel_name: []u8,
    kernel_release: []u8,
};

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

pub fn getKernelInfo(allocator: std.mem.Allocator) !KernelInfo {
    var uts: c_utsname.struct_utsname = undefined;
    if (c_utsname.uname(&uts) != 0) {
        return error.UnameFailed;
    }

    return KernelInfo{
        .kernel_name = try allocator.dupe(u8, &uts.sysname),
        .kernel_release = try allocator.dupe(u8, &uts.release),
    };
}

pub fn getOsInfo(allocator: std.mem.Allocator) ![]u8 {
    const os_release_path = "/etc/os-release";
    const file = try std.fs.cwd().openFile(os_release_path, .{});
    defer file.close();
    const os_release_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(os_release_data);

    var pretty_name: ?[]const u8 = null;

    var lines = std.mem.split(u8, os_release_data, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "PRETTY_NAME")) {
            var parts = std.mem.split(u8, line, "=");
            _ = parts.next(); // discard the key
            if (parts.next()) |value| {
                pretty_name = std.mem.trim(u8, value, "\"");
                break;
            }
        }
    }

    return try allocator.dupe(u8, pretty_name orelse "Unknown");
}
