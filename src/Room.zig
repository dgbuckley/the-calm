const std = @import("std");

const Allocator = std.mem.Allocator;

const Direction = Pos.Direction;
const Hall = @import("./Hall.zig");
const Line = Pos.Line;
const Pos = @import("./Pos.zig");
const Window = @import("./ui.zig").Window;

const Room = @This();

pos: Pos,
width: u32,
height: u32,
halls: std.ArrayListUnmanaged(*Hall),

pub fn init(ally: Allocator, pos: Pos, width: u32, height: u32) !*Room {
    var room = try ally.create(Room);
    room.* = .{
        .pos = pos,
        .width = width,
        .height = height,
        .halls = .{},
    };
    return room;
}

pub fn deinit(room: *Room, ally: Allocator) void {
    ally.destroy(room);
}

pub fn draw(room: Room, win: *Window) void {
    var x = room.pos.x;

    win.putNHorizontal(x + 1, room.pos.y, '─', room.width - 2);
    win.putAt(x, room.pos.y, '└');
    win.putAt(x + room.width - 1, room.pos.y, '┘');

    var y = room.pos.y + 1;
    while (y < room.pos.y + room.height - 1) : (y += 1) {
        win.putAt(room.pos.x, y, '│');
        win.putNHorizontal(room.pos.x + 1, y, ' ', room.width - 2);
        win.putAt(room.pos.x + room.width - 1, y, '│');
    }

    win.putNHorizontal(x, room.pos.y + room.height - 1, '─', room.width - 1);
    win.putAt(x, room.pos.y + room.height - 1, '┌');
    win.putAt(x + room.width - 1, room.pos.y + room.height - 1, '┐');

    for (room.halls.items) |hall| {
        hall.draw(win);
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

    var prev_dist = target.manhattan_dist(pev_wall.line.points[1]);
    var next_dist = target.manhattan_dist(next_wall.line.points[0]);

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

pub fn check_collision(room: *const Room, target: Pos, clearance: isize) bool {
    return (target.x >= room.pos.x - clearance and target.x < room.pos.x + room.width + clearance) and
        (target.y >= room.pos.y - clearance and target.y < room.pos.y + room.height + clearance);
}

pub fn join(from: *Room, ally: Allocator, to: *Room) !void {
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
    const from_pos = blk: {
        var from_pos = Pos{
            .x = @divFloor(from_wall.line.points[0].x + from_wall.line.points[1].x, @as(isize, 2)),
            .y = @divFloor(from_wall.line.points[0].y + from_wall.line.points[1].y, @as(isize, 2)),
        };

        from_pos = step(from_pos, from_wall.direction, 2);

        break :blk from_pos;
    };

    const to_pos = blk: {
        var to_pos = Pos{
            .x = @divFloor(to_wall.line.points[0].x + to_wall.line.points[1].x, @as(isize, 2)),
            .y = @divFloor(to_wall.line.points[0].y + to_wall.line.points[1].y, @as(isize, 2)),
        };
        to_pos = step(to_pos, to_wall.direction, 2);
        break :blk to_pos;
    };

    // path find

    // var DirectionWeights[@enumToInt(dir)] = dir;

    var hall: *Hall = try ally.create(Hall);
    hall.* = .{ .segments = .{} };
    try to.halls.append(ally, hall);
    try from.halls.append(ally, hall);
    try hall.segments.append(ally, .{ .kind = Hall.get_entrance_type(from_wall.direction), .pos = step(from_pos, from_wall.direction.opposite(), 2) });

    var current_pos = from_pos;

    var dir: Direction = from_wall.direction;
    var prev_dir: Direction = dir;
    var direction_weight = [4]f32{ 0, 0, 0, 0 };

    while (current_pos.x != to_pos.x or current_pos.y != to_pos.y) {
        prev_dir = dir;

        // Weight each direction
        // Add one to each weight to allow prioritization of direction by decrease without risk of underflow
        direction_weight[@enumToInt(Direction.Left)] = @intToFloat(f32, to_pos.manhattan_dist(step(current_pos, .Left, 1)) + 1);
        direction_weight[@enumToInt(Direction.Right)] = @intToFloat(f32, to_pos.manhattan_dist(step(current_pos, .Right, 1)) + 1);
        direction_weight[@enumToInt(Direction.Up)] = @intToFloat(f32, to_pos.manhattan_dist(step(current_pos, .Up, 1)) + 1);
        direction_weight[@enumToInt(Direction.Down)] = @intToFloat(f32, to_pos.manhattan_dist(step(current_pos, .Down, 1)) + 1);

        // Slightly prioritize continuing in same direction for straighter lines
        direction_weight[@enumToInt(prev_dir)] -= @as(f32, 0.5);

        // sorted directions by bring pos closest to goal
        var closest_dir: [3]u32 = .{ 0, 0, 0 };
        // Closest distances brought by step in closest_dir
        var closest_dist: [3]f32 = .{ std.math.f32_max, std.math.f32_max, std.math.f32_max };
        var index: u32 = 0;
        while (index < 4) : (index += 1) {
            var cur_dir: u32 = index;
            var cur_dist = direction_weight[index];
            var sortIndex: u32 = 0;
            while (sortIndex < 3) : (sortIndex += 1) {
                if (cur_dist < closest_dist[sortIndex] and
                    @intToEnum(Direction, cur_dir) != dir.opposite())
                {
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
        while (index < 3) : (index += 1) {
            dir = @intToEnum(Direction, closest_dir[index]);
            next_pos = step(current_pos, dir, 1);
            if ((next_pos.x == to_pos.x and next_pos.y == to_pos.y) or
                !(from.check_collision(next_pos, 1) or to.check_collision(next_pos, 1)))
                break;
        }
        if (dir != prev_dir) try hall.segments.append(ally, .{ .kind = Hall.get_corner_type(prev_dir, dir), .pos = current_pos });
        current_pos = next_pos;
    }

    // Check if any turn taken in entering room, add turn to hall if so
    if (dir != to_wall.direction.opposite())
        try hall.segments.append(ally, .{ .kind = Hall.get_corner_type(dir, to_wall.direction.opposite()), .pos = to_pos });

    // Add ending Entrance
    try hall.segments.append(ally, .{ .kind = Hall.get_entrance_type(to_wall.direction), .pos = step(to_pos, to_wall.direction.opposite(), 2) });
}
