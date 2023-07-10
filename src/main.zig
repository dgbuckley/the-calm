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

    const ArrowUp = 0xFFFF - 18;
    const ArrowDown = 0xFFFF - 19;
    const ArrowLeft = 0xFFFF - 20;
    const ArrowRight = 0xFFFF - 21;

    main: while (true) {
        switch (try t.pollEvent()) {
            .Key => |key_ev| {
                switch (key_ev.ch) {
                    'q' => break :main,
                    else => {},
                }
                switch (key_ev.key) {
                    ArrowUp => win.pos.y -= 1,
                    ArrowDown => win.pos.y += 1,
                    ArrowRight => win.pos.x += 1,
                    ArrowLeft => win.pos.x -= 1,
                    else => {},
                }
            },
            else => {},
        }

        t.clear();

        for (chunk.rooms.items) |room| {
            try room.draw(&win);
        }

        try t.present();
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
