const std = @import("std");

pub const gpa = std.heap.page_allocator;

const Winsize = extern struct {
    ws_row: c_ushort,
    ws_col: c_ushort,
    ws_xpixel: c_ushort,
    ws_ypixel: c_ushort,
};

pub fn pathExists(path: []const u8) bool {
    const f = std.fs.cwd().createFile(path, .{ .exclusive = true }) catch |e| switch (e) {
        error.PathAlreadyExists => return true,
        else => return false,
    };
    f.close();
    return true;
}

pub fn getScreenWidth(stdout: std.posix.fd_t) usize {
    var winsize: Winsize = undefined;
    _ = std.os.linux.ioctl(stdout, 0x5413, @intFromPtr(&winsize));
    return @intCast(winsize.ws_col);
}

pub const Spinner = struct {
    frames: []const []const u8 = &.{ "[=  ]", "[ = ]", "[  =]", "[  =]", "[ = ]", "[=  ]" },
    pos: usize = 0,

    pub fn step(self: *Spinner) void {
        if (self.pos == self.frames.len - 1) {
            self.pos = 0;
            return;
        }
        self.pos += 1;
    }

    pub fn get(self: *Spinner) []const u8 {
        return self.frames[self.pos];
    }

    pub fn next(self: *Spinner) []const u8 {
        const out = self.get();
        self.step();
        return out;
    }
};

pub const ProgressBar = struct {
    open: []const u8 = "[",
    close: []const u8 = "]",
    empty_slot: []const u8 = " ",
    full_slot: []const u8 = "|",
    caret_slot: []const u8 = "|",
    total: usize = 0,
    complete: usize = 0,
    progress: f64 = 0.0,
    width: usize = 20,

    pub fn getPercent(total: usize, complete: usize) f64 {
        const t: f64 = @floatFromInt(total);
        const c: f64 = @floatFromInt(complete);
        return c / t;
    }

    pub fn update(self: *ProgressBar, complete: usize) void {
        self.complete = complete;
        self.progress = getPercent(self.total, self.complete);
    }

    pub fn getString(self: *ProgressBar) ![]const u8 {
        var buf = std.ArrayList(u8).init(std.heap.page_allocator);
        try self.writeString(buf.writer());
        return buf.toOwnedSlice();
    }

    pub fn writeString(self: *ProgressBar, writer: anytype) !void {
        const pos: usize = @intFromFloat(@as(f64, @floatFromInt(self.width)) * self.progress);

        try writer.writeAll(self.open);

        for (0..self.width) |i| {
            if (i < pos) {
                try writer.writeAll(self.full_slot);
            } else if (i == pos) {
                try writer.writeAll(self.caret_slot);
            } else {
                try writer.writeAll(self.empty_slot);
            }
        }
        try writer.writeAll(self.close);
    }
};

pub const colors = std.StaticStringMap([]const u8).initComptime(.{
    .{ "red", "\x1b[0;31m" },
    .{ "green", "\x1b[0;32m" },
    .{ "blue", "\x1b[0;34m" },
    .{ "magenta", "\x1b[0;35m" },
    .{ "cyan", "\x1b[0;36m" },
    .{ "default", "\x1b[0m" },
});

pub fn canColorize() bool {
    if (std.posix.getenv("NO_COLOR")) |v|
        return v[0] == '1';
    return true;
}

pub fn color(name: []const u8, s: []const u8) ![]const u8 {
    if (!canColorize())
        return s;

    return try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{
        colors.get(name) orelse colors.get("default").?,
        s,
        colors.get("default").?,
    });
}

pub fn colorFmt(name: []const u8, comptime fmt: []const u8, args: anytype) ![]const u8 {
    if (!canColorize())
        return try std.fmt.allocPrint(gpa, fmt, args);
    return try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{
        colors.get(name) orelse colors.get("default").?,
        try std.fmt.allocPrint(gpa, fmt, args),
        colors.get("default").?,
    });
}
