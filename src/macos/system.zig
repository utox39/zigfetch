const std = @import("std");
const c_libproc = @import("bindings/libproc.zig");
const c = @import("c");

/// Struct representing system uptime in days, hours, and minutes.
pub const SystemUptime = struct {
    days: i8,
    hours: i8,
    minutes: i8,
};

/// Struct representing Kernel informations
pub const KernelInfo = struct {
    kernel_name: []u8,
    kernel_release: []u8,
};

/// Returns the hostname.
pub fn getHostname(gpa: std.mem.Allocator) ![]u8 {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostnameEnv = try std.posix.gethostname(&buf);

    const hostname = try gpa.dupe(u8, hostnameEnv);

    return hostname;
}

pub fn getLocale(gpa: std.mem.Allocator, environ: std.process.Environ) ![]u8 {
    const locale = std.process.Environ.getAlloc(environ, gpa, "LANG") catch |err| if (err == error.EnvironmentVariableMissing) {
        return gpa.dupe(u8, "Unknown");
    } else return err;
    return locale;
}

/// Returns the system uptime.
pub fn getSystemUptime(io: std.Io) SystemUptime {
    const seconds_per_day: f64 = 86400.0;
    const hours_per_day: f64 = 24.0;
    const seconds_per_hour: f64 = 3600.0;
    const seconds_per_minute: f64 = 60.0;

    const boot_seconds: f64 = @as(f64, @floatFromInt(std.Io.Timestamp.now(io, .boot).toSeconds()));

    var remainig_seconds: f64 = boot_seconds;
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

pub fn getKernelInfo(gpa: std.mem.Allocator) !KernelInfo {
    var size: usize = 0;

    // --- KERNEL NAME ---
    // First call to sysctlbyname to get the size of the string
    if (c.sysctlbyname("kern.ostype", null, &size, null, 0) != 0) {
        return error.FailedToGetKernelNameSize;
    }

    const kernel_type: []u8 = try gpa.alloc(u8, size - 1);
    errdefer gpa.free(kernel_type);

    // Second call to sysctlbyname to get the kernel name
    if (c.sysctlbyname("kern.ostype", kernel_type.ptr, &size, null, 0) != 0) {
        return error.FailedToGetKernelName;
    }

    // --- KERNEL RELEASE ---
    // First call to sysctlbyname to get the size of the string
    if (c.sysctlbyname("kern.osrelease", null, &size, null, 0) != 0) {
        return error.FailedToGetKernelReleaseSize;
    }

    const os_release: []u8 = try gpa.alloc(u8, size - 1);
    errdefer gpa.free(os_release);

    // Second call to sysctlbyname to get the kernel release
    if (c.sysctlbyname("kern.osrelease", os_release.ptr, &size, null, 0) != 0) {
        return error.FailedToGetKernelRelease;
    }

    return KernelInfo{
        .kernel_name = kernel_type,
        .kernel_release = os_release,
    };
}

pub fn getOsInfo(gpa: std.mem.Allocator) ![]u8 {
    var size: usize = 0;

    // First call to sysctlbyname to get the size of the string
    if (c.sysctlbyname("kern.osproductversion", null, &size, null, 0) != 0) {
        return error.FailedToGetCpuNameSize;
    }

    const os_version: []u8 = try gpa.alloc(u8, size - 1);
    defer gpa.free(os_version);

    // Second call to sysctlbyname to get the os version
    if (c.sysctlbyname("kern.osproductversion", os_version.ptr, &size, null, 0) != 0) {
        return error.FailedToGetOsVersion;
    }

    const os_info = try std.fmt.allocPrint(gpa, "macOS {s}", .{os_version});

    return os_info;
}

pub fn getWindowManagerInfo(gpa: std.mem.Allocator) ![]const u8 {
    var name = [_]c_int{ c.CTL_KERN, c.KERN_PROC, c.KERN_PROC_ALL };
    var size: usize = 0;

    // First call to get the dimension
    if (c.sysctl(&name, name.len, null, &size, null, 0) != 0) {
        return error.SysctlFailed;
    }

    const buffer: []u8 = try gpa.alloc(u8, size);
    defer gpa.free(buffer);

    // Second call to retrieve process data
    if (c.sysctl(&name, name.len, buffer.ptr, &size, null, 0) != 0) {
        return error.SysctlFailed;
    }

    // Ensure the buffer size is valid
    if (size % @sizeOf(c.struct_kinfo_proc) != 0) {
        return error.InvalidBufferSize;
    }

    const kinfo_list = std.mem.bytesAsSlice(c.struct_kinfo_proc, buffer);

    var wm_name: ?[]const u8 = null;

    const supported_wms: [6][]const u8 = .{
        "aerospace",
        "amethyst",
        "chunkwm",
        "rectangle",
        "spectacle",
        "yabai",
    };

    wm_name = outer: {
        for (kinfo_list) |kinfo| {
            const pid = kinfo.kp_proc.p_pid;
            if (pid <= 0) continue;

            // Gets the process pathname
            var pathbuf: [c_libproc.PROC_PIDPATHINFO_MAXSIZE]u8 = undefined;
            // c_libproc.proc_pidpath saves the process name in `pathbuf` and returns the len
            const path_len = @as(usize, @intCast(c_libproc.proc_pidpath(pid, &pathbuf, pathbuf.len)));
            const proc_pathname = if (path_len > 0) try gpa.dupe(u8, pathbuf[0..@intCast(path_len)]) else try gpa.dupe(u8, "unknown");
            defer gpa.free(proc_pathname);

            inline for (supported_wms) |wm| {
                if (std.ascii.endsWithIgnoreCase(proc_pathname, wm)) {
                    const basename = if (std.mem.lastIndexOfScalar(u8, proc_pathname, '/')) |index|
                        proc_pathname[index + 1 ..]
                    else
                        proc_pathname;

                    break :outer try gpa.dupe(u8, basename);
                }
            }
        }

        break :outer null;
    };

    return wm_name orelse gpa.dupe(u8, "Quartz Compositor");
}
