const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");
const dl = @import("download.zig");

const host_arch = @tagName(builtin.cpu.arch);
const host_sys = @tagName(builtin.os.tag);
const download_url = "https://ziglang.org/download/{0s}/zig-{1s}-{2s}-{0s}.tar.xz";

pub fn get(prefix: []const u8, root: []const u8, version: []const u8, arch: ?[]const u8, sys: ?[]const u8) !void {
    const a = arch orelse host_arch;
    const s = sys orelse host_sys;

    if (!isValidArch(a)) {
        std.log.err("Invalid architecture: {s}", .{a});
        return;
    }

    if (!isValidSystemTag(s)) {
        std.log.err("Invalid system tag: {s}", .{s});
        return;
    }

    if (!isValidVersion(version)) {
        std.log.err("Invalid version: {s}", .{version});
        return;
    }

    const uri = try std.fmt.allocPrint(util.gpa, download_url, .{
        version,
        sys orelse host_sys,
        arch orelse host_arch,
    });

    const path = try dl.fetch(util.gpa, uri, root);
    const unpacked = try unpack(path);
    const done = try util.colorFmt("green", "Zig v{s} has been installed on your system\n", .{version});

    try install(prefix, unpacked);

    defer {
        util.gpa.free(uri);
        util.gpa.free(path);
        util.gpa.free(unpacked);
        util.gpa.free(done);
    }
    try std.io.getStdOut().writeAll(done);
}

pub fn unpack(path: []const u8) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var falloc = std.heap.FixedBufferAllocator.init(&buf);

    const f = std.fs.openFileAbsolute(path, .{}) catch |err| {
        std.log.err("Unable to unpack {s}: {s}", .{ path, @errorName(err) });
        return err;
    };
    defer f.close();

    const Ctx = struct {
        unpacked: bool = false,
        dots: util.Spinner = .{ .frames = &.{ "∙∙∙", "●∙∙", "∙●∙", "∙∙●", "∙∙∙" } },
        spinner: util.Spinner = .{ .frames = &.{ "[-  ]", "[ = ]", "[  -]", "[ = ]" } },
    };
    var ctx = Ctx{};

    const out_path = std.fs.path.dirname(path) orelse unreachable;
    const unpacked_dir = try std.fs.path.join(falloc.allocator(), &.{
        out_path,
        std.fs.path.stem(path[0 .. std.mem.lastIndexOfScalar(u8, path, '.') orelse path.len]),
    });

    std.debug.print("out_path: {s}\nunpacked_dir: {s}\n", .{ out_path, unpacked_dir });

    if (util.pathExists(unpacked_dir)) {
        std.log.warn("{s} already exists", .{unpacked_dir});
        return util.gpa.dupe(u8, unpacked_dir);
    }

    std.fs.makeDirAbsolute(out_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const out_dir = try std.fs.openDirAbsolute(out_path, .{ .iterate = true });

    var notif_thread = try std.Thread.spawn(.{}, struct {
        fn func(c: *Ctx) void {
            while (!c.unpacked) {
                std.time.sleep(std.time.ns_per_ms * 80);
                const spinner_str = util.color("green", if (c.unpacked) "[DONE]" else c.spinner.next()) catch @panic("OOM");
                defer util.gpa.free(spinner_str);
                std.io.getStdOut().writer().print("\r{s} Unpacking (this might take some time) {s}", .{
                    spinner_str,
                    if (c.unpacked) "\n" else c.dots.next(),
                }) catch unreachable;
            }
        }
    }.func, .{&ctx});
    defer notif_thread.join();

    var br = std.io.bufferedReaderSize(std.crypto.tls.max_ciphertext_record_len, f.reader());
    var decomp = try std.compress.xz.decompress(util.gpa, br.reader());
    defer decomp.deinit();

    try std.tar.pipeToFileSystem(out_dir, decomp.reader(), .{ .mode_mode = .ignore, .exclude_empty_directories = true });
    ctx.unpacked = true;

    return try util.gpa.dupe(u8, unpacked_dir);
}

pub fn install(prefix: []const u8, unpacked_path: []const u8) !void {
    const zig_exe_path = try std.fs.path.join(util.gpa, &.{ unpacked_path, "zig" });
    const zig_installed_exe_path = try std.fs.path.join(util.gpa, &.{ prefix, "bin", "zig" });

    defer util.gpa.free(zig_exe_path);
    defer util.gpa.free(zig_installed_exe_path);

    std.fs.symLinkAbsolute(zig_exe_path, zig_installed_exe_path, .{ .is_directory = false }) catch |err| switch (err) {
        error.AccessDenied => {
            std.log.err("unable to symlink {s} to {s}: AccessDenied", .{ zig_exe_path, zig_installed_exe_path });
            return;
        },
        error.PathAlreadyExists => try overwriteSymlink(zig_exe_path, zig_installed_exe_path),
        else => return err,
    };

    const tag = @import("builtin").os.tag;
    if (tag == .windows) return;

    const symlink_fd = try std.fs.openFileAbsolute(zig_installed_exe_path, .{});
    try symlink_fd.chmod(700);
    symlink_fd.close();

    const exe_fd = try std.fs.openFileAbsolute(zig_exe_path, .{});
    try exe_fd.chmod(700);
    exe_fd.close();
}

fn overwriteSymlink(path: []const u8, to: []const u8) !void {
    std.fs.deleteFileAbsolute(to) catch |err| switch (err) {
        error.AccessDenied => {
            std.log.err("unable to overwrite symlink {s}: AccessDenied", .{to});
        },
        else => return err,
    };
    std.fs.symLinkAbsolute(path, to, .{ .is_directory = false }) catch |err| switch (err) {
        error.AccessDenied => {
            std.log.err("unable to symlink {s} to {s}: AccessDenied", .{ path, to });
            return;
        },
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn isValidArch(s: []const u8) bool {
    inline for (std.meta.fieldNames(std.Target.Cpu.Arch)) |name| if (std.mem.eql(u8, name, s)) return true;
    return false;
}

pub fn isValidSystemTag(s: []const u8) bool {
    inline for (std.meta.fieldNames(std.Target.Os.Tag)) |name| if (std.mem.eql(u8, name, s)) return true;
    return false;
}

pub fn isValid(arch: []const u8, sys: []const u8) bool {
    return isValidArch(arch) and isValidSystemTag(sys);
}

pub fn isValidVersion(s: []const u8) bool {
    _ = std.SemanticVersion.parse(s) catch return false;
    return true;
}
