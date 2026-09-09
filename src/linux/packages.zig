const std = @import("std");
const utils = @import("../utils.zig");
const build_options = @import("build_options");
const c = @import("c");

pub fn getPackagesInfo(gpa: std.mem.Allocator, io: std.Io, environ: std.process.Environ) ![]const u8 {
    var packages_info = std.array_list.Managed(u8).init(gpa);
    defer packages_info.deinit();

    const flatpak_packages = countFlatpakPackages(io) catch |err| if (err == error.FileNotFound) 0 else return err;
    const nix_packages = countNixPackages(gpa, io, environ) catch 0;
    const dpkg_packages = countDpkgPackages(gpa, io) catch |err| if (err == error.FileNotFound) 0 else return err;
    const pacman_packages = countPacmanPackages(io) catch |err| if (err == error.FileNotFound) 0 else return err;
    const xbps_packages = countXbpsPackages(gpa, io) catch |err| if (err == error.FileNotFound) 0 else return err;
    // If sqlite fails it fallback to librpm.
    // Inspired by: https://github.com/fastfetch-cli/fastfetch/blob/5d290cc3d5c61ee23f7f1ffa04e54c18254984af/src/detection/packages/packages_linux.c#L649
    //
    // Errors from `countRpmPackagesViaSqlite` are ignored for now
    const rpm_packages = countRpmPackagesViaSqlite("/var/lib/rpm/rpmdb.sqlite") catch countRpmPackagesViaLibrpm();

    var buffer: [32]u8 = undefined;

    if (nix_packages > 0) {
        try packages_info.appendSlice(try std.fmt.bufPrint(&buffer, " Nix: {d}", .{nix_packages}));
    }

    if (flatpak_packages > 0) {
        try packages_info.appendSlice(try std.fmt.bufPrint(&buffer, " Flatpak: {d}", .{flatpak_packages}));
    }

    if (dpkg_packages > 0) {
        try packages_info.appendSlice(try std.fmt.bufPrint(&buffer, " Dpkg: {d}", .{dpkg_packages}));
    }

    if (pacman_packages > 0) {
        try packages_info.appendSlice(try std.fmt.bufPrint(&buffer, " Pacman: {d}", .{pacman_packages}));
    }

    if (xbps_packages > 0) {
        try packages_info.appendSlice(try std.fmt.bufPrint(&buffer, " Xbps: {d}", .{xbps_packages}));
    }

    if (rpm_packages > 0) {
        try packages_info.appendSlice(try std.fmt.bufPrint(&buffer, " RPM: {d}", .{rpm_packages}));
    }

    return try gpa.dupe(u8, packages_info.items);
}

fn countFlatpakPackages(io: std.Io) !usize {
    const flatpak_apps = try countFlatpakApps(io);
    const flatpak_runtimes = try countFlatpakRuntimes(io);

    return flatpak_apps + flatpak_runtimes;
}

fn countFlatpakApps(io: std.Io) !usize {
    var dir = try std.Io.Dir.openDirAbsolute(io, "/var/lib/flatpak/app/", .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();

    var count: usize = 0;

    while (try iter.next(io)) |e| {
        if (e.kind != .directory) continue;

        var sub_dir = try dir.openDir(io, e.name, .{});
        defer sub_dir.close(io);

        var current = sub_dir.openDir(io, "current", .{}) catch continue;
        defer current.close(io);

        // If `current` was opened successfully, increment the count
        count += 1;
    }

    return count;
}

fn countFlatpakRuntimes(io: std.Io) !usize {
    var dir = try std.Io.Dir.openDirAbsolute(io, "/var/lib/flatpak/runtime/", .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();

    var counter: usize = 0;

    while (try iter.next(io)) |e| {
        if (std.mem.endsWith(u8, e.name, ".Locale") or std.mem.endsWith(u8, e.name, ".Debug")) continue;

        var arch_dir = try dir.openDir(io, e.name, .{ .iterate = true });
        defer arch_dir.close(io);
        var arch_iter = arch_dir.iterate();
        while (try arch_iter.next(io)) |arch_e| {
            if (arch_e.kind != .directory) continue;

            var sub_dir = try arch_dir.openDir(io, arch_e.name, .{ .iterate = true });
            defer sub_dir.close(io);
            var sub_iter = sub_dir.iterate();
            while (try sub_iter.next(io)) |_| {
                counter += 1;
            }
        }
    }

    return counter;
}

fn countNixPackages(gpa: std.mem.Allocator, io: std.Io, environ: std.process.Environ) !usize {
    // `/run/current-system` is a sym-link, so we need to obtein the real path
    const real_path = try std.Io.Dir.realPathFileAbsoluteAlloc(io, "/run/current-system", gpa);
    defer gpa.free(real_path);

    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(real_path, &hash, .{});
    const hash_hex = try std.fmt.allocPrint(gpa, "{x}", .{hash});
    defer gpa.free(hash_hex);

    var count: usize = 0;

    // Inspired by https://github.com/fastfetch-cli/fastfetch/blob/608382109cda6623e53f318e8aced54cf8e5a042/src/detection/packages/packages_nix.c#L81
    count = checkNixCache(gpa, io, environ, hash_hex) catch |err| switch (err) {
        error.FileNotFound, error.InvalidCache => {
            // nix-store --query --requisites /run/current-system | wc -l
            const result = try std.process.run(gpa, io, .{ .argv = &[_][]const u8{
                "sh",
                "-c",
                "nix-store --query --requisites /run/current-system | wc -l",
            } });

            const result_trimmed = std.mem.trim(u8, result.stdout, "\n");
            defer gpa.free(result.stdout);
            defer gpa.free(result.stderr);

            count = try std.fmt.parseInt(usize, result_trimmed, 10);

            try writeNixCache(gpa, io, environ, hash_hex, count);

            return count;
        },
        else => return err,
    };

    return count;
}

fn getNixCachePath(gpa: std.mem.Allocator, environ: std.process.Environ) ![]const u8 {
    const cache_dir_path = try getUnixCachePath(gpa, environ);
    defer gpa.free(cache_dir_path);
    return try std.fs.path.join(gpa, &.{ cache_dir_path, "zigfetch", "nix" });
}

fn getUnixCachePath(gpa: std.mem.Allocator, environ: std.process.Environ) ![]const u8 {
    var cache_dir_path = std.process.Environ.getAlloc(environ, gpa, "XDG_CACHE_HOME") catch try gpa.dupe(u8, "");
    if (cache_dir_path.len == 0) {
        gpa.free(cache_dir_path);
        const home = try std.process.Environ.getAlloc(environ, gpa, "HOME");
        defer gpa.free(home);
        cache_dir_path = try std.fs.path.join(gpa, &.{ home, ".cache" });
    }

    return cache_dir_path;
}

fn writeNixCache(gpa: std.mem.Allocator, io: std.Io, environ: std.process.Environ, hash: []const u8, count: usize) !void {
    const nix_cache_dir_path = try getNixCachePath(gpa, environ);
    defer gpa.free(nix_cache_dir_path);

    std.Io.Dir.accessAbsolute(io, nix_cache_dir_path, .{ .read = true }) catch {
        const cache_dir_path = try getUnixCachePath(gpa, environ);
        defer gpa.free(cache_dir_path);

        const cache_dir = try std.Io.Dir.openDirAbsolute(io, cache_dir_path, .{});
        try cache_dir.createDirPath(io, "zigfetch/nix");
    };

    var nix_cache_dir = try std.Io.Dir.openDirAbsolute(io, nix_cache_dir_path, .{});
    defer nix_cache_dir.close(io);
    var cache_file = try nix_cache_dir.createFile(io, "nix_cache", .{ .truncate = true });
    defer cache_file.close(io);

    const cache_content = try std.fmt.allocPrint(gpa, "{s}\n{d}\n", .{ hash, count });
    defer gpa.free(cache_content);
    try cache_file.writePositionalAll(io, cache_content, 0);
}

fn checkNixCache(gpa: std.mem.Allocator, io: std.Io, environ: std.process.Environ, hash: []const u8) !usize {
    const cache_dir_path = try getNixCachePath(gpa, environ);
    defer gpa.free(cache_dir_path);
    var cache_dir = try std.Io.Dir.openDirAbsolute(io, cache_dir_path, .{});
    defer cache_dir.close(io);

    var cache_file = try cache_dir.openFile(io, "nix_cache", .{ .mode = .read_only });
    defer cache_file.close(io);
    const cache_size = (try cache_file.stat(io)).size;
    const cache_content = try utils.readFile(gpa, io, cache_file, cache_size);
    defer gpa.free(cache_content);

    var cache_iter = std.mem.splitScalar(u8, cache_content, '\n');

    const hash_needle = cache_iter.next().?;
    if (!std.mem.eql(u8, hash, hash_needle)) {
        return error.InvalidCache;
    }

    // The next element in the split is the package count
    return std.fmt.parseInt(usize, cache_iter.next().?, 10);
}

fn countDpkgPackages(gpa: std.mem.Allocator, io: std.Io) !usize {
    const dpkg_status_path = "/var/lib/dpkg/status";
    const dpkg_file = try std.Io.Dir.openFileAbsolute(io, dpkg_status_path, .{ .mode = .read_only });
    defer dpkg_file.close(io);
    const file_size = (try dpkg_file.stat(io)).size;

    const content = try utils.readFile(gpa, io, dpkg_file, file_size);
    defer gpa.free(content);

    var count: usize = 0;
    var iter = std.mem.splitSequence(u8, content, "\n\n");
    // TODO: find a way to avoid this loop
    while (iter.next()) |_| {
        count += 1;
    }

    // Subtruct 1 to remove an useless line
    return count - 1;
}

fn countPacmanPackages(io: std.Io) !usize {
    // Subtruct 1 to remove `ALPM_DB_VERSION` from the count
    return try utils.countEntries(io, "/var/lib/pacman/local") - 1;
}

fn countXbpsPackages(gpa: std.mem.Allocator, io: std.Io) !usize {
    var dir = try std.Io.Dir.openDirAbsolute(io, "/var/db/xbps/", .{ .iterate = true });
    defer dir.close(io);

    var count: usize = 0;

    var dir_iter = dir.iterate();

    while (try dir_iter.next(io)) |e| {
        if ((e.kind == .file) and std.mem.startsWith(u8, e.name, "pkgdb-")) {
            const pkgdb_file = try dir.openFile(io, e.name, .{ .mode = .read_only });
            defer pkgdb_file.close(io);
            const file_size = (try pkgdb_file.stat(io)).size;

            const content = try utils.readFile(gpa, io, pkgdb_file, file_size);
            defer gpa.free(content);

            var file_iter = std.mem.splitSequence(u8, content, "<string>installed</string>");
            // TODO: find a way to avoid this loop
            while (file_iter.next()) |_| {
                count += 1;
            }

            break;
        }
    }

    // Subtruct 1 to remove an useless line
    return count - 1;
}

// Inspired by: https://github.com/fastfetch-cli/fastfetch/blob/5d290cc3d5c61ee23f7f1ffa04e54c18254984af/src/detection/packages/packages_linux.c#L188
fn countRpmPackagesViaLibrpm() usize {
    if (build_options.enable_rpm) {
        // Don't print any error messages
        //
        // rpmlogSetMask(RPMLOG_MASK(RPMLOG_EMERG));
        //
        // #define RPMLOG_MASK(pri) (1 << ((unsigned)(pri)))
        //
        _ = c.rpmlogSetMask(1 << @as(usize, @intCast(c.RPMLOG_EMERG)));

        if (c.rpmReadConfigFiles(null, null) != 0) {
            return 0;
        }

        const ts: c.rpmts = c.rpmtsCreate();
        if (ts == null) {
            return 0;
        }

        const match_iter: c.rpmdbMatchIterator = c.rpmtsInitIterator(ts, c.RPMDBI_LABEL, null, 0);
        if (match_iter == null) {
            _ = c.rpmtsFree(ts);
            return 0;
        }

        const count: usize = @intCast(c.rpmdbGetIteratorCount(match_iter));

        _ = c.rpmdbFreeIterator(match_iter);
        _ = c.rpmtsFree(ts);

        return count;
    }

    return 0;
}

fn countRpmPackagesViaSqlite(path: []const u8) !usize {
    if (build_options.enable_rpm) {
        var db_connection: ?*c.sqlite3 = undefined;
        if (c.sqlite3_open(path.ptr, &db_connection) != c.SQLITE_OK) {
            // std.log.err("Can't open database {s}: {s}\n", .{ path, c.sqlite3_errmsg(db_connection) });
            return error.FailedToOpenTheRpmDB;
        }
        defer _ = c.sqlite3_close(db_connection);

        const query =
            \\ SELECT COUNT(*) FROM Sigmd5;
        ;

        var stmt: ?*c.sqlite3_stmt = undefined;
        if (c.sqlite3_prepare_v2(db_connection, query, @as(c_int, @intCast(query.len + 1)), &stmt, null) != c.SQLITE_OK) {
            // std.log.err("Can't create prepared statement: {s}\n", .{c.sqlite3_errmsg(db_connection)});
            return error.FailedToPrepareTheStatementForTheRpmDB;
        }
        defer _ = c.sqlite3_finalize(stmt);

        var count: usize = 0;
        var rc = c.sqlite3_step(stmt);
        while (rc == c.SQLITE_ROW) : (rc = c.sqlite3_step(stmt)) {
            count = @as(usize, @intCast(c.sqlite3_column_int(stmt, 0)));
        } else if (rc != c.SQLITE_DONE) {
            // std.log.err("Failed to get row: {s}\n", .{c.sqlite3_errmsg(db_connection)});
            return error.FailedToGetRpmPackagesCount;
        }

        return count;
    }

    return 0;
}
