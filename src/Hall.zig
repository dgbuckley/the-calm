const std = @import("std");

const Direction = Pos.Direction;
const Line = Pos.Line;
const Pos = @import("Pos.zig");
const Window = @import("ui.zig").Window;

const Hall = @This();

// The list of segments are guaranteed to be the correct order,
// but not to be in any specific direction.
segments: std.ArrayListUnmanaged(Point),

const Point = struct {
    kind: Kind,
    pos: Pos,

    const Kind = enum {
        // ┘ └
        EnterUp,
        // ┐ ┌
        EnterDown,
        // ┘
        //
        // ┐
        EnterLeft,
        // └
        //
        // ┌
        EnterRight,
        // ┌──
        // │
        // │ ┌
        DownRight,
        // │ └
        // │
        // └──
        UpRight,
        // ──┐
        //   │
        // ┐ │
        DownLeft,
        // ┘ │
        //   │
        // ──┘
        UpLeft,

        fn isEnterance(kind: Kind) bool {
            switch (kind) {
                .EnterUp, .EnterDown, .EnterLeft, .EnterRight => return true,
                else => return false,
            }
        }
    };
};

pub fn get_corner_type(previous: Direction, current: Direction) Point.Kind {
    switch (previous) {
        .Right => {
            switch (current) {
                .Up => return .UpLeft,
                .Down => return .DownLeft,
                else => @panic("No Valid Corner"),
            }
        },
        .Left => {
            switch (current) {
                .Up => return .UpRight,
                .Down => return .DownRight,
                else => @panic("No Valid Corner"),
            }
        },
        .Down => {
            switch (current) {
                .Left => return .UpLeft,
                .Right => return .UpRight,
                else => @panic("No Valid Corner"),
            }
        },
        .Up => {
            switch (current) {
                .Left => return .DownLeft,
                .Right => return .DownRight,
                else => @panic("No Valid Corner"),
            }
        },
    }
}

pub fn get_entrance_type(to: Direction) Point.Kind {
    switch (to) {
        .Left => return .EnterLeft,
        .Right => return .EnterRight,
        .Up => return .EnterUp,
        .Down => return .EnterDown,
    }
}

fn draw_enterance(segment: Hall.Point, win: *Window) void {
    const pos = segment.pos;
    switch (segment.kind) {
        .EnterUp => {
            win.putHorizontal(pos.x - 1, pos.y, &[_]u21{ '┘', ' ', '└' });
        },
        .EnterDown => {
            win.putHorizontal(pos.x - 1, pos.y, &[_]u21{ '┐', ' ', '┌' });
        },
        .EnterLeft => {
            win.putAt(pos.x, pos.y + 1, '┘');
            win.putAt(pos.x, pos.y, ' ');
            win.putAt(pos.x, pos.y - 1, '┐');
        },
        .EnterRight => {
            win.putAt(pos.x, pos.y + 1, '└');
            win.putAt(pos.x, pos.y, ' ');
            win.putAt(pos.x, pos.y - 1, '┌');
        },
        else => @panic("Invalid Enterance"),
    }
}

fn draw_corner(segment: Hall.Point, win: *Window) void {
    const pos = segment.pos;
    switch (segment.kind) {
        .UpRight => {
            win.putHorizontal(pos.x - 1, pos.y + 1, &[_]u21{ '│', ' ', '└' });
            win.putHorizontal(pos.x - 1, pos.y, &[_]u21{ '│', ' ', ' ' });
            win.putHorizontal(pos.x - 1, pos.y - 1, &[_]u21{ '└', '─', '─' });
        },
        .DownRight => {
            win.putHorizontal(pos.x - 1, pos.y + 1, &[_]u21{ '┌', '─', '─' });
            win.putHorizontal(pos.x - 1, pos.y, &[_]u21{ '│', ' ', ' ' });
            win.putHorizontal(pos.x - 1, pos.y - 1, &[_]u21{ '│', ' ', '┌' });
        },
        .UpLeft => {
            win.putHorizontal(pos.x - 1, pos.y + 1, &[_]u21{ '┘', ' ', '│' });
            win.putHorizontal(pos.x - 1, pos.y, &[_]u21{ ' ', ' ', '│' });
            win.putHorizontal(pos.x - 1, pos.y - 1, &[_]u21{ '─', '─', '┘' });
        },
        .DownLeft => {
            win.putHorizontal(pos.x - 1, pos.y + 1, &[_]u21{ '─', '─', '┐' });
            win.putHorizontal(pos.x - 1, pos.y, &[_]u21{ ' ', ' ', '│' });
            win.putHorizontal(pos.x - 1, pos.y - 1, &[_]u21{ '┐', ' ', '│' });
        },
        else => @panic("Invalid Enterance"),
    }
}

pub fn draw(hall: Hall, win: *Window) void {
    std.debug.assert(hall.segments.items.len >= 2);

    var prev = hall.segments.items[0];
    for (hall.segments.items[1..]) |segment| {
        if (prev.pos.x == segment.pos.x) {
            // vertical
            var y: isize = @min(prev.pos.y, segment.pos.y);
            var height = (std.math.absInt(prev.pos.y - segment.pos.y) catch unreachable) + y;

            while (y < height) : (y += 1) {
                win.putHorizontal(prev.pos.x - 1, y, &[_]u21{ '│', ' ', '│' });
            }
        } else {
            std.debug.assert(prev.pos.y == segment.pos.y);
            // horizontal
            var x = @min(prev.pos.x, segment.pos.x) + 1;
            var width = std.math.absCast(prev.pos.x - segment.pos.x);

            win.putNHorizontal(x, segment.pos.y + 1, '─', width - 1);
            win.putNHorizontal(x, segment.pos.y, ' ', width - 1);
            win.putNHorizontal(x, segment.pos.y - 1, '─', width - 1);
        }

        prev = segment;
    }

    for (hall.segments.items) |segment| {
        switch (segment.kind) {
            .EnterUp, .EnterDown, .EnterLeft, .EnterRight => {
                draw_enterance(segment, win);
            },
            else => draw_corner(segment, win),
        }
    }

    return;
}
