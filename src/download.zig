const std = @import("std");
const util = @import("util.zig");

const Context = struct {
    fps: usize = 80,
    bps: usize = 0,
    size: usize = 0,
    total: ?usize = null,
    finished: bool = false,
};

/// Returns path to the downloaded object.
/// Caller owns the memory.
pub fn fetch(gpa: std.mem.Allocator, url: []const u8, out_dir: []const u8) ![]const u8 {
    var ctx = Context{};
    var header_buf: [1024 * 6]u8 = undefined;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var falloc = std.heap.FixedBufferAllocator.init(&buf);
    var spinner = util.Spinner{};
    var bar = util.ProgressBar{};

    const name = std.fs.path.basename(url);
    const path = try std.fs.path.join(falloc.allocator(), &.{ out_dir, name });

    if (util.pathExists(path)) {
        std.log.warn("{s} already exists", .{path});
        return try util.gpa.dupe(u8, path);
    }
    var client = std.http.Client{ .allocator = gpa };
    defer client.deinit();

    var request = try client.open(.GET, try std.Uri.parse(url), .{
        .server_header_buffer = &header_buf,
        .headers = .{ .user_agent = .{ .override = "zigman" } },
    });
    defer request.deinit();

    try request.send();
    try request.wait();

    ctx.total = if (request.response.content_length) |cl| @intCast(cl) else null;

    var refresh_thread = try std.Thread.spawn(.{}, update, .{ &ctx, &spinner, &bar, name });
    var measure_thread = try std.Thread.spawn(.{}, measure, .{&ctx});

    defer {
        refresh_thread.join();
        measure_thread.join();
    }

    try std.fs.cwd().makePath(out_dir);
    const fd = try std.fs.cwd().createFile(path, .{});
    defer fd.close();

    try readTo(&ctx, request.reader(), fd.writer());

    ctx.finished = true;
    return try gpa.dupe(u8, path);
}

fn readTo(ctx: *Context, in: anytype, out: anytype) !void {
    var buf: [2048]u8 = undefined;

    while (if (ctx.total) |total| total != ctx.size else true) {
        const bytes = in.read(&buf) catch break;
        if (bytes == 0) break;
        ctx.size += try out.write(buf[0..bytes]);
    }
}

fn update(ctx: *Context, spinner: *util.Spinner, bar: *util.ProgressBar, name: []const u8) !void {
    while (!ctx.finished) {
        std.time.sleep(std.time.ns_per_ms * ctx.fps);
        spinner.step();

        bar.total = ctx.total orelse 0;
        bar.update(ctx.size);

        const stdout = std.io.getStdOut().writer();
        const dps = util.DataUnits.adapt(ctx.bps);
        const size = util.DataUnits.adapt(ctx.size);
        const total = util.DataUnits.adapt(ctx.total orelse 0);

        const speed = try util.colorFmt("cyan", "{d:.2} {s}/s", .{ dps, @tagName(util.DataUnits.detect(ctx.bps)) });
        const s = try util.color("green", spinner.get());
        const b = try bar.getString();
        const p = try util.colorFmt("red", "{d:.2}/{d:.2} {s}", .{ size, total, @tagName(util.DataUnits.detect(ctx.size)) });

        defer {
            util.gpa.free(speed);
            util.gpa.free(s);
            util.gpa.free(b);
            util.gpa.free(p);
        }

        try stdout.print("\r{0s} {1s} {2s} {3s} {4s}", .{ s, name, p, speed, b });
        if (ctx.finished) try stdout.writeByte('\n');
    }
}

fn measure(ctx: *Context) void {
    while (!ctx.finished) {
        const start = ctx.size;
        std.time.sleep(std.time.ns_per_s);
        ctx.bps = ctx.size - start;
    }
}
