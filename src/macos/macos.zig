const std = @import("std");
const utils = @import("./utils.zig");
const c_libproc = @cImport(@cInclude("libproc.h"));
const c_sysctl = @cImport(@cInclude("sys/sysctl.h"));
const c_iokit = @cImport(@cInclude("IOKit/IOKitLib.h"));
const c_core_foundation = @cImport(@cInclude("CoreFoundation/CoreFoundation.h"));
const c_mach = @cImport(@cInclude("mach/mach.h"));

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

pub const RamInfo = struct {
    ram_size: f64,
    ram_usage: f64,
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
    if (c_sysctl.sysctl(&name, name.len, &boot_time, &size, null, 0) == 0) {
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
    var ram_info = RamInfo{
        .ram_size = 0,
        .ram_usage = 0,
    };

    // -- RAM SIZE --
    var ram_size: u64 = 0;
    var ram_size_len: usize = @sizeOf(u64);
    var name = [_]c_int{ c_sysctl.CTL_HW, c_sysctl.HW_MEMSIZE };
    if (c_sysctl.sysctl(&name, name.len, &ram_size, &ram_size_len, null, 0) != 0) {
        return error.FailedToGetRamSize;
    }

    // Converts Bytes to Gigabytes
    const ram_size_gb: f64 = @as(f64, @floatFromInt(ram_size)) / (1024 * 1024 * 1024);

    ram_info.ram_size = ram_size_gb;

    // -- RAM USAGE --
    var info: c_mach.vm_statistics64 = undefined;
    var count: c_mach.mach_msg_type_number_t = @sizeOf(c_mach.vm_statistics64) / @sizeOf(c_mach.integer_t);
    const host_port = c_mach.mach_host_self();

    if (c_mach.host_statistics64(host_port, c_mach.HOST_VM_INFO64, @ptrCast(&info), &count) != c_mach.KERN_SUCCESS) {
        return error.HostStatistics64Failed;
    }

    const page_size: u64 = std.mem.page_size;
    const ram_usage = (info.active_count + info.wire_count) * page_size;

    // Converts Bytes to Gigabytes
    const ram_usage_gb: f64 = @as(f64, @floatFromInt(ram_usage)) / (1024 * 1024 * 1024);

    ram_info.ram_usage = ram_usage_gb;

    return ram_info;
}
