const std = @import("std");

const Direction = Pos.Direction;
const Line = Pos.Line;
const Pos = @import("Pos.zig");
const Window = @import("Window.zig");

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

fn draw_enterance(segment: Hall.Point, win: *Window) !void {
    const pos = segment.pos;
    switch (segment.kind) {
        .EnterUp => {
            try win.printAt("┘ └", .{}, pos.x - 1, pos.y);
        },
        .EnterDown => {
            try win.printAt("┐ ┌", .{}, pos.x - 1, pos.y);
        },
        .EnterLeft => {
            try win.putAt(pos.x, pos.y + 1, '┘');
            try win.putAt(pos.x, pos.y, ' ');
            try win.putAt(pos.x, pos.y - 1, '┐');
        },
        .EnterRight => {
            try win.putAt(pos.x, pos.y + 1, '└');
            try win.putAt(pos.x, pos.y, ' ');
            try win.putAt(pos.x, pos.y - 1, '┌');
        },
        else => @panic("Invalid Enterance"),
    }
}

fn draw_corner(segment: Hall.Point, win: *Window) !void {
    const pos = segment.pos;
    switch (segment.kind) {
        .UpRight => {
            try win.printAt("│ └", .{}, pos.x - 1, pos.y + 1);
            try win.printAt("│  ", .{}, pos.x - 1, pos.y);
            try win.printAt("└──", .{}, pos.x - 1, pos.y - 1);
        },
        .DownRight => {
            try win.printAt("┌──", .{}, pos.x - 1, pos.y + 1);
            try win.printAt("│  ", .{}, pos.x - 1, pos.y);
            try win.printAt("│ ┌", .{}, pos.x - 1, pos.y - 1);
        },
        .UpLeft => {
            try win.printAt("┘ │", .{}, pos.x - 1, pos.y + 1);
            try win.printAt("  │", .{}, pos.x - 1, pos.y);
            try win.printAt("──┘", .{}, pos.x - 1, pos.y - 1);
        },
        .DownLeft => {
            try win.printAt("──┐", .{}, pos.x - 1, pos.y + 1);
            try win.printAt("  │", .{}, pos.x - 1, pos.y);
            try win.printAt("┐ │", .{}, pos.x - 1, pos.y - 1);
        },
        else => @panic("Invalid Enterance"),
    }
}

pub fn draw(hall: Hall, win: *Window) !void {
    std.debug.assert(hall.segments.items.len >= 2);

    var prev = hall.segments.items[0];
    for (hall.segments.items[1..]) |segment| {
        if (prev.pos.x == segment.pos.x) {
            // vertical
            var y: isize = 1;
            var height = std.math.absCast(prev.pos.y - segment.pos.y);

            while (y < height) : (y += 1) {
                win.printAt("│ │", .{}, prev.pos.x - 1, prev.pos.y + y) catch return;
            }
        } else {
            std.debug.assert(prev.pos.y == segment.pos.y);
            // horizontal
            var x = @min(prev.pos.x, segment.pos.x) + 1;
            var width = std.math.absCast(prev.pos.x - segment.pos.x);

            try win.putN(x, segment.pos.y + 1, '─', width - 1);
            try win.putN(x, segment.pos.y, ' ', width - 1);
            try win.putN(x, segment.pos.y - 1, '─', width - 1);
        }

        prev = segment;
    }

    for (hall.segments.items) |segment| {
        switch (segment.kind) {
            .EnterUp, .EnterDown, .EnterLeft, .EnterRight => {
                try draw_enterance(segment, win);
            },
            else => try draw_corner(segment, win),
        }
    }

    return;
}
