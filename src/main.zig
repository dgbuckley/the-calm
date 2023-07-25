const std = @import("std");
const assert = std.debug.assert;
const termbox = @import("termbox");
const Allocator = std.mem.Allocator;

const libui = @import("ui.zig");
const Chunk = @import("Chunk.zig");
const Context = libui.Context;
const Game = @import("Game.zig");
const Window = libui.Window;
const UI = libui.UI;

fn getmaxyx(y: *u16, x: *u16) void {
    var winsize: std.os.linux.winsize = undefined;
    _ = std.os.linux.ioctl(0, std.os.linux.T.IOCGWINSZ, @ptrToInt(&winsize));
    y.* = winsize.ws_row;
    x.* = winsize.ws_col;
    return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    var ally = gpa.allocator();

    var rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.nanoTimestamp()));
    var game = try Game.init(ally, rng.random());
    defer game.deinit();
    try game.newGame();

    var ui = try UI.init(ally, game);
    defer ui.deinit(ally);

    while (!ui.shouldExit()) {
        const tick = try ui.tick();

        // ~60fps
        if (!tick) std.time.sleep(16 * std.time.ns_per_ms);
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
