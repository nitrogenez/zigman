const std = @import("std");
const util = @import("util.zig");
const dl = @import("download.zig");

pub const url = "https://ziglang.org/download/index.json";

// TODO: Parsing using std.json.Scanner
// FIXME: I HAVE ASKED YOU EVERY TIME YOU WENT HERE TO DO FUCKING PARSING WHY IS IT NOT DONE YET

pub fn fetch() !void {
    std.log.debug("fetching index...", .{});

    var headerbuf: [1024 * 8]u8 = undefined;
    var client = std.http.Client{ .allocator = util.gpa };
    defer client.deinit();

    var request = try client.open(.GET, try std.Uri.parse(url), .{
        .server_header_buffer = &headerbuf,
        .headers = .{ .user_agent = .{ .override = "zigman" } },
    });
    defer request.deinit();

    try request.send();
    try request.wait();

    var rdbuf: [1024]u8 = undefined;
    var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());

    while (true) {
        const bytes = try request.read(&rdbuf);

        if (bytes == 0)
            break;
        _ = try stdout.write(rdbuf[0..bytes]);
    }
    _ = try stdout.write("\n");
    try stdout.flush();
}
