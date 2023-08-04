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

pub const RoomBounds = struct {
    clearance: isize,
    bound_positions: std.AutoHashMap(Pos, void),

    pub fn init(ally: Allocator, clearance: isize) RoomBounds {
        return RoomBounds{
            .clearance = clearance,
            .bound_positions = std.AutoHashMap(Pos, void).init(ally),
        };
    }

    pub fn deinit(bounds: *RoomBounds) void {
        bounds.bound_positions.deinit();
    }

    pub fn addBounds(bounds: *RoomBounds, room: *const Room) error{OutOfMemory}!void {
        // iterate though walls starting at bottom left corner going clockwise
        var cur_pos: Pos = Pos{ .x = room.pos.x - bounds.clearance, .y = room.pos.y - bounds.clearance };

        try bounds.bound_positions.put(cur_pos, {});

        // vertical walls
        var index: isize = room.pos.y - bounds.clearance;
        while (index < room.pos.y + room.height + bounds.clearance) : (index += 1) {
            try bounds.bound_positions.put(Pos{ .x = room.pos.x - bounds.clearance, .y = index }, {});
            try bounds.bound_positions.put(Pos{ .x = room.pos.x + room.width - 1 + bounds.clearance, .y = index }, {});
        }
        // horizontal wall
        index = room.pos.x - bounds.clearance;
        while (index < room.pos.x + room.width + bounds.clearance) : (index += 1) {
            try bounds.bound_positions.put(Pos{ .x = index, .y = room.pos.y - bounds.clearance }, {});
            try bounds.bound_positions.put(Pos{ .x = index, .y = room.pos.y + room.height - 1 + bounds.clearance }, {});
        }
    }

    pub fn checkCollision(bounds: RoomBounds, target: Pos) bool {
        return bounds.bound_positions.get(target) != null;
    }
};

const Node = struct {
    pos: Pos,
    G_cost: usize, // Distance from starting node
    H_cost: usize, // Direct distance from target node
    open: bool,
    dir_from: Direction, // Direction of which node led to this
};

pub fn closeNode(node_index: usize, openNodes: *std.ArrayList(Node), closedNodes: *std.AutoHashMap(Pos, usize), room_bounds: RoomBounds, to_pos: Pos) error{OutOfMemory}!void {
    var dir: Direction = .Left;
    var n: Pos = Pos{ .x = 0, .y = 0 };
    var i: u32 = 0;
    // Iterate through each neighbor of current node
    while (i < 4) : (i += 1) {
        dir = @intToEnum(Direction, i);
        n = step(openNodes.items[node_index].pos, dir, 1);
        // Skip if neighbor already closed
        if (closedNodes.get(n) != null) continue;
        if (room_bounds.checkCollision(n)) continue;
        for (openNodes.items) |_, j| {
            // Ensure node is the current neighbor
            if (openNodes.items[j].pos.x != n.x or openNodes.items[j].pos.y != n.y) continue; // Filter out nodes not at pos n
            std.debug.assert(openNodes.items[j].open); // Node should've alread been tested for being closed

            if (openNodes.items[j].G_cost > openNodes.items[node_index].G_cost + 1) {
                openNodes.items[j].G_cost = openNodes.items[node_index].G_cost + 1;
                openNodes.items[j].dir_from = dir.opposite();
            }
            break;
        } else {
            try openNodes.append(Node{ .pos = n, .G_cost = openNodes.items[node_index].G_cost + 1, .H_cost = n.manhattan_dist(to_pos), .open = true, .dir_from = dir.opposite() });
        }
    }
    // Set current node to closed
    openNodes.items[node_index].open = false;
    try closedNodes.put(openNodes.items[node_index].pos, node_index);
}

pub fn join(from: *Room, ally: Allocator, to: *Room, room_bounds: RoomBounds) !void {
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

    var openNodes = std.ArrayList(Node).init(ally);
    var closedNodes = std.AutoHashMap(Pos, usize).init(ally);

    // Create node for initial position and imediatly close it
    try openNodes.append(Node{ .pos = from_pos, .G_cost = 0, .H_cost = from_pos.manhattan_dist(to_pos), .open = true, .dir_from = from_wall.direction.opposite() });
    try closeNode(0, &openNodes, &closedNodes, room_bounds, to_pos);

    var current_index: usize = 0;

    while (openNodes.items[current_index].pos.x != to_pos.x or openNodes.items[current_index].pos.y != to_pos.y) {
        // Find open node with smallest F_cost (G_cost + H_cost  or  distince to end node + distance from start node)
        var smallest_F_cost: usize = std.math.maxInt(u32);
        var selected_index: usize = 0;
        for (openNodes.items) |node, i| {
            if (!node.open) continue;
            if (node.G_cost + node.H_cost < smallest_F_cost) {
                smallest_F_cost = node.G_cost + node.H_cost;
                selected_index = i;
            }
        }
        current_index = selected_index;
        try closeNode(current_index, &openNodes, &closedNodes, room_bounds, to_pos);
    }

    // Build hallway going from to_pos to from_pos

    var hall: *Hall = try ally.create(Hall);
    hall.* = .{ .segments = .{} };
    try to.halls.append(ally, hall);
    try from.halls.append(ally, hall);

    // add entrace on to_wall
    try hall.segments.append(ally, .{ .kind = Hall.get_entrance_type(to_wall.direction), .pos = step(to_pos, to_wall.direction.opposite(), 2) });

    // Add turns taken by path
    var prev_dir: Direction = to_wall.direction;
    var cur_pos: Pos = to_pos;
    var cur_node = openNodes.items[
        closedNodes.get(cur_pos) orelse @panic("Unable to find node at to_pos")
    ];

    while (cur_pos.x != from_pos.x or cur_pos.y != from_pos.y) {
        if (cur_node.dir_from != prev_dir)
            try hall.segments.append(ally, .{ .kind = Hall.get_corner_type(prev_dir, cur_node.dir_from), .pos = cur_pos });

        prev_dir = cur_node.dir_from;
        cur_pos = step(cur_pos, cur_node.dir_from, 1);
        cur_node = openNodes.items[
            closedNodes.get(cur_pos) orelse @panic("Unable to find node for position")
        ];
    }

    if (cur_node.dir_from != prev_dir and cur_node.dir_from != prev_dir.opposite())
        try hall.segments.append(ally, .{ .kind = Hall.get_corner_type(prev_dir, cur_node.dir_from), .pos = cur_pos });

    // Add entrace on from_wall
    try hall.segments.append(ally, .{ .kind = Hall.get_entrance_type(from_wall.direction), .pos = step(from_pos, from_wall.direction.opposite(), 2) });
}
