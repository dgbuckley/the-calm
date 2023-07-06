const std = @import("std");
const assert = std.debug.assert;

const termbox = @import("termbox");

const Allocator = std.mem.Allocator;

const Chunk = @import("Chunk.zig");
const Context = @import("./ui.zig").Context;
const Window = @import("./ui.zig").Window;

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

    var ctx = Context.init(t.term_h, t.term_w, &t);
    var win = Window{ .ctx = ctx, .pos = .{ .x = 0, .y = 0 } };

    var rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.nanoTimestamp()));
    var chunk = try Chunk.init(std.heap.page_allocator, .{ .x = 0, .y = 0 }, rng.random());
    defer chunk.deinit(std.heap.page_allocator);

    for (chunk.rooms.items) |room| {
        try room.draw(&win);
    }

    try t.present();

    _ = try t.pollEvent();
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
