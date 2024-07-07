const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");
const Downloader = @import("Downloader.zig");

const host_arch = @tagName(builtin.cpu.arch);
const host_sys = @tagName(builtin.os.tag);

pub fn getDownloadUri(version: []const u8, arch: ?[]const u8, sys: ?[]const u8) ![]const u8 {
    const uri_base = "https://ziglang.org/download/{0s}/zig-{2s}-{1s}-{0s}.tar.xz";
    return try std.fmt.allocPrint(util.gpa, uri_base, .{ version, arch orelse host_arch, sys orelse host_sys });
}

pub fn download(root: []const u8, version: []const u8, arch: ?[]const u8, sys: ?[]const u8) !void {
    const uri = try getDownloadUri(version, arch, sys);
    const dl = try Downloader.download(uri, root);
    try std.io.getStdOut().writeAll("\n");
    try unpack(dl.path);
    util.gpa.free(dl.path);
    try std.io.getStdOut().writeAll("\n");
}

pub fn unpack(path: []const u8) !void {
    const f = try std.fs.openFileAbsolute(path, .{});
    defer f.close();

    const Ctx = struct {
        unpacked: bool = false,
        dots: util.Spinner = .{ .frames = &.{ "*  ", "** ", "***" } },
        spinner: util.Spinner = .{ .frames = &.{ "[>  ]", "[ > ]", "[  >]", "[  <]", "[ < ]", "[<  ]" } },
    };
    var ctx = Ctx{};

    const out_path = path[0 .. std.mem.lastIndexOf(u8, path, ".tar.xz") orelse path.len];
    std.fs.makeDirAbsolute(out_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const out_dir = try std.fs.openDirAbsolute(out_path, .{ .iterate = true });

    var notif_thread = try std.Thread.spawn(.{}, struct {
        fn func(c: *Ctx) void {
            while (!c.unpacked) {
                std.time.sleep(std.time.ns_per_ms * 80);
                const spinner_str = util.color("green", c.spinner.next()) catch @panic("OOM");
                defer util.gpa.free(spinner_str);
                std.io.getStdOut().writer().print("\r{s} Unpacking {s}", .{ spinner_str, c.dots.next() }) catch unreachable;
            }
        }
    }.func, .{&ctx});
    defer notif_thread.join();

    var br = std.io.bufferedReaderSize(std.crypto.tls.max_ciphertext_record_len, f.reader());
    var decomp = try std.compress.xz.decompress(util.gpa, br.reader());
    defer decomp.deinit();

    try std.tar.pipeToFileSystem(out_dir, decomp.reader(), .{ .mode_mode = .ignore, .exclude_empty_directories = true });
    ctx.unpacked = true;
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
