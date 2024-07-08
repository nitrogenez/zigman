const std = @import("std");
const util = @import("util.zig");
const Downloader = @This();

path: []const u8 = "",
filename: []const u8 = "",
finished: bool = false,
size: ?usize = null,
downloaded: usize = 0,
spinner: util.Spinner = .{},
bar: util.ProgressBar = .{},
bytes_per_second: usize = 0,
update_rate: usize = 80,

pub fn download(url: []const u8, dir: []const u8) !Downloader {
    var ctx = @This(){
        .filename = std.fs.path.basename(url),
        .path = try std.fs.path.join(util.gpa, &.{ dir, std.fs.path.basename(url) }),
    };

    if (util.pathExists(ctx.path)) {
        try std.io.getStdOut().writer().print("Nothing left to download ({s} exists)\n", .{ctx.path});
        return ctx;
    }

    const uri = try std.Uri.parse(url);

    var client = std.http.Client{ .allocator = util.gpa };
    defer client.deinit();

    var headerbuf: [1024 * 8]u8 = undefined;
    var req = client.open(.GET, uri, .{ .server_header_buffer = &headerbuf, .headers = .{
        .user_agent = .{ .override = "zigman" },
        .accept_encoding = .{ .override = "utf-8" },
    } }) catch |err| {
        std.log.err("unable to connect to {s}: {s}", .{ url, @errorName(err) });
        return ctx;
    };
    defer req.deinit();

    try req.send();
    try req.wait();

    ctx.size = if (req.response.content_length) |cl| @intCast(cl) else null;

    var update_thread = try std.Thread.spawn(.{}, struct {
        fn func(c: *Downloader) !void {
            while (!c.finished) {
                std.time.sleep(std.time.ns_per_ms * c.update_rate);
                try c.update();
            }
        }
    }.func, .{&ctx});
    defer update_thread.join();

    var speed_measure_thread = try std.Thread.spawn(.{}, struct {
        fn func(c: *Downloader) !void {
            while (!c.finished) {
                std.time.sleep(std.time.ns_per_s);
                c.getSpeed();
            }
        }
    }.func, .{&ctx});
    defer speed_measure_thread.join();

    var rdbuf: [512]u8 = undefined;
    try std.fs.cwd().makePath(std.fs.path.dirname(ctx.path) orelse unreachable);
    const fd = try std.fs.cwd().createFile(ctx.path, .{});

    defer fd.close();

    if (ctx.size == null) {
        while (true) {
            const bytes = req.read(&rdbuf) catch break;

            if (bytes == 0) break;
            ctx.downloaded += try fd.write(rdbuf[0..bytes]);
        }
    } else {
        while (ctx.downloaded != ctx.size.?) {
            const bytes = req.read(&rdbuf) catch break;
            ctx.downloaded += try fd.write(rdbuf[0..bytes]);
        }
    }
    ctx.finished = true;
    return ctx;
}

fn update(self: *@This()) !void {
    const stdout = std.io.getStdOut().writer();

    self.spinner.step();

    self.bar.total = self.size orelse 0;
    self.bar.update(self.downloaded);

    const dl_units = Units.detect(self.downloaded);
    const downloaded = dl_units.to(self.downloaded);
    const total = dl_units.to(self.size orelse 0);

    const dl_speed_units = Units.detect(self.bytes_per_second);
    const dl_speed = dl_speed_units.to(self.bytes_per_second);

    const spinner_str = try util.color("green", if (self.finished) "[DONE]" else self.spinner.get());
    const progress_str = try util.colorFmt("cyan", "{d:.2}/{d:.2} {s}", .{ downloaded, total, @tagName(dl_units) });
    const speed_str = try util.colorFmt("red", "{d:.2} {s}/s", .{ dl_speed, @tagName(dl_speed_units) });
    const bar_str = try self.bar.getString();
    const full_str = try std.fmt.allocPrint(util.gpa, "\r{0s} {1s} {2s} {3s} {4s}", .{
        spinner_str,
        self.filename,
        progress_str,
        speed_str,
        bar_str,
    });

    defer util.gpa.free(spinner_str);
    defer util.gpa.free(progress_str);
    defer util.gpa.free(speed_str);
    defer util.gpa.free(bar_str);
    defer util.gpa.free(full_str);

    try stdout.writeAll(full_str);
    if (self.finished) try stdout.writeAll("\n");
}

fn getSpeed(ctx: *@This()) void {
    const start = ctx.downloaded;
    std.time.sleep(std.time.ns_per_s);
    ctx.bytes_per_second = ctx.downloaded - start;
}

const Units = enum(usize) {
    B = 0,
    KiB = 1024,
    MiB = 1048576,
    GiB = 1073741824,
    TiB = 1099511627776,

    pub fn detect(bytes: usize) Units {
        const kib = @intFromEnum(Units.KiB);
        const mib = @intFromEnum(Units.MiB);
        const gib = @intFromEnum(Units.GiB);
        const tib = @intFromEnum(Units.TiB);

        if (bytes <= kib) return .KiB;
        if (bytes >= kib and bytes < mib) return .KiB;
        if (bytes >= mib and bytes < gib) return .MiB;
        if (bytes >= gib and bytes < tib) return .GiB;
        if (bytes > gib) return .TiB;
        return .B;
    }

    pub fn to(self: Units, bytes: usize) f64 {
        const b: f64 = @floatFromInt(bytes);
        return if (self == .B) b else b / @as(f64, @floatFromInt(@intFromEnum(self)));
    }
};
