const std = @import("std");
const c_libproc = @cImport(@cInclude("libproc.h"));
const c_sysctl = @cImport(@cInclude("sys/sysctl.h"));

/// Structure representing system uptime in days, hours, and minutes.
pub const SystemUptime = struct {
    days: i8,
    hours: i8,
    minutes: i8,
};

pub const CpuInfo = struct {
    cpu_name: []u8,
    cpu_cores: i32,
};

/// Returns the current logged-in uesr's username.
/// Uses the environment variable `USER`.
/// The caller is responsible for freeing the allocated memory.
pub fn getUsername(allocator: std.mem.Allocator) ![]u8 {
    const username = try std.process.getEnvVarOwned(allocator, "USER");
    return username;
}

/// Returns the hostname.
pub fn getHostname(allocator: std.mem.Allocator) ![]u8 {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostnameEnv = try std.posix.gethostname(&buf);

    const hostname = try allocator.dupe(u8, hostnameEnv);

    return hostname;
}

/// Returns the system uptime.
///
/// Uses `sysctl` to fetch the system boot time and calculates the elapsed time.
pub fn getSystemUptime() !SystemUptime {
    const seconds_per_day: f64 = 86400.0;
    const hours_per_day: f64 = 24.0;
    const seconds_per_hour: f64 = 3600.0;
    const seconds_per_minute: f64 = 60.0;

    var boot_time: c_libproc.struct_timeval = undefined;
    var size: usize = @sizeOf(c_libproc.struct_timeval);

    var uptime_ns: f64 = 0.0;

    var name = [_]c_int{ c_sysctl.CTL_KERN, c_sysctl.KERN_BOOTTIME };
    if (c_sysctl.sysctl(&name, 2, &boot_time, &size, null, 0) == 0) {
        const boot_seconds = @as(f64, @floatFromInt(boot_time.tv_sec));
        const now_seconds = @as(f64, @floatFromInt(std.time.timestamp()));
        uptime_ns = now_seconds - boot_seconds;
    } else {
        return error.UnableToGetSystemUptime;
    }

    var remainig_seconds: f64 = uptime_ns;
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
    var size: usize = 0;

    // First call to sysctlbyname to get the size of the string
    if (c_sysctl.sysctlbyname("machdep.cpu.brand_string", null, &size, null, 0) != 0) {
        return error.FailedToGetCpuNameSize;
    }

    const cpu_name: []u8 = try allocator.alloc(u8, size);

    // Second call to sysctlbyname to get the CPU name
    if (c_sysctl.sysctlbyname("machdep.cpu.brand_string", cpu_name.ptr, &size, null, 0) != 0) {
        allocator.free(cpu_name);
        return error.FailedToGetCpuName;
    }

    // Call to sysctlbyname to get the cpu cores
    var n_cpu: i32 = 0;
    size = @sizeOf(i32);
    if (c_sysctl.sysctlbyname("hw.ncpu", &n_cpu, &size, null, 0) != 0) {
        return error.FailedToGetPhysicalCpuInfo;
    }

    // TODO: add cpu frequency (find a way to get it even on Apple Silicon)

    return CpuInfo{
        .cpu_name = cpu_name,
        .cpu_cores = n_cpu,
    };
}
