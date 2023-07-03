const std = @import("std");

const Pos = @This();

x: isize,
y: isize,

const Orientation = enum(u8) {
    Collinear = 0,
    Clockwise,
    Counter,
};

// Checks the orientation of 3 points
pub fn orientation(p: Pos, q: Pos, r: Pos) Orientation {
    var lExpr: isize = ((q.y - p.y) * (r.x - q.x));
    var rExpr: isize = ((q.x - p.x) * (r.y - q.y));
    const val: isize = lExpr - rExpr;

    if (val == 0) return .Collinear;
    return if (val > 0) .Clockwise else .Counter;
}

// Test if line 1 intersect line 2
pub fn intersects(p1: Pos, q1: Pos, p2: Pos, q2: Pos) bool {
    return (orientation(p1, q1, p2) != orientation(p1, q1, q2)) and (orientation(p2, q2, p1) != orientation(p2, q2, q1));
}

pub fn manhattan_dist(from: Pos, to: Pos) usize {
    return std.math.absCast(to.x - from.x) + std.math.absCast(to.y - from.y);
}

pub const Line = struct {
    points: [2]Pos,

    pub fn init(p1: Pos, p2: Pos) Line {
        return .{ .points = .{ p1, p2 } };
    }

    pub fn intersects(l1: Line, l2: Line) bool {
        return Pos.intersects(l1.points[0], l1.points[1], l2.points[0], l2.points[1]);
    }
};

pub const Direction = enum {
    Left,
    Right,
    Up,
    Down,

    pub fn opposite(dir: Direction) Direction {
        switch (dir) {
            .Left => return .Right,
            .Right => return .Left,
            .Up => return .Down,
            .Down => return .Up,
        }
    }
};
