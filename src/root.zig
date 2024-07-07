const std = @import("std");

pub fn fetchIndexZ() !std.fs.File {
    const f = try std.fs.createFileAbsolute("/tmp/zigman.index.json", .{});
    try f.lock(.exclusive);
    defer f.unlock();
    try fetchIndexInternal(f.writer());
    return f;
}

pub fn fetchIndexW() !std.fs.File {
    const f = try std.fs.cwd().createFile("zigman.index.json", .{});
    try f.lock(.exclusive);
    defer f.unlock();
    try fetchIndexInternal(f.writer());
    return f;
}

pub fn fetchIndex() !std.fs.File {
    const tag = @import("builtin").os.tag;

    if (tag.isDarwin() or tag.isBSD() or tag.isSolarish() or tag == .linux) {
        return try fetchIndexZ();
    }
    return try fetchIndexW();
}

fn fetchIndexInternal(writer: anytype) !void {
    const uri = "https://ziglang.org/download/index.json";
    var headerbuf: [1024 * 4]u8 = undefined;
    var client = std.http.Client{ .allocator = std.heap.page_allocator };
    defer client.deinit();

    std.log.info("pulling download index from ziglang.org", .{});

    var conn = client.open(.GET, try std.Uri.parse(uri), .{ .server_header_buffer = &headerbuf, .headers = .{
        .user_agent = .{ .override = "zigman" },
        .accept_encoding = .{ .override = "utf-8" },
    } }) catch |e| {
        std.log.err("connection closed, reason: {s}", .{@errorName(e)});
        return;
    };
    defer conn.deinit();

    std.log.info("connection estabilished", .{});

    var rdbuf: [4096]u8 = undefined;
    var total: usize = 0;

    try conn.send();
    try conn.wait();

    const content_len: usize = @intCast(conn.response.content_length orelse 0);

    while (total != content_len) {
        const bytes = conn.read(&rdbuf) catch break;

        if (bytes == 0)
            break;
        total += try writer.write(rdbuf[0..bytes]);
    }
    try conn.finish();
}
