const std = @import("std");
const utils = @import("utils.zig");
const c_sysctl = @cImport(@cInclude("sys/sysctl.h"));
const c_iokit = @cImport(@cInclude("IOKit/IOKitLib.h"));
const c_cf = @cImport(@cInclude("CoreFoundation/CoreFoundation.h"));
const c_mach = @cImport(@cInclude("mach/mach.h"));
const c_statvfs = @cImport(@cInclude("sys/statvfs.h"));

/// Struct representing CPU informations
pub const CpuInfo = struct {
    cpu_name: []u8,
    cpu_cores: i32,
    cpu_max_freq: f64,

    pub fn toStr(self: CpuInfo, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{s} ({}) @ {d:.2} GHz", .{ self.cpu_name, self.cpu_cores, self.cpu_max_freq });
    }
};

/// Struct representing GPU informations
pub const GpuInfo = struct {
    gpu_name: []u8,
    gpu_cores: i32,
    gpu_freq: f64,

    pub fn toStr(self: GpuInfo, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{s} ({}) @ {d:.2} GHz", .{ self.gpu_name, self.gpu_cores, self.gpu_freq });
    }
};

/// Struct representing RAM usage informations
pub const RamInfo = struct {
    ram_size: f64,
    ram_usage: f64,
    ram_usage_percentage: u8,

    pub fn toStr(self: RamInfo, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{d:.2} / {d:.2} GiB ({}%)", .{ self.ram_usage, self.ram_size, self.ram_usage_percentage });
    }
};

/// Struct representing Swap usage informations
pub const SwapInfo = struct {
    swap_size: f64,
    swap_usage: f64,
    swap_usage_percentage: u64,

    pub fn toStr(self: SwapInfo, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{d:.2} / {d:.2} GiB ({}%)", .{ self.swap_usage, self.swap_size, self.swap_usage_percentage });
    }
};

/// Struct representing Disk usage informations
pub const DiskInfo = struct {
    disk_path: []const u8,
    disk_size: f64,
    disk_usage: f64,
    disk_usage_percentage: u8,

    pub fn toStr(self: DiskInfo, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "({s}): {d:.2} / {d:.2} GB ({}%)", .{ self.disk_path, self.disk_usage, self.disk_size, self.disk_usage_percentage });
    }
};

pub fn getCpuInfo(allocator: std.mem.Allocator) !CpuInfo {
    var size: usize = 0;

    // First call to sysctlbyname to get the size of the string
    if (c_sysctl.sysctlbyname("machdep.cpu.brand_string", null, &size, null, 0) != 0) {
        return error.FailedToGetCpuNameSize;
    }

    const cpu_name: []u8 = try allocator.alloc(u8, size - 1);
    errdefer allocator.free(cpu_name);

    // Second call to sysctlbyname to get the CPU name
    if (c_sysctl.sysctlbyname("machdep.cpu.brand_string", cpu_name.ptr, &size, null, 0) != 0) {
        return error.FailedToGetCpuName;
    }

    // Call to sysctlbyname to get the cpu cores
    var n_cpu: i32 = 0;
    size = @sizeOf(i32);
    if (c_sysctl.sysctlbyname("hw.ncpu", &n_cpu, &size, null, 0) != 0) {
        return error.FailedToGetPhysicalCpuInfo;
    }

    // Get cpu architecture
    const arch: []u8 = try getCpuArch(allocator);
    defer allocator.free(arch);

    var cpu_freq_mhz: f64 = 0.0;

    if (std.mem.eql(u8, arch, "arm64")) {
        cpu_freq_mhz = try getCpuFreqAppleSilicon();
    } else if (std.mem.eql(u8, arch, "x86_64")) {
        cpu_freq_mhz = getCpuFreqIntel();
    }

    const cpu_freq_ghz = @floor(cpu_freq_mhz) / 1000;

    return CpuInfo{ .cpu_name = cpu_name, .cpu_cores = n_cpu, .cpu_max_freq = cpu_freq_ghz };
}

fn getCpuArch(allocator: std.mem.Allocator) ![]u8 {
    var size: usize = 0;

    if (c_sysctl.sysctlbyname("hw.machine", null, &size, null, 0) != 0) {
        return error.SysctlbynameFailed;
    }

    const machine: []u8 = try allocator.alloc(u8, size);

    if (c_sysctl.sysctlbyname("hw.machine", machine.ptr, &size, null, 0) != 0) {
        return error.SysctlbynameFailed;
    }

    defer allocator.free(machine);

    return allocator.dupe(u8, std.mem.sliceTo(machine, 0));
}

fn getCpuFreqAppleSilicon() !f64 {
    // https://github.com/fastfetch-cli/fastfetch/blob/dev/src/detection/cpu/cpu_apple.c

    // Retrieve the matching service for "pmgr"
    // https://developer.apple.com/documentation/iokit/1514535-ioservicegetmatchingservice
    const service = c_iokit.IOServiceGetMatchingService(c_iokit.kIOMasterPortDefault, c_iokit.IOServiceNameMatching("pmgr"));
    if (service == c_iokit.FALSE) return error.NoMatchingService;
    defer _ = c_iokit.IOObjectRelease(service);

    // Check that the service conforms to "AppleARMIODevice"
    // https://developer.apple.com/documentation/iokit/1514505-ioobjectconformsto
    if (c_iokit.IOObjectConformsTo(service, "AppleARMIODevice") == c_iokit.FALSE) {
        return error.NotAppleARMIODevice;
    }

    // CFSTR is a macro and can't be translated by Zig
    // The CFString is created "manually"
    const vs5s_key = c_iokit.CFStringCreateWithCString(c_iokit.kCFAllocatorDefault, "voltage-states5-sram", c_iokit.kCFStringEncodingUTF8);
    if (vs5s_key == null) {
        return error.FailedToCreateCFKey;
    }
    defer c_iokit.CFRelease(vs5s_key);

    // Retrieve the property from the registry entry
    // https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty
    const freq_property = c_iokit.IORegistryEntryCreateCFProperty(service, vs5s_key, c_iokit.kCFAllocatorDefault, 0);
    if (freq_property == null) return error.PropertyNotFound;
    defer c_iokit.CFRelease(freq_property);

    // Ensure the property is a CFData object
    if (c_iokit.CFGetTypeID(freq_property) != c_cf.CFDataGetTypeID())
        return error.InvalidPropertyType;

    const freq_data = @as(*const c_iokit.__CFData, @ptrCast(freq_property));

    // Get the length of the CFData
    const freq_data_length = c_iokit.CFDataGetLength(freq_data);

    // voltage-states5-sram stores supported <frequency / voltage> pairs of pcores from the lowest to the highest
    if (freq_data_length == 0 or @as(u32, @intCast(freq_data_length)) % (@sizeOf(u32) * 2) != 0)
        return error.InvalidVoltageStates5SramLength;

    // Get data pointer
    const freq_data_ptr = c_iokit.CFDataGetBytePtr(freq_data);
    if (freq_data_ptr == null)
        return error.InvalidVoltageStates5SramData;

    const freq_array = @as([*]const u32, @ptrCast(@alignCast(freq_data_ptr)));

    // The first element contains the minimum freq
    var p_max: u32 = freq_array[0];

    const total_elements = @as(u32, @intCast(freq_data_length)) / @sizeOf(u32);

    // Iterate on values, starting at index 2, skipping voltage (each pair is <frequency, voltage>)
    var i: usize = 2;
    while (i < total_elements) : (i += 2) {
        const current = freq_array[i];
        if (current == 0) break;
        if (current > p_max) {
            p_max = current;
        }
    }

    // Assume that p_max is in Hz, M1~M3
    if (p_max > 100_000_000) {
        return @as(f64, @floatFromInt(p_max)) / 1_000 / 1_000;
    } else { // Assume that p_max is in kHz, M4 and later
        return @as(f64, @floatFromInt(p_max)) / 1_000;
    }
}

// TODO: test on intel machine
pub fn getCpuFreqIntel() f64 {
    var freq: f64 = 0;
    var size: usize = @sizeOf(f64);

    if (c_sysctl.sysctlbyname("hw.cpufrequency_max", &freq, &size, null, 0) != 0) {
        return 0.0;
    }

    // Converts from Hz to MHz
    return freq / 1_000_000.0;
}

pub fn getGpuInfo(allocator: std.mem.Allocator) !GpuInfo {
    // TODO: add support for non-Apple Silicon Macs

    var gpu_info = GpuInfo{
        .gpu_name = try allocator.dupe(u8, "Unknown"),
        .gpu_cores = 0,
        .gpu_freq = 0.0,
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
            if (c_iokit.CFGetTypeID(cores_ref) == c_cf.CFNumberGetTypeID()) {
                var cores_num: i32 = 0;
                if (c_cf.CFNumberGetValue(@as(c_cf.CFNumberRef, @ptrCast(cores_ref)), c_cf.kCFNumberIntType, &cores_num) == c_cf.TRUE) {
                    gpu_info.gpu_cores = cores_num;
                }
            }
        }
    }

    // Get cpu architecture
    const arch: []u8 = try getCpuArch(allocator);
    defer allocator.free(arch);

    var gpu_freq_mhz: f64 = 0.0;

    if (std.mem.eql(u8, arch, "arm64")) {
        gpu_freq_mhz = try getAppleSiliconGpuFreq();
    }

    const gpu_freq_ghz = @floor(gpu_freq_mhz) / 1000;
    gpu_info.gpu_freq = gpu_freq_ghz;

    return gpu_info;
}

fn getAppleSiliconGpuFreq() !f64 {
    // https://github.com/fastfetch-cli/fastfetch/blob/dev/src/detection/gpu/gpu_apple.c

    // Retrieve the matching service for "pmgr"
    // https://developer.apple.com/documentation/iokit/1514535-ioservicegetmatchingservice
    const service = c_iokit.IOServiceGetMatchingService(c_iokit.kIOMasterPortDefault, c_iokit.IOServiceNameMatching("pmgr"));
    if (service == c_iokit.FALSE) return error.NoMatchingService;
    defer _ = c_iokit.IOObjectRelease(service);

    // Check that the service conforms to "AppleARMIODevice"
    // https://developer.apple.com/documentation/iokit/1514505-ioobjectconformsto
    if (c_iokit.IOObjectConformsTo(service, "AppleARMIODevice") == c_iokit.FALSE) {
        return error.NotAppleARMIODevice;
    }

    // CFSTR is a macro and can't be translated by Zig
    // The CFString is created "manually"
    const vs9s_key = c_iokit.CFStringCreateWithCString(c_iokit.kCFAllocatorDefault, "voltage-states9-sram", c_iokit.kCFStringEncodingUTF8);
    if (vs9s_key == null) {
        return error.FailedToCreateCFKey;
    }
    defer c_iokit.CFRelease(vs9s_key);

    // Retrieve the property from the registry entry
    // https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty
    const freq_property = c_iokit.IORegistryEntryCreateCFProperty(service, vs9s_key, c_iokit.kCFAllocatorDefault, 0);
    if (freq_property == null) return error.PropertyNotFound;
    defer c_iokit.CFRelease(freq_property);

    // Ensure the property is a CFData object
    if (c_iokit.CFGetTypeID(freq_property) != c_cf.CFDataGetTypeID())
        return error.InvalidPropertyType;

    const freq_data = @as(*const c_iokit.__CFData, @ptrCast(freq_property));

    // Get the length of the CFData
    const freq_data_length = c_iokit.CFDataGetLength(freq_data);

    // voltage-states9-sram stores supported <frequency / voltage> pairs of pcores from the lowest to the highest
    if (freq_data_length == 0 or @as(u32, @intCast(freq_data_length)) % (@sizeOf(u32) * 2) != 0)
        return error.InvalidVoltageStates5SramLength;

    // Get data pointer
    const freq_data_ptr = c_iokit.CFDataGetBytePtr(freq_data);
    if (freq_data_ptr == null)
        return error.InvalidVoltageStates5SramData;

    const freq_array = @as([*]const u32, @ptrCast(@alignCast(freq_data_ptr)));

    // The first element contains the minimum freq
    var p_max: u32 = freq_array[0];

    const total_elements = @as(u32, @intCast(freq_data_length)) / @sizeOf(u32);

    // Iterate on values, starting at index 2, skipping voltage (each pair is <frequency, voltage>)
    var i: usize = 2;
    while (i < total_elements) : (i += 2) {
        const current = freq_array[i];
        if (current == 0) break;
        if (current > p_max) {
            p_max = current;
        }
    }

    // Assume that p_max is in Hz, M1~M3
    if (p_max > 100_000_000) {
        return @as(f64, @floatFromInt(p_max)) / 1_000 / 1_000;
    } else { // Assume that p_max is in kHz, M4 and later
        return @as(f64, @floatFromInt(p_max)) / 1_000;
    }
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

    // https://github.com/fastfetch-cli/fastfetch/blob/dev/src/detection/memory/memory_apple.c
    const ram_usage = (info.active_count + info.inactive_count + info.speculative_count + info.wire_count + info.compressor_page_count - info.purgeable_count - info.external_page_count) * page_size;

    // Converts Bytes to Gigabytes
    const ram_usage_gb: f64 = @as(f64, @floatFromInt(ram_usage)) / (1024 * 1024 * 1024);

    const ram_usage_percentage: u8 = @as(u8, @intFromFloat((ram_usage_gb * 100) / ram_size_gb));

    return RamInfo{
        .ram_size = ram_size_gb,
        .ram_usage = ram_usage_gb,
        .ram_usage_percentage = ram_usage_percentage,
    };
}

pub fn getSwapInfo() !?SwapInfo {
    var swap: c_sysctl.struct_xsw_usage = undefined;
    var size: usize = @sizeOf(c_sysctl.struct_xsw_usage);

    if (c_sysctl.sysctlbyname("vm.swapusage", &swap, &size, null, 0) != 0) {
        return error.FailedToGetSwapInfo;
    }

    const swap_size = @as(f64, @floatFromInt(swap.xsu_total / (1024 * 1024 * 1024)));
    const swap_usage = @as(f64, @floatFromInt(swap.xsu_used)) / (1024 * 1024 * 1024);
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
