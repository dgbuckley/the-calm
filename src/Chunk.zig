const std = @import("std");

const Allocator = std.mem.Allocator;

const Line = Pos.Line;
const Pos = @import("Pos.zig");
const Room = @import("Room.zig");

const Chunk = @This();

pos: Pos,
rooms: std.ArrayListUnmanaged(*Room),
rng: std.rand.Random,

const Width: isize = 250;
const Height: isize = 250;

pub fn init(ally: Allocator, pos: Pos, rng: std.rand.Random) Allocator.Error!*Chunk {
    std.debug.assert(@mod(pos.x, Chunk.Width) == 0 and @mod(pos.y, Chunk.Height) == 0);
    var chunk: *Chunk = try std.heap.page_allocator.create(Chunk);
    chunk.* = .{ .pos = pos, .rooms = std.ArrayListUnmanaged(*Room){}, .rng = rng };
    try chunk.generateRooms(ally);
    return chunk;
}

pub fn deinit(chunk: *Chunk, ally: Allocator) void {
    for (chunk.rooms.items) |room| {
        room.deinit(ally);
    }
    chunk.rooms.deinit(ally);
    ally.destroy(chunk);
}

const PotentialRoom = struct {
    pos: Pos,
    width: u32,
    height: u32,
    connections: std.ArrayListUnmanaged(usize),

    fn center(room: PotentialRoom) Pos {
        return .{ .x = room.pos.x + (room.width / 2), .y = room.pos.y + (room.height / 2) };
    }
};

const ROOMS = 2;
fn generateRooms(chunk: *Chunk, ally: Allocator) !void {

    // room_store stores the rooms in memory
    var room_store = try ally.alloc(PotentialRoom, ROOMS);
    defer ally.free(room_store);

    // generate 50 random rooms
    for (room_store) |*room| {
        const width = chunk.rng.intRangeAtMost(u32, 8, 15);
        const height = chunk.rng.intRangeAtMost(u32, 8, 15);
        const x = chunk.rng.intRangeAtMost(usize, 0, @as(usize, Width) - width - 1);
        const y = chunk.rng.intRangeAtMost(usize, 0, @as(usize, Height) - height - 1);

        room.* = PotentialRoom{
            .pos = .{ .x = @intCast(isize, x), .y = @intCast(isize, y) },
            .width = width,
            .height = height,
            .connections = std.ArrayListUnmanaged(usize){},
        };
    }

    // Use optional pointers to eliminate rooms
    var rooms: [ROOMS]?*PotentialRoom = undefined;
    for (rooms) |*room, i| {
        room.* = &room_store[i];
    }

    for (rooms) |maybe_room, i| {
        if (maybe_room == null) continue;
        var room = maybe_room.?;
        for (rooms[i + 1 ..]) |maybe_r| {
            if (maybe_r == null) continue;
            var r = maybe_r.?;

            const gap: isize = 6;
            if (r.pos.y < room.pos.y + room.height + gap and r.pos.x < room.pos.x + room.width + gap and r.pos.y + r.height + gap > room.pos.y and r.pos.x + r.width + gap > room.pos.x) {
                rooms[i] = null;
                break;
            }
        }
    }

    // TODO: Complete two phase system for selecting paths between rooms
    // Phase 1:
    // start from one room and recursivly traverse

    // TODO walk the graph tracking connections. If we re-walk a connection, concider deleting one randomly using length as a weight.

    for (rooms) |maybe_room, i| {
        if (maybe_room == null) continue;
        var room = maybe_room.?;

        for (rooms[i + 1 ..]) |maybe_r, j| {
            if (maybe_r == null) continue;

            try room.connections.append(ally, i + j + 1);
        }
    }

    for (rooms) |maybe_room| {
        if (maybe_room == null) continue;
        var room = maybe_room.?;

        var con_i: usize = 1;
        while (con_i < room.connections.items.len) {
            var con = room.connections.items[con_i];
            const l1 = Line.init(room.center(), rooms[con].?.center());

            loop: for (rooms) |maybe_p, i| {
                if (maybe_p == null) continue;
                var p = maybe_p.?;

                for (rooms[i..]) |maybe_q| {
                    if (maybe_q == null) continue;
                    var q = maybe_q.?;

                    const l2 = Line.init(p.center(), q.center());

                    if (l1.intersects(l2)) {
                        _ = room.connections.orderedRemove(con_i);
                        break :loop;
                    }
                }
            } else con_i += 1;
        }
    }

    var room_map = std.AutoHashMapUnmanaged(usize, *Room){};
    defer room_map.deinit(ally);

    for (rooms) |maybe_room, i| {
        if (maybe_room == null) continue;
        var room = maybe_room.?;

        var r = try Room.init(ally, room.pos, room.width, room.height);
        try room_map.put(ally, i, r);
        try chunk.rooms.append(ally, r);
    }

    for (rooms) |maybe_room, i| {
        if (maybe_room == null) continue;
        var pot_room = maybe_room.?;
        var room = room_map.get(i).?;

        for (pot_room.connections.items) |con| {
            var r = room_map.get(con).?;
            try room.join(ally, r);
        }
    }
}
