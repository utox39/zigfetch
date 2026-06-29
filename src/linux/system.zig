const std = @import("std");
const utils = @import("../utils.zig");
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
    var uts: c.struct_utsname = undefined;
    if (c.uname(&uts) != 0) {
        return error.UnameFailed;
    }

    return KernelInfo{
        .kernel_name = try gpa.dupe(u8, std.mem.sliceTo(&uts.sysname, 0)),
        .kernel_release = try gpa.dupe(u8, std.mem.sliceTo(&uts.release, 0)),
    };
}

pub fn getOsInfo(gpa: std.mem.Allocator, io: std.Io) ![]u8 {
    const os_release_path = "/etc/os-release";
    const os_release_file = try std.Io.Dir.cwd().openFile(io, os_release_path, .{ .mode = .read_only });
    defer os_release_file.close(io);
    const size = (try os_release_file.stat(io)).size;
    const os_release_data = try utils.readFile(gpa, io, os_release_file, size);
    defer gpa.free(os_release_data);

    var pretty_name: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, os_release_data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "PRETTY_NAME")) {
            var parts = std.mem.splitScalar(u8, line, '=');
            _ = parts.next(); // discard the key
            if (parts.next()) |value| {
                pretty_name = std.mem.trim(u8, value, "\"");
                break;
            }
        }
    }

    return try gpa.dupe(u8, pretty_name orelse "Unknown");
}

pub fn getWindowManagerInfo(gpa: std.mem.Allocator, io: std.Io) ![]const u8 {
    var dir = try std.Io.Dir.cwd().openDir(io, "/proc/", .{ .iterate = true });
    defer dir.close(io);

    var wm_name: ?[]const u8 = null;

    var iter = dir.iterate();
    wm_name = outer: {
        while (try iter.next(io)) |entry| {
            if (entry.kind != .directory) continue;

            // Check if the entry name is numeric
            _ = std.fmt.parseInt(i32, entry.name, 10) catch continue;

            var buf: [1024]u8 = undefined;
            const file_name = try std.fmt.bufPrint(&buf, "/proc/{s}/comm", .{entry.name});
            const file = try std.Io.Dir.cwd().openFile(io, file_name, .{ .mode = .read_only });
            defer file.close(io);

            // NOTE: https://stackoverflow.com/questions/23534263/what-is-the-maximum-allowed-limit-on-the-length-of-a-process-name
            const proc_name = try utils.readFile(gpa, io, file, 16);
            defer gpa.free(proc_name);

            const proc_name_trimmed = std.mem.trim(u8, proc_name, "\n");

            const supported_wms: [9][]const u8 = .{
                "i3", // https://i3wm.org/
                // "i3gaps", // TODO: find a way to recognize i3gaps
                "sway", // https://swaywm.org/
                // "swayfx", // TODO: find a way to recognize swayfx
                "niri", // https://github.com/YaLTeR/niri
                "dwm", // https://dwm.suckless.org/
                // "qtile", // TODO: find a way to recognize qtile
                "awesome", // https://awesomewm.org/
                "river", // https://codeberg.org/river/river
                "hyprland", // https://hypr.land/
                "bspwm", // https://github.com/baskerville/bspwm
                "openbox", // https://openbox.org/
            };

            inline for (supported_wms) |wm| {
                if (std.ascii.eqlIgnoreCase(wm, proc_name_trimmed)) {
                    break :outer try gpa.dupe(u8, proc_name_trimmed);
                }
            }
        }

        break :outer null;
    };

    return wm_name orelse gpa.dupe(u8, "Unknown");
}
