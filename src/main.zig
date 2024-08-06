const std = @import("std");
const util = @import("util.zig");
const clap = @import("clap");
const index = @import("index.zig");
const compiler = @import("compiler.zig");

const help =
    \\-h, --help          Show this message and exit
    \\-p, --prefix <DIR>  Install the Zig toolchain relative to DIR
    \\-i, --index         Fetch and print the Zig toolchain download index and exit
    \\-a, --arch   <ARCH> Fetch the Zig toolchain for ARCH architecture
    \\-s, --system <SYS>  Fetch the Zig toolchain for SYS system
    \\-d, --dir    <DIR>  Fetch the Zig toolchain into DIR directory
    \\<VERSION>
;

pub fn main() !void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var falloc = std.heap.FixedBufferAllocator.init(&buf);

    if (@import("secret.zig").getAManAfterMidnight() != null) return;

    const params = comptime clap.parseParamsComptime(help);
    const parsers = comptime .{
        .DIR = clap.parsers.string,
        .ARCH = clap.parsers.string,
        .SYS = clap.parsers.string,
        .VERSION = clap.parsers.string,
    };

    var clap_diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &clap_diag,
        .allocator = util.gpa,
    }) catch |err| {
        clap_diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try printHelp();
        return;
    }

    if (res.args.index != 0) {
        try index.fetch();
        return;
    }

    if (res.positionals.len < 1) {
        std.log.err("no version specified", .{});
        return;
    }

    const root = res.args.dir orelse try std.fs.path.join(falloc.allocator(), &.{
        std.posix.getenv("HOME") orelse unreachable,
        ".zigman",
        res.positionals[0],
    });
    try compiler.get(res.args.prefix orelse "/usr", root, res.positionals[0], res.args.arch, res.args.system);
}

fn printHelp() !void {
    var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());

    _ = try stdout.write("Copyright (c) 2024 Andrij Glyko. All rights reserved.\n");
    _ = try stdout.write("This software is licensed under the 3-Clause BSD License.\n");
    _ = try stdout.write("\nusage: zigman [OPIONS...] VERSION\n\n");
    _ = try stdout.write(help);
    _ = try stdout.write("\n\n");
    _ = try stdout.write(@import("secret.zig").get());
    _ = try stdout.write("\n");

    try stdout.flush();
}
