const std = @import("std");
const utils = @import("./utils.zig");
const c_libproc = @cImport(@cInclude("libproc.h"));
const c_sysctl = @cImport(@cInclude("sys/sysctl.h"));
const c_iokit = @cImport(@cInclude("IOKit/IOKitLib.h"));
const c_core_foundation = @cImport(@cInclude("CoreFoundation/CoreFoundation.h"));
const c_mach = @cImport(@cInclude("mach/mach.h"));
const c_statvfs = @cImport(@cInclude("sys/statvfs.h"));

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

pub const GpuInfo = struct {
    gpu_name: []u8,
    gpu_cores: i32,
};

pub const KernelInfo = struct {
    kernel_name: []u8,
    kernel_release: []u8,
};

pub const RamInfo = struct {
    ram_size: f64,
    ram_usage: f64,
    ram_usage_percentage: u8,
};

pub const DiskInfo = struct {
    disk_path: []const u8,
    disk_size: f64,
    disk_usage: f64,
    disk_usage_percentage: u8,
};

pub const SwapInfo = struct {
    swap_size: f64,
    swap_usage: f64,
    swap_usage_percentage: u64,
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

    const cpu_name: []u8 = try allocator.alloc(u8, size - 1);

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

/// Returns the gpu info.
pub fn getGpuInfo(allocator: std.mem.Allocator) !GpuInfo {
    // TODO: add support for non-Apple Silicon Macs

    var gpu_info = GpuInfo{
        .gpu_name = try allocator.dupe(u8, "Unknown"),
        .gpu_cores = 0,
    };

    // https://developer.apple.com/documentation/iokit/1514687-ioservicematching
    const accel_matching_dict = c_iokit.IOServiceMatching("IOAccelerator");
    if (accel_matching_dict == null) {
        return error.MatchingDictionaryCreationFailed;
    }

    var iterator: c_iokit.io_iterator_t = undefined;
    // https://developer.apple.com/documentation/iokit/1514494-ioservicegetmatchingservices
    const result = c_iokit.IOServiceGetMatchingServices(c_iokit.kIOMasterPortDefault, accel_matching_dict, &iterator);

    if (result != c_iokit.KERN_SUCCESS) {
        return error.ServiceMatchingFailed;
    }
    defer _ = c_iokit.IOObjectRelease(iterator);

    const service = c_iokit.IOIteratorNext(iterator);
    if (service != 0) {
        defer _ = c_iokit.IOObjectRelease(service);

        var properties_ptr: c_iokit.CFMutableDictionaryRef = null;
        const properties_ptr_ref: [*c]c_iokit.CFMutableDictionaryRef = &properties_ptr;

        // https://developer.apple.com/documentation/iokit/1514310-ioregistryentrycreatecfpropertie
        if (c_iokit.IORegistryEntryCreateCFProperties(service, properties_ptr_ref, c_iokit.kCFAllocatorDefault, 0) != c_iokit.KERN_SUCCESS) {
            return gpu_info;
        }

        if (properties_ptr == null) {
            return gpu_info;
        }
        defer c_iokit.CFRelease(properties_ptr);

        var name_ref: c_iokit.CFTypeRef = undefined;
        var cores_ref: c_iokit.CFTypeRef = undefined;

        // CFSTR is a macro and can't be translated by Zig
        // The CFString is created "manually"
        const model_key = c_iokit.CFStringCreateWithCString(c_iokit.kCFAllocatorDefault, "model", c_iokit.kCFStringEncodingUTF8);
        if (model_key == null) return gpu_info;
        defer c_iokit.CFRelease(model_key);

        if (c_iokit.CFDictionaryGetValueIfPresent(@as(c_iokit.CFDictionaryRef, @ptrCast(properties_ptr)), model_key, &name_ref) == c_iokit.TRUE) {
            if (c_iokit.CFGetTypeID(name_ref) == c_iokit.CFStringGetTypeID()) {
                const accel_name = utils.cfStringToZigString(allocator, @as(c_iokit.CFStringRef, @ptrCast(name_ref))) catch {
                    return gpu_info;
                };

                allocator.free(gpu_info.gpu_name);
                gpu_info.gpu_name = accel_name;
            }
        }

        // CFSTR is a macro and can't be translated by Zig
        // The CFString is created "manually"
        const gpu_core_count_key = c_iokit.CFStringCreateWithCString(c_iokit.kCFAllocatorDefault, "gpu-core-count", c_iokit.kCFStringEncodingUTF8);
        if (gpu_core_count_key == null) return gpu_info;
        defer c_iokit.CFRelease(gpu_core_count_key);

        if (c_iokit.CFDictionaryGetValueIfPresent(@as(c_iokit.CFDictionaryRef, @ptrCast(properties_ptr)), gpu_core_count_key, &cores_ref) == c_iokit.TRUE) {
            if (c_iokit.CFGetTypeID(cores_ref) == c_core_foundation.CFNumberGetTypeID()) {
                var cores_num: i32 = 0;
                if (c_core_foundation.CFNumberGetValue(@as(c_core_foundation.CFNumberRef, @ptrCast(cores_ref)), c_core_foundation.kCFNumberIntType, &cores_num) == c_core_foundation.TRUE) {
                    gpu_info.gpu_cores = cores_num;
                }
            }
        }
    }

    return gpu_info;
}

pub fn getRamInfo() !RamInfo {
    // -- RAM SIZE --
    var ram_size: u64 = 0;
    var ram_size_len: usize = @sizeOf(u64);
    var name = [_]c_int{ c_sysctl.CTL_HW, c_sysctl.HW_MEMSIZE };
    if (c_sysctl.sysctl(&name, name.len, &ram_size, &ram_size_len, null, 0) != 0) {
        return error.FailedToGetRamSize;
    }

    // Converts Bytes to Gigabytes
    const ram_size_gb: f64 = @as(f64, @floatFromInt(ram_size)) / (1024 * 1024 * 1024);

    // -- RAM USAGE --
    var info: c_mach.vm_statistics64 = undefined;
    var count: c_mach.mach_msg_type_number_t = @sizeOf(c_mach.vm_statistics64) / @sizeOf(c_mach.integer_t);
    const host_port = c_mach.mach_host_self();

    if (c_mach.host_statistics64(host_port, c_mach.HOST_VM_INFO64, @ptrCast(&info), &count) != c_mach.KERN_SUCCESS) {
        return error.HostStatistics64Failed;
    }

    const page_size: u64 = std.heap.page_size_min;
    const ram_usage = (info.active_count + info.wire_count) * page_size;

    // Converts Bytes to Gigabytes
    const ram_usage_gb: f64 = @as(f64, @floatFromInt(ram_usage)) / (1024 * 1024 * 1024);

    const ram_usage_percentage: u8 = @as(u8, @intFromFloat((ram_usage_gb * 100) / ram_size_gb));

    return RamInfo{
        .ram_size = ram_size_gb,
        .ram_usage = ram_usage_gb,
        .ram_usage_percentage = ram_usage_percentage,
    };
}

pub fn getDiskSize(disk_path: []const u8) !DiskInfo {
    var stat: c_statvfs.struct_statvfs = undefined;
    if (c_statvfs.statvfs(disk_path.ptr, &stat) != 0) {
        return error.StatvfsFailed;
    }

    const total_size = stat.f_blocks * stat.f_frsize;
    const free_size = stat.f_bavail * stat.f_frsize;
    const used_size = total_size - free_size;

    const used_size_percentage = (used_size * 100) / total_size;

    return DiskInfo{
        .disk_path = disk_path,
        .disk_size = @as(f64, @floatFromInt(total_size)) / 1e9,
        .disk_usage = @as(f64, @floatFromInt(used_size)) / 1e9,
        .disk_usage_percentage = @as(u8, @intCast(used_size_percentage)),
    };
}

pub fn getTerminalName(allocator: std.mem.Allocator) ![]u8 {
    const term_progrm = try std.process.getEnvVarOwned(allocator, "TERM_PROGRAM");
    return term_progrm;
}

pub fn getKernelInfo(allocator: std.mem.Allocator) !KernelInfo {
    var size: usize = 0;

    // --- KERNEL NAME ---
    // First call to sysctlbyname to get the size of the string
    if (c_sysctl.sysctlbyname("kern.ostype", null, &size, null, 0) != 0) {
        return error.FailedToGetKernelNameSize;
    }

    const kernel_type: []u8 = try allocator.alloc(u8, size - 1);

    // Second call to sysctlbyname to get the kernel name
    if (c_sysctl.sysctlbyname("kern.ostype", kernel_type.ptr, &size, null, 0) != 0) {
        allocator.free(kernel_type);
        return error.FailedToGetKernelName;
    }

    // --- KERNEL RELEASE ---
    // First call to sysctlbyname to get the size of the string
    if (c_sysctl.sysctlbyname("kern.osrelease", null, &size, null, 0) != 0) {
        return error.FailedToGetKernelReleaseSize;
    }

    const os_release: []u8 = try allocator.alloc(u8, size - 1);

    // Second call to sysctlbyname to get the kernel release
    if (c_sysctl.sysctlbyname("kern.osrelease", os_release.ptr, &size, null, 0) != 0) {
        allocator.free(os_release);
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
        allocator.free(os_version);
        return error.FailedToGetOsVersion;
    }

    const os_info = try std.fmt.allocPrint(allocator, "macOS {s}", .{os_version});

    return os_info;
}

pub fn getSwapInfo() !?SwapInfo {
    var swap: c_sysctl.struct_xsw_usage = undefined;
    var size: usize = @sizeOf(c_sysctl.struct_xsw_usage);

    if (c_sysctl.sysctlbyname("vm.swapusage", &swap, &size, null, 0) != 0) {
        return error.FailedToGetSwapInfo;
    }

    const swap_size = @as(f64, @floatFromInt(swap.xsu_total / (1024 * 1024 * 1024)));
    const swap_usage = @as(f64, @floatFromInt(swap.xsu_used / (1024 * 1024 * 1024)));
    var swap_usage_percentage: u64 = 0;
    if (@as(u64, swap.xsu_total) != 0) {
        swap_usage_percentage = (@as(u64, swap.xsu_used) * 100) / @as(u64, swap.xsu_total);
    } else {
        return null;
    }

    return SwapInfo{
        .swap_size = swap_size,
        .swap_usage = swap_usage,
        .swap_usage_percentage = swap_usage_percentage,
    };
}
