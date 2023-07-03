const std = @import("std");
const assert = std.debug.assert;

const termbox = @import("termbox");

const Allocator = std.mem.Allocator;

const Window = @import("./Window.zig");
const Pos = @import("./Pos.zig");

const Line = struct {
    points: [2]Pos,

    fn init(p1: Pos, p2: Pos) Line {
        return .{ .points = .{ p1, p2 } };
    }

    fn intersects(l1: Line, l2: Line) bool {
        return Pos.intersects(l1.points[0], l1.points[1], l2.points[0], l2.points[1]);
    }
};

const Direction = enum {
    Left,
    Right,
    Up,
    Down,
};

const Hall = struct {
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
        };
    };

    fn get_corner_type(from: Direction, to: Direction) Point.Kind {
        switch (from) {
            .Left => {
                switch (to) {
                    .Up => return .UpLeft,
                    .Down => return .DownLeft,
                    else => @panic("No Valid Corner"),
                }
            },
            .Right => {
                switch (to) {
                    .Up => return .UpRight,
                    .Down => return .DownRight,
                    else => @panic("No Valid Corner"),
                }
            },
            .Up => {
                switch (to) {
                    .Left => return .UpLeft,
                    .Right => return .UpRight,
                    else => @panic("No Valid Corner"),
                }
            },
            .Down => {
                switch (to) {
                    .Left => return .DownLeft,
                    .Right => return .DownRight,
                    else => @panic("No Valid Corner"),
                }
            },
        }
    }

    fn get_entrance_type(to: Direction) Point.Kind {
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
                // try win.printAt("┘ └", .{}, pos.x - 1, pos.y);
                try win.putAt(pos.x - 1, pos.y, '┘');
                try win.putAt(pos.x, pos.y, ' ');
                try win.putAt(pos.x + 1, pos.y, '└');
            },
            .EnterDown => {
                // try win.printAt("┐ ┌", .{}, pos.x - 1, pos.y);
                try win.putAt(pos.x - 1, pos.y, '┐');
                try win.putAt(pos.x, pos.y, ' ');
                try win.putAt(pos.x + 1, pos.y, '┌');
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

    fn draw(hall: Hall, win: *Window) !void {
        std.debug.assert(hall.segments.items.len >= 2);

        try draw_enterance(hall.segments.items[0], win);

        var prev = hall.segments.items[0];
        for (hall.segments.items[1..]) |segment| {
            if (prev.pos.x == segment.pos.x) {
                // vertical
                var y: isize = 1;
                var height = std.math.absCast(prev.pos.y - segment.pos.y);

                while (y < height - 1) : (y += 1) {
                    // try win.printAt("│ │", .{}, prev.pos.x - 1, y);
                    try win.putAt(prev.pos.x - 1, prev.pos.y + y, '│');
                    try win.putAt(prev.pos.x, prev.pos.y + y, ' ');
                    try win.putAt(prev.pos.x + 1, prev.pos.y + y, '│');
                }
            } else {
                std.debug.assert(prev.pos.y == segment.pos.y);
                // horizontal
                var x = @min(prev.pos.x, segment.pos.x);
                var width = std.math.absCast(prev.pos.x - segment.pos.x);

                try win.putN(x + 1, segment.pos.y + 1, '─', width - 1);
                try win.putN(x + 1, segment.pos.y, ' ', width - 1);
                try win.putN(x + 1, segment.pos.y - 1, '─', width - 1);
            }

            switch (segment.kind) {
                .EnterUp, .EnterDown, .EnterLeft, .EnterRight => {
                    try draw_enterance(segment, win);
                },
                else => {},
            }
            prev = segment;
        }

        return;
    }
};

const Room = struct {
    pos: Pos,
    width: u32,
    height: u32,
    halls: std.ArrayListUnmanaged(*Hall),

    fn draw(room: Room, win: *Window) !void {
        var x = room.pos.x;

        try win.putN(x, room.pos.y, '─', room.width);

        var y = room.pos.y + 1;
        while (y < room.pos.y + room.height - 1) : (y += 1) {
            try win.putAt(room.pos.x, y, '│');
            try win.putN(room.pos.x + 1, room.pos.y, ' ', room.width - 2);
            try win.putAt(room.pos.x + room.width - 1, y, '│');
        }

        try win.putN(x, room.pos.y + room.height - 1, '─', room.width);

        for (room.halls.items) |hall| {
            try hall.draw(win);
        }
    }

    fn center(room: Room) Pos {
        return .{ .x = room.pos.x + (room.width / 2), .y = room.pos.y + (room.height / 2) };
    }

    const Wall = struct {
        direction: Direction,
        line: Line,
    };

    // Returns wall forming select side of room, wall points are garanteed to run clockwise
    fn get_wall(room: *const Room, direction: Direction) Wall {
        switch (direction) {
            .Left => return .{ .direction = direction, .line = Line.init(room.pos, .{ .x = room.pos.x, .y = room.pos.y + room.height - 1 }) },
            .Right => return .{ .direction = direction, .line = Line.init(.{ .x = room.pos.x + room.width - 1, .y = room.pos.y + room.height - 1 }, .{ .x = room.pos.x + room.width - 1, .y = room.pos.y }) },
            .Up => return .{ .direction = direction, .line = Line.init(.{ .x = room.pos.x, .y = room.pos.y + room.height - 1 }, .{ .x = room.pos.x + room.width - 1, .y = room.pos.y + room.height - 1 }) },
            .Down => return .{ .direction = direction, .line = Line.init(.{ .x = room.pos.x + room.width - 1, .y = room.pos.y }, room.pos) },
        }
    }

    fn manhattan_dist(from: Pos, to: Pos) usize {
        return std.math.absCast(to.x - from.x) + std.math.absCast(to.y - from.y);
    }

    // clorest_walls returns an array of walls where the first item (index 0) is the closest wall to the target
    fn closest_walls(room: *const Room, target: Pos) [4]Wall {
        const room_center = room.center();
        // Get walls for each side of room, defined clockwise
        var room_walls = [4]Wall{
            room.get_wall(.Up),
            room.get_wall(.Right),
            room.get_wall(.Down),
            room.get_wall(.Left),

            // Line.init(room.pos, .{ .x = room.pos.x + room.width, .y = room.pos.y }),
            // Line.init(room.pos, .{ .x = room.pos.x, .y = room.pos.y + room.height }),
            // Line.init(.{ .x = room.pos.x + room.width, .y = room.pos.y }, .{ .x = room.pos.x + room.width, .y = room.pos.y + room.height }),
            // Line.init(.{ .x = room.pos.x, .y = room.pos.y + room.height }, .{ .x = room.pos.x + room.width, .y = room.pos.y + room.height }),
        };

        var walls: [4]Wall = undefined;

        const y_diff = target.y - room_center.y;
        const x_diff = target.x - room_center.x;

        // Peppendicular isn't the best way to check for walls, best bet would be to use direction after finding the closest.
        const perpendicular_a = Line.init(room_center, .{ .x = room_center.x - y_diff * 10, .y = room_center.y + x_diff * 10 });
        _ = perpendicular_a;
        const perpendicular_b = Line.init(.{ .x = room_center.x + y_diff * 10, .y = room_center.y - x_diff * 10 }, room_center);
        _ = perpendicular_b;

        var main_wall_idx: usize = 0;
        for (room_walls) |wall, i| {
            if (wall.line.intersects(Line.init(room_center, target))) {
                walls[0] = wall;
                main_wall_idx = i;

                //     // get clockwise
                //     // get counter
                //     // get opposite
                // } else if (wall.line.intersects(perpendicular_a)) {
                //     walls[1] = wall;
                // } else if (wall.line.intersects(perpendicular_b)) {
                //     walls[2] = wall;
                // } else {
                //     walls[3] = wall;
                // }
                break;
            }
        } else {
            @panic("No walls found");
        }

        var pev_wall = if (main_wall_idx > 0) room_walls[main_wall_idx - 1] else room_walls[3];
        var next_wall = if (main_wall_idx < 3) room_walls[main_wall_idx + 1] else room_walls[0];

        var prev_dist = manhattan_dist(target, pev_wall.line.points[1]);
        var next_dist = manhattan_dist(target, next_wall.line.points[0]);

        if (prev_dist < next_dist) {
            walls[1] = pev_wall;
            walls[2] = next_wall;
        } else {
            walls[1] = next_wall;
            walls[2] = pev_wall;
        }

        // Wall behind intersected wall is always assumed furthest.
        var back_wall = if (main_wall_idx > 1) room_walls[main_wall_idx - 2] else room_walls[main_wall_idx + 2];
        walls[3] = back_wall;

        return walls;
    }

    // Using a weighted average of 0.5, 0.24, 0.24, 0.02, select a wall
    fn select_wall(walls: [4]Wall) Wall {
        const cumulative_sums = [4]u32{ 50, 74, 98, 100 };

        var rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.nanoTimestamp()));
        const rand = rng.random().intRangeAtMost(u32, 0, 99);

        for (cumulative_sums) |sum, i| {
            if (rand < sum) {
                return walls[i];
            }
        }
        return walls[3];
    }

    fn step(pos: Pos, dir: Direction, step_length: i32) Pos {
        switch (dir) {
            .Left => return Pos{ .x = pos.x - step_length, .y = pos.y },
            .Right => return Pos{ .x = pos.x + step_length, .y = pos.y },
            .Up => return Pos{ .x = pos.x, .y = pos.y + step_length },
            .Down => return Pos{ .x = pos.x, .y = pos.y - step_length },
        }
    }

    fn check_collision(room: *const Room, target: Pos) bool {
        return (target.x > room.pos.x and target.x < room.pos.x + room.width) or
            (target.y > room.pos.y and target.y < room.pos.y + room.height);
    }

    fn join(from: *Room, ally: Allocator, to: *Room) !void {
        // select from wall,
        // select point on from wall,
        // select to wall,
        // select point on to wall,o

        const from_walls = from.closest_walls(to.center());
        const to_walls = to.closest_walls(from.center());

        const from_wall = Room.select_wall(from_walls);
        const to_wall = Room.select_wall(to_walls);

        // TODO select a more random point on the wall
        // from_pos is the center of from_wall
        const from_pos = Pos{
            .x = @divFloor(from_wall.line.points[0].x + from_wall.line.points[1].x, @as(isize, 2)),
            .y = @divFloor(from_wall.line.points[0].y + from_wall.line.points[1].y, @as(isize, 2)),
        };
        const to_pos = Pos{
            .x = @divFloor(to_wall.line.points[0].x + to_wall.line.points[1].x, @as(isize, 2)),
            .y = @divFloor(to_wall.line.points[0].y + to_wall.line.points[1].y, @as(isize, 2)),
        };

        // path find

        // var DirectionWeights[@enumToInt(dir)] = dir;

        var hall: *Hall = try ally.create(Hall);
        hall.* = .{ .segments = .{} };
        try to.halls.append(ally, hall);
        try from.halls.append(ally, hall);
        try hall.segments.append(ally, .{ .kind = Hall.get_entrance_type(from_wall.direction), .pos = from_pos });

        var current_pos = from_pos;

        var dir: Direction = from_wall.direction;
        var previous_dir: Direction = dir;
        var direction_weight = [4]f32{ 0, 0, 0, 0 };

        while (current_pos.x != to_pos.x or current_pos.y != to_pos.y) {
            previous_dir = dir;

            // Weight each direction
            // Add one to each weight to allow prioritization of direction by decrease without risk of underflow
            direction_weight[@enumToInt(Direction.Left)] = @intToFloat(f32, manhattan_dist(to_pos, step(current_pos, .Left, 1)) + 1);
            direction_weight[@enumToInt(Direction.Right)] = @intToFloat(f32, manhattan_dist(to_pos, step(current_pos, .Right, 1)) + 1);
            direction_weight[@enumToInt(Direction.Up)] = @intToFloat(f32, manhattan_dist(to_pos, step(current_pos, .Up, 1)) + 1);
            direction_weight[@enumToInt(Direction.Down)] = @intToFloat(f32, manhattan_dist(to_pos, step(current_pos, .Down, 1)) + 1);

            // Slightly prioritize continuing in same direction for straighter lines
            direction_weight[@enumToInt(previous_dir)] -= @as(f32, 0.5);

            // sorted directions by bring pos closest to goal
            var closest_dir: [4]u32 = .{ 0, 0, 0, 0 };
            // Closest distances brought by step in closest_dir
            var closest_dist: [4]f32 = .{ std.math.f32_max, std.math.f32_max, std.math.f32_max, std.math.f32_max };
            var index: u32 = 0;
            while (index < 4) : (index += 1) {
                var cur_dir: u32 = index;
                var cur_dist = direction_weight[index];
                var sortIndex: u32 = 0;
                while (sortIndex < 4) : (sortIndex += 1) {
                    if (cur_dist < closest_dist[sortIndex]) {
                        var tmpi: u32 = closest_dir[sortIndex];
                        closest_dir[sortIndex] = cur_dir;
                        cur_dir = tmpi;
                        var tmpf: f32 = closest_dist[sortIndex];
                        closest_dist[sortIndex] = cur_dist;
                        cur_dist = tmpf;
                    }
                }
            }
            index = 0;
            var next_pos = current_pos;
            while (index < 4) : (index += 1) {
                dir = @intToEnum(Direction, closest_dir[index]);
                next_pos = step(current_pos, dir, 1);
                // if ((next_pos.x == to_pos.x and next_pos.y == to_pos.y) or false)
                // !(from.check_collision(next_pos) or to.check_collision(next_pos)))
                break;
            }
            if (dir != previous_dir) try hall.segments.append(ally, .{ .kind = Hall.get_corner_type(previous_dir, dir), .pos = current_pos });
            current_pos = next_pos;
        }

        // Add ending Entrance
        try hall.segments.append(ally, .{ .kind = Hall.get_entrance_type(to_wall.direction), .pos = to_pos });
    }
};

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

    var room1 = Room{ .pos = Pos{ .x = 10, .y = 10 }, .width = 5, .height = 5, .halls = std.ArrayListUnmanaged(*Hall){} };
    var room2 = Room{ .pos = Pos{ .x = 30, .y = 20 }, .width = 5, .height = 5, .halls = std.ArrayListUnmanaged(*Hall){} };
    try room1.join(std.heap.page_allocator, &room2);

    try room1.draw(&win);
    try room2.draw(&win);

    try t.present();

    _ = try t.pollEvent();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
