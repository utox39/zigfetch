const std = @import("std");
const c_sysctl = @cImport(@cInclude("sys/sysctl.h"));
const c_libproc = @cImport(@cInclude("libproc.h"));

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

// Returns the hostname.
pub fn getHostname(allocator: std.mem.Allocator) ![]u8 {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostnameEnv = try std.posix.gethostname(&buf);

    const hostname = try allocator.dupe(u8, hostnameEnv);

    return hostname;
}

pub fn getLocale(allocator: std.mem.Allocator) ![]u8 {
    const locale = try std.process.getEnvVarOwned(allocator, "LANG");
    return locale;
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

    var uptime_seconds: f64 = 0.0;

    var name = [_]c_int{ c_sysctl.CTL_KERN, c_sysctl.KERN_BOOTTIME };
    if (c_sysctl.sysctl(&name, name.len, &boot_time, &size, null, 0) == 0) {
        const boot_seconds = @as(f64, @floatFromInt(boot_time.tv_sec));
        const now_seconds = @as(f64, @floatFromInt(std.time.timestamp()));
        uptime_seconds = now_seconds - boot_seconds;
    } else {
        return error.UnableToGetSystemUptime;
    }

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
    var size: usize = 0;

    // --- KERNEL NAME ---
    // First call to sysctlbyname to get the size of the string
    if (c_sysctl.sysctlbyname("kern.ostype", null, &size, null, 0) != 0) {
        return error.FailedToGetKernelNameSize;
    }

    const kernel_type: []u8 = try allocator.alloc(u8, size - 1);
    errdefer allocator.free(kernel_type);

    // Second call to sysctlbyname to get the kernel name
    if (c_sysctl.sysctlbyname("kern.ostype", kernel_type.ptr, &size, null, 0) != 0) {
        return error.FailedToGetKernelName;
    }

    // --- KERNEL RELEASE ---
    // First call to sysctlbyname to get the size of the string
    if (c_sysctl.sysctlbyname("kern.osrelease", null, &size, null, 0) != 0) {
        return error.FailedToGetKernelReleaseSize;
    }

    const os_release: []u8 = try allocator.alloc(u8, size - 1);
    errdefer allocator.free(os_release);

    // Second call to sysctlbyname to get the kernel release
    if (c_sysctl.sysctlbyname("kern.osrelease", os_release.ptr, &size, null, 0) != 0) {
        return error.FailedToGetKernelRelease;
    }

    return KernelInfo{
        .kernel_name = kernel_type,
        .kernel_release = os_release,
    };
}

pub fn getOsInfo(allocator: std.mem.Allocator) ![]u8 {
    var size: usize = 0;

    // First call to sysctlbyname to get the size of the string
    if (c_sysctl.sysctlbyname("kern.osproductversion", null, &size, null, 0) != 0) {
        return error.FailedToGetCpuNameSize;
    }

    const os_version: []u8 = try allocator.alloc(u8, size - 1);
    defer allocator.free(os_version);

    // Second call to sysctlbyname to get the os version
    if (c_sysctl.sysctlbyname("kern.osproductversion", os_version.ptr, &size, null, 0) != 0) {
        return error.FailedToGetOsVersion;
    }

    const os_info = try std.fmt.allocPrint(allocator, "macOS {s}", .{os_version});

    return os_info;
}
