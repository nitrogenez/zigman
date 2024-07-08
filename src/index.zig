const std = @import("std");
const util = @import("util.zig");
const Downloader = @import("Downloader.zig");

pub const url = "https://ziglang.org/download/index.json";

// TODO: Parsing using std.json.Scanner

pub fn fetch(zig_root: []const u8) !void {
    const dl = try Downloader.download(url, zig_root);
    path = dl.path;
}

pub fn print() !void {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    var buf: [1024 * 1024 * 2]u8 = undefined;
    const bytes = try f.read(&buf);

    try std.io.getStdOut().writer().print("{s}\n", .{buf[0..bytes]});
    util.gpa.free(path);
}

var path: []const u8 = "";
