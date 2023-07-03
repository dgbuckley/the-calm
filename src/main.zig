const std = @import("std");
const assert = std.debug.assert;

const termbox = @import("termbox");

const Allocator = std.mem.Allocator;

const Chunk = @import("Chunk.zig");
const Window = @import("./Window.zig");

fn getmaxyx(y: *u16, x: *u16) void {
    var winsize: std.os.linux.winsize = undefined;
    _ = std.os.linux.ioctl(0, std.os.linux.T.IOCGWINSZ, @ptrToInt(&winsize));
    y.* = winsize.ws_row;
    x.* = winsize.ws_col;
    return;
}

pub fn main() !void {
    var t = try termbox.Termbox.init(std.heap.page_allocator);
    defer t.shutdown() catch {};

    try t.selectInputSettings(termbox.InputSettings{
        .mode = .Esc,
        .mouse = true,
    });

    var win = Window.init(t.term_h, t.term_w, &t);

    var rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.nanoTimestamp()));
    var chunk = try Chunk.init(std.heap.page_allocator, .{ .x = 0, .y = 0 }, rng.random());
    defer chunk.deinit(std.heap.page_allocator);

    for (chunk.rooms.items) |room| {
        try room.draw(&win);
    }

    try t.present();

    _ = try t.pollEvent();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
