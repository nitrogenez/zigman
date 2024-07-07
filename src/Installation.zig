const std = @import("std");

pub const default_prefix = "/usr";
pub const default_zig_root = ".zig";
pub const zig_tarball_fmt = "zig-{1s}-{0s}-{2s}.tar.xz";
pub const zig_download_uri_fmt = "https://ziglang.org/download/{2s}/" ++ zig_tarball_fmt;

var download_finished: bool = false;
var bps: usize = 0;
var downloaded_bytes: usize = 0;

const Spinner = struct {
    frames: []const []const u8 = &.{ "◇ ", "◈ ", "◆ " },
    index: usize = 0,

    pub fn next(self: *Spinner) []const u8 {
        if (self.index >= self.frames.len) {
            self.index = 0;
        }
        const out = self.frames[self.index];
        self.index += 1;
        return out;
    }
};

arch: []const u8,
sys: []const u8,
version: []const u8,

pub fn fetch(self: *const @This(), prefix: ?[]const u8, zig_root: ?[]const u8) !void {
    var headerbuf: [1024 * 6]u8 = undefined;
    var uribuf: [512]u8 = undefined;
    var namebuf: [512]u8 = undefined;
    var rdbuf: [1024]u8 = undefined;
    var filenamebuf: [std.fs.max_path_bytes]u8 = undefined;
    var linknamebuf: [std.fs.max_path_bytes]u8 = undefined;

    _ = prefix;

    const uri = try std.fmt.bufPrint(&uribuf, zig_download_uri_fmt, .{ self.arch, self.sys, self.version });
    const name = try std.fmt.bufPrint(&namebuf, zig_tarball_fmt, .{ self.arch, self.sys, self.version });

    const root_path = try std.fs.path.join(std.heap.page_allocator, &.{
        std.posix.getenv("HOME") orelse unreachable,
        zig_root orelse default_zig_root,
    });
    const tarball_path = try std.fs.path.join(std.heap.page_allocator, &.{ root_path, name });

    var root_dir = try std.fs.openDirAbsolute(root_path, .{ .iterate = true });
    defer root_dir.close();

    std.fs.makeDirAbsolute(root_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const tarball_fd = try std.fs.createFileAbsolute(tarball_path, .{ .read = true });
    defer tarball_fd.close();

    defer std.heap.page_allocator.free(root_path);
    defer std.heap.page_allocator.free(tarball_path);

    var client = std.http.Client{ .allocator = std.heap.page_allocator };
    defer client.deinit();

    std.log.debug("fetch: estabilishing connection...", .{});

    var req = try client.open(.GET, try std.Uri.parse(uri), .{
        .server_header_buffer = &headerbuf,
        .headers = .{
            .accept_encoding = .{ .override = "utf-8" },
            .user_agent = .{ .override = "zigman" },
        },
    });
    defer req.deinit();

    try req.send();
    try req.wait();

    var recvd: usize = 0;
    const size: usize = @intCast(req.response.content_length orelse 0);

    std.log.debug("fetch: reading {d} bytes from connection...", .{size});

    var measure_thread = try std.Thread.spawn(.{}, measureBps, .{});
    var spinner = Spinner{ .frames = &.{
        "[    ]",
        "[=   ]",
        "[==  ]",
        "[=== ]",
        "[====]",
        "[ ===]",
        "[  ==]",
        "[   =]",
        "[    ]",
        "[   =]",
        "[  ==]",
        "[ ===]",
        "[====]",
        "[=== ]",
        "[==  ]",
        "[=   ]",
    } };
    var spinner_thread = try std.Thread.spawn(.{}, spinnerNext, .{&spinner});

    while (recvd != size) {
        const read = try req.read(&rdbuf);
        recvd += try tarball_fd.write(rdbuf[0..read]);
        downloaded_bytes = recvd;
        try std.io.getStdOut().writer().print("\r\x1b[0;32m{s}\x1b[0m \x1b[0;37m{s}\x1b[0m \x1b[0;36m{d:.2}/{d:.2} MiB \x1b[0;32m{d:.2} KiB/s\x1b[0m", .{
            spinner.frames[spinner.index],
            name,
            bToMib(recvd),
            bToMib(size),
            bToKib(bps),
        });
    }
    download_finished = true;

    measure_thread.join();
    spinner_thread.join();

    try req.finish();

    try std.io.getStdOut().writeAll("\n");

    std.log.debug("fetch: {d} bytes read, decompressing...", .{recvd});

    var decomp = try std.compress.xz.decompress(std.heap.page_allocator, tarball_fd.reader());
    defer decomp.deinit();

    const tar_path = tarball_path[0 .. std.mem.lastIndexOfScalar(u8, tarball_path, '.') orelse tarball_path.len];
    const tar_fd = try std.fs.createFileAbsolute(tar_path, .{});
    defer tar_fd.close();

    while (true) {
        const bytes = decomp.read(&rdbuf) catch break;
        try tar_fd.writeAll(rdbuf[0..bytes]);
    }

    var tar_it = std.tar.iterator(tar_fd.reader(), .{
        .file_name_buffer = &filenamebuf,
        .link_name_buffer = &linknamebuf,
    });

    std.log.debug("fetch: unwrapping tar...", .{});

    while (try tar_it.next()) |entry| {
        switch (entry.kind) {
            .directory => try root_dir.makePath(entry.name),
            .file => {
                const fd = try root_dir.createFile(entry.name, .{});
                while (entry.unread_bytes.* != 0) {
                    const bytes = entry.read(&rdbuf) catch break;
                    try fd.writeAll(rdbuf[0..bytes]);
                }
                fd.close();
            },
            else => {},
        }
    }
}

fn spinnerNext(spinner: *Spinner) void {
    while (!download_finished) {
        std.time.sleep(std.time.ns_per_ms * 80);

        if (spinner.index == spinner.frames.len - 1) {
            spinner.index = 0;
            continue;
        }
        spinner.index += 1;
    }
}

fn measureBps() void {
    while (!download_finished) {
        const start = downloaded_bytes;
        std.time.sleep(std.time.ns_per_s);
        const end = downloaded_bytes;
        bps = end - start;
    }
}

fn bToMib(b: usize) f64 {
    return @as(f64, @floatFromInt(b)) / (1024.0 * 1024.0);
}

fn bToKib(b: usize) f64 {
    return @as(f64, @floatFromInt(b)) / 1024.0;
}
