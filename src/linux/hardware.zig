const std = @import("std");
const c_unistd = @cImport(@cInclude("unistd.h"));
const c_statvfs = @cImport(@cInclude("sys/statvfs.h"));

/// Struct representing CPU informations
pub const CpuInfo = struct {
    cpu_name: []u8,
    cpu_cores: i32,
    cpu_max_freq: f32,

    pub fn toStr(self: CpuInfo, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{s} ({}) @ {d:.2} GHz", .{ self.cpu_name, self.cpu_cores, self.cpu_max_freq });
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
    swap_usage_percentage: u8,

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
    const cpu_cores = c_unistd.sysconf(c_unistd._SC_NPROCESSORS_ONLN);

    // Reads /proc/cpuinfo
    const cpuinfo_path = "/proc/cpuinfo";
    var file = try std.fs.cwd().openFile(cpuinfo_path, .{});
    defer file.close();
    const cpuinfo_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(cpuinfo_data);

    // Parsing /proc/cpuinfo
    var model_name: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, cpuinfo_data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "model name") and model_name == null) {
            var parts = std.mem.splitScalar(u8, trimmed, ':');
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

pub fn getRamInfo(allocator: std.mem.Allocator) !RamInfo {
    // Reads /proc/meminfo
    const meminfo_path = "/proc/meminfo";
    const file = try std.fs.cwd().openFile(meminfo_path, .{});
    defer file.close();
    const meminfo_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(meminfo_data);

    // Parsing /proc/meminfo
    var total_mem: f64 = 0.0;
    var free_mem: f64 = 0.0; // remove?
    var available_mem: f64 = 0.0;

    var total_mem_str: ?[]const u8 = null;
    var free_mem_str: ?[]const u8 = null;
    var available_mem_str: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, meminfo_data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "MemTotal")) {
            var parts = std.mem.splitScalar(u8, trimmed, ':');
            _ = parts.next(); // discards the key
            if (parts.next()) |value| {
                total_mem_str = std.mem.trim(u8, value[0..(value.len - 3)], " ");
                total_mem = try std.fmt.parseFloat(f64, total_mem_str.?);
            }
        } else if (std.mem.startsWith(u8, trimmed, "MemFree")) {
            var parts = std.mem.splitScalar(u8, trimmed, ':');
            _ = parts.next(); // discards the key
            if (parts.next()) |value| {
                free_mem_str = std.mem.trim(u8, value[0..(value.len - 3)], " ");
                free_mem = try std.fmt.parseFloat(f64, free_mem_str.?);
            }
        } else if (std.mem.startsWith(u8, trimmed, "MemAvailable")) {
            var parts = std.mem.splitScalar(u8, trimmed, ':');
            _ = parts.next(); // discards the key
            if (parts.next()) |value| {
                available_mem_str = std.mem.trim(u8, value[0..(value.len - 3)], " ");
                available_mem = try std.fmt.parseFloat(f64, available_mem_str.?);
            }
        }

        if ((total_mem_str != null) and (free_mem_str != null) and (available_mem_str != null)) {
            break;
        }
    }

    var used_mem = total_mem - available_mem;

    // Converts KB in GB
    total_mem /= (1024 * 1024);
    used_mem /= (1024 * 1024);
    const ram_usage_percentage: u8 = @as(u8, @intFromFloat((used_mem * 100) / total_mem));

    return RamInfo{
        .ram_size = total_mem,
        .ram_usage = used_mem,
        .ram_usage_percentage = ram_usage_percentage,
    };
}

pub fn getSwapInfo(allocator: std.mem.Allocator) !?SwapInfo {
    // Reads /proc/meminfo
    const meminfo_path = "/proc/meminfo";
    const file = try std.fs.cwd().openFile(meminfo_path, .{});
    defer file.close();
    const meminfo_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(meminfo_data);

    // Parsing /proc/meminfo
    var total_swap: f64 = 0.0;
    var free_swap: f64 = 0.0;

    var total_swap_str: ?[]const u8 = null;
    var free_swap_str: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, meminfo_data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "SwapTotal")) {
            var parts = std.mem.splitScalar(u8, trimmed, ':');
            _ = parts.next(); // discards the key
            if (parts.next()) |value| {
                total_swap_str = std.mem.trim(u8, value[0..(value.len - 3)], " ");
                total_swap = try std.fmt.parseFloat(f64, total_swap_str.?);
            }
        } else if (std.mem.startsWith(u8, trimmed, "SwapFree")) {
            var parts = std.mem.splitScalar(u8, trimmed, ':');
            _ = parts.next(); // discards the key
            if (parts.next()) |value| {
                free_swap_str = std.mem.trim(u8, value[0..(value.len - 3)], " ");
                free_swap = try std.fmt.parseFloat(f64, free_swap_str.?);
            }
        }

        if ((total_swap_str != null) and (free_swap_str != null)) {
            break;
        }
    }

    var used_swap = total_swap - free_swap;

    // Converts KB in GB
    total_swap /= (1024 * 1024);
    used_swap /= (1024 * 1024);

    if (used_swap == 0) {
        return null;
    }

    const swap_usage_percentage: u8 = @as(u8, @intFromFloat((used_swap * 100) / total_swap));

    return SwapInfo{
        .swap_size = total_swap,
        .swap_usage = used_swap,
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
