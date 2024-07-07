const std = @import("std");
const root = @import("root.zig");
const builtin = @import("builtin");
const util = @import("util.zig");

const Compiler = @import("Compiler.zig");
const Downloader = @import("Downloader.zig");

const Options = struct {
    prefix: ?[]const u8 = null,
    arch: []const u8 = @tagName(builtin.cpu.arch),
    sys: []const u8 = @tagName(builtin.os.tag),
    version: ?[]const u8 = null,
    zig_root: ?[]const u8 = null,
};

const help =
    \\usage: zigman [OPTIONS...] [VERSION]
    \\
    \\Copyright (c) 2024 Andrij Glyko <nitrogenez.dev@tuta.io>. All rights reserved.
    \\This software is licensed under the 3-clause BSD license.
    \\
    \\OPTIONS:
    \\  [-p | --prefix PREFIX]      Zig will be installed in directories relative to PREFIX
    \\  [-i | --index]              Will fetch zig download index from ziglang.org and print it to stdout
    \\  [-a | --arch ARCHITECTURE]  Will fetch zig for ARCHITECTURE instead of native one
    \\  [-s | --system SYSTEM]      Will fetch zig for SYSTEM instead of native one
    \\  [-d | --directory DIR]      Will fetch zig compiler to DIR
    \\
    \\PREFIX: String, path that will be zig's root (e.g PREFIX = /home, then zig will be at /home/bin/zig, etc.)
    \\VERSION: String, can be omitted when using [-i | --index] option
    \\
    \\zigman has no affiliation with the Zig Language Foundation, Andrew Kelley, or any other
    \\Zig Language Foundation officials. zigman is purely a third-party tool
    \\for developers made with no bad intent.
;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var opts = Options{};
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();

    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, "--help", arg) or std.mem.eql(u8, "-h", arg)) {
            try stdout.print("{s}\n", .{help});
            return;
        } else if (std.mem.eql(u8, "--prefix", arg) or std.mem.eql(u8, "-p", arg)) {
            opts.prefix = args.next() orelse {
                std.log.err("--prefix requires value", .{});
                return;
            };
        } else if (std.mem.eql(u8, "--index", arg) or std.mem.eql(u8, "-i", arg)) {
            printIndex() catch |e| switch (e) {
                error.NotOpenForReading => {},
                else => {
                    std.log.err("index cannot be retrieved due to {s}", .{@errorName(e)});
                },
            };
            return;
        } else if (std.mem.eql(u8, "--arch", arg) or std.mem.eql(u8, "-a", arg)) {
            opts.arch = args.next() orelse {
                std.log.err("--arch requires value", .{});
                return;
            };
        } else if (std.mem.eql(u8, "--system", arg) or std.mem.eql(u8, "-s", arg)) {
            opts.sys = args.next() orelse {
                std.log.err("--system requires value", .{});
                return;
            };
        } else if (std.mem.eql(u8, "--directory", arg) or std.mem.eql(u8, "-d", arg)) {
            opts.zig_root = args.next() orelse {
                std.log.err("--directory requires value", .{});
                return;
            };
        } else {
            opts.version = arg;
        }
    }

    if (opts.version == null) {
        std.log.err("no version specified", .{});
        return;
    }

    if (!Compiler.isValidArch(opts.arch)) {
        std.log.err("{s} is not a valid architecture", .{opts.arch});
        return;
    }
    if (!Compiler.isValidSystemTag(opts.sys)) {
        std.log.err("{s} is not a valid system tag", .{opts.sys});
        return;
    }
    const r = opts.zig_root orelse try std.fs.path.join(util.gpa, &.{ std.posix.getenv("HOME") orelse unreachable, ".zigman", opts.version.? });
    try Compiler.download(r, opts.version.?, opts.arch, opts.sys);
}

fn printIndex() !void {
    const f = try root.fetchIndex();
    defer f.close();

    try f.seekTo(0);
    var buf: [1024 * 1024 * 2]u8 = undefined;
    std.debug.print("hi", .{});
    const bytes = try f.readAll(&buf);

    try std.io.getStdOut().writeAll(buf[0..bytes]);
    try std.io.getStdOut().writeAll("\n");
}

fn bToMib(b: usize) f64 {
    const in: f64 = @floatFromInt(b);
    return @divTrunc(in, (1024.0 * 1024.0));
}
