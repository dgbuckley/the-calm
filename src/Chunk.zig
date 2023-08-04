const std = @import("std");

const Allocator = std.mem.Allocator;

const Line = Pos.Line;
const Pos = @import("Pos.zig");
const Room = @import("Room.zig");

const Chunk = @This();

pos: Pos,
rooms: []Room,
rng: std.rand.Random,

const Width: isize = 120;
const Height: isize = 120;

pub fn init(ally: Allocator, pos: Pos, rng: std.rand.Random) Allocator.Error!*Chunk {
    std.debug.assert(@mod(pos.x, Chunk.Width) == 0 and @mod(pos.y, Chunk.Height) == 0);
    var chunk: *Chunk = try ally.create(Chunk);
    chunk.* = .{ .pos = pos, .rooms = &.{}, .rng = rng };
    try chunk.generateRooms(ally);
    return chunk;
}

pub fn deinit(chunk: *Chunk, ally: Allocator) void {
    ally.free(chunk.rooms);
    ally.destroy(chunk);
}

const PotentialRoom = struct {
    pos: Pos,
    width: u32,
    height: u32,
    connections: std.ArrayListUnmanaged(*PotentialRoom),

    fn center(room: PotentialRoom) Pos {
        return .{ .x = room.pos.x + (room.width / 2), .y = room.pos.y + (room.height / 2) };
    }
};

const Triangle = struct {
    // Three points in clockwise orientation, making a traingle
    points: [3]*PotentialRoom,
    contains: std.ArrayListUnmanaged(*PotentialRoom),
    list: LinkedList(Triangle, "list").Node,

    // Three points in clockwise orientation, making a traingle
    fn init(ally: Allocator, points: [3]*PotentialRoom, contains: []const *PotentialRoom) !*Triangle {
        std.debug.assert(Pos.orientation(points[0].pos, points[1].pos, points[2].pos) == .Clockwise);

        var t = try ally.create(Triangle);
        t.* = Triangle{
            .points = points,
            .contains = std.ArrayListUnmanaged(*PotentialRoom){},
            .list = LinkedList(Triangle, "list").Node{ .next = null, .prev = null },
        };
        try t.contains.appendSlice(ally, contains);
        return t;
    }

    fn deinit(t: *Triangle, ally: Allocator) void {
        _ = t.list.remove();
        t.contains.deinit(ally);
        ally.destroy(t);
    }

    fn is_inside(t: Triangle, p: *PotentialRoom) bool {
        const o1 = Pos.orientation(t.points[0].pos, t.points[1].pos, p.pos);
        const o2 = Pos.orientation(t.points[1].pos, t.points[2].pos, p.pos);
        const o3 = Pos.orientation(t.points[2].pos, t.points[0].pos, p.pos);

        return (o1 == .Clockwise and o1 == o2 and o1 == o3);
    }

    // Returns true if the point is inside a circle formed by the triangles 3 points.
    fn in_circle(tri: Triangle, p: PotentialRoom) bool {
        const o1 = Pos.orientation(tri.points[0].pos, tri.points[1].pos, p.pos);
        const o2 = Pos.orientation(tri.points[1].pos, tri.points[2].pos, p.pos);
        const o3 = Pos.orientation(tri.points[2].pos, tri.points[0].pos, p.pos);

        if (o1 == .Clockwise and o1 == o2 and o1 == o3)
            return true;
        if ((o1 == .Counter and o2 == .Counter and o3 == .Clockwise) or
            (o1 == .Clockwise and o2 == .Counter and o3 == .Counter) or
            (o1 == .Counter and o2 == .Clockwise and o3 == .Counter))
            return false;

        // Find determinate of following 4by4 matrix, within circle result is < 0
        // m =
        // [t[2].x,  t[2].x,  (t[2].x^2 + t[2].y^2),  1]
        // [t[1].x,  t[1].x,  (t[1].x^2 + t[1].y^2),  1]
        // [t[0].x,  t[0].x,  (t[0].x^2 + t[0].y^2),  1]
        // [p.x,  p.x,  (p.x^2 + p.y^2),  1]

        const det = determinant(4, .{
            .{ tri.points[2].p.x, tri.points[2].pos.y, (std.math.pow(isize, tri.points[2].pos.x, 2) + std.math.pow(isize, tri.points[2].pos.y, 2)), 1 },
            .{ tri.points[1].p.x, tri.points[1].pos.y, (std.math.pow(isize, tri.points[1].pos.x, 2) + std.math.pow(isize, tri.points[1].pos.y, 2)), 1 },
            .{ tri.points[0].p.x, tri.points[0].pos.y, (std.math.pow(isize, tri.points[0].pos.x, 2) + std.math.pow(isize, tri.points[0].pos.y, 2)), 1 },
            .{ p.pos.x, p.pos.y, (std.math.pow(isize, p.pos.x, 2) + std.math.pow(isize, p.pos.y, 2)), 1 },
        });
        return det > 0;
    }
};

fn submatrix(comptime col: usize, comptime d: usize, m: [d][d]isize) [d - 1][d - 1]isize {
    var sub: [d - 1][d - 1]isize = undefined;

    comptime var c = 0;
    comptime var real_c = 0;
    inline while (c < d) : (c += 1) {
        if (c != col) {
            comptime var r = 1;
            inline while (r < d) : (r += 1) {
                sub[r - 1][real_c] = m[r][c];
            }
            real_c += 1;
        }
    }

    return sub;
}

fn determinant(comptime d: usize, m: [d][d]isize) isize {
    if (d > 2) {
        var det: isize = 0;
        comptime var sub_m_i = 0;
        inline while (sub_m_i < d) : (sub_m_i += 1) {
            const sub3 = determinant(d - 1, submatrix(sub_m_i, d, m));

            det += m[0][sub_m_i] * sub3 * (sub_m_i % 2 * -2 + 1);
        }
        return det;
    } else if (d == 2) {
        return m[0][0] * m[1][1] - m[0][1] * m[1][0];
    } else {
        return m[0][0];
    }
}

fn LinkedList(comptime T: type, comptime node_field_name: []const u8) type {
    return struct {
        head: ?*Node,

        fn insert(self: *@This(), node: *Node) void {
            var head = self.head;
            self.head = node;
            if (head) |h| {
                h.prev = self.head;
                self.head.?.next = h;
            }
        }

        const Node = struct {
            next: ?*Node,
            prev: ?*Node,

            fn data(self: *Node) *T {
                return @fieldParentPtr(T, node_field_name, self);
            }

            fn remove(self: *Node) *Node {
                if (self.prev) |prev|
                    prev.next = self.next;
                self.prev = null;
                if (self.next) |next|
                    next.prev = self.prev;
                self.next = null;
                return self;
            }

            fn insert_after(self: *Node, after: *Node) *Node {
                if (@import("builtin").mode == .Debug) {
                    std.debug.assert(after.next == null and after.prev == null);
                }

                if (self.next) |next| {
                    after.next = next;
                    next.prev = after;
                }
                self.next = after;
                after.prev = self;

                return self;
            }

            fn first(node: *Node) *Node {
                var n = node;
                while (n.prev) |prev| : (n = prev) {}
                return n;
            }
        };
    };
}

fn indexOf(comptime T: type, ptr: *T, start_ptr: *T) usize {
    return @divExact((@ptrToInt(ptr) - @ptrToInt(start_ptr)), @sizeOf(T));
}

const ROOMS = 6;
fn generateRooms(chunk: *Chunk, ally: Allocator) !void {
    var potential_rooms = blk: {
        var potential_rooms = std.ArrayList(PotentialRoom).init(ally);
        // TODO add randomness to ROOMS
        try potential_rooms.ensureTotalCapacity(ROOMS);

        potential_rooms.appendSlice(&[_]PotentialRoom{
            .{ .width = 0, .height = 0, .pos = .{ .x = chunk.pos.x - Height - 1, .y = chunk.pos.y - 1 }, .connections = undefined },
            .{ .width = 0, .height = 0, .pos = .{ .x = chunk.pos.x + Width / 2, .y = chunk.pos.y + Height + Width / 2 + 1 }, .connections = undefined },
            .{ .width = 0, .height = 0, .pos = .{ .x = chunk.pos.x + Width + Height, .y = chunk.pos.y - 1 }, .connections = undefined },
        }) catch unreachable;

        // generate rooms
        var i: usize = 0;
        while (i < ROOMS) : (i += 1) {
            const width = chunk.rng.intRangeAtMost(u32, 8, 15);
            const height = chunk.rng.intRangeAtMost(u32, 8, 15);
            potential_rooms.append(.{
                .pos = .{
                    .x = chunk.rng.intRangeAtMost(isize, chunk.pos.x, chunk.pos.x + Width - @as(isize, width) - 1),
                    .y = chunk.rng.intRangeAtMost(isize, chunk.pos.y, chunk.pos.y + Height - @as(isize, height) - 1),
                },
                .width = width,
                .height = height,
                .connections = std.ArrayListUnmanaged(*PotentialRoom){},
            }) catch unreachable;
        }

        // remove intersecting rooms
        var j: usize = 3;
        while (j < potential_rooms.items.len) : (j += 1) {
            var k: usize = j + 1;
            while (k < potential_rooms.items.len) : (k += 1) {
                var room = potential_rooms.items[j];
                var other = potential_rooms.items[k];

                const gap = 6;
                if (other.pos.y < room.pos.y + room.height + gap and other.pos.x < room.pos.x + room.width + gap and other.pos.y + other.height + gap > room.pos.y and other.pos.x + other.width + gap > room.pos.x) {
                    _ = potential_rooms.orderedRemove(k);
                }
            }
        }

        break :blk potential_rooms.toOwnedSlice();
    };

    // Construct list of pointers to potential rooms for passing between triangles and building rooms
    var room_pointers = try ally.alloc(*PotentialRoom, potential_rooms.len);
    for (potential_rooms) |*room, i| room_pointers[i] = room;

    var triangles = LinkedList(Triangle, "list"){ .head = null };
    var bounds = try Triangle.init(ally, .{ room_pointers[0], room_pointers[1], room_pointers[2] }, &.{});
    try bounds.contains.appendSlice(ally, room_pointers[3..]);
    triangles.insert(&bounds.list);

    var tri = bounds;
    loop: while (true) {
        // Set p to point in tri
        var p = tri.contains.items[0];
        // Create three triangle formed from the points of tri and p
        var t1 = try Triangle.init(ally, .{ tri.points[0], tri.points[1], p }, &.{});
        var t2 = try Triangle.init(ally, .{ tri.points[1], tri.points[2], p }, &.{});
        var t3 = try Triangle.init(ally, .{ tri.points[2], tri.points[0], p }, &.{});
        _ = tri.list.insert_after(&t1.list);
        _ = tri.list.insert_after(&t2.list);
        _ = tri.list.insert_after(&t3.list);

        // Copy points contained withing tri, to one of the newly created triangles which contains it
        for (tri.contains.items) |r| {
            if (r == p) continue;
            inline for ([_]*Triangle{ t1, t2, t3 }) |t| {
                if (t.is_inside(r)) try t.contains.append(ally, r);
            }
        }

        // Build connections between p at points of parent triangle going both ways
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            try p.connections.append(ally, tri.points[i]);
            try tri.points[i].connections.append(ally, p);
        }

        var old = tri;
        // defer old.deinit(ally);
        defer old.deinit(ally);

        // Get new tri as first triangle from list containing points. If none have points, return.
        var tri_n = tri.list.next;
        while (tri_n) |n| : (tri_n = n.next) {
            if (n.data().contains.items.len > 0) {
                tri = n.data();
                break;
            }
        } else break :loop;
    }

    // Generate rooms and bounds
    chunk.rooms = try ally.alloc(Room, potential_rooms.len - 3);
    for (chunk.rooms) |*r, i| {
        var room = potential_rooms[i + 3];

        r.* = .{
            .pos = room.pos,
            .width = room.width,
            .height = room.height,
            .halls = .{},
        };
    }
    var room_connector = try Room.Connector.init(ally, chunk.rooms);
    defer room_connector.deinit();

    // Connect together chunk rooms based on potential rooms connections
    // Assumed potential room connections are two way
    for (chunk.rooms) |*r, i| {
        var room = potential_rooms[i + 3];
        for (room.connections.items) |l| {
            const l_idx = indexOf(PotentialRoom, l, &potential_rooms[0]);
            if (l_idx < 3 or l_idx < i) continue;
            try room_connector.join(r, &chunk.rooms[l_idx - 3]);
        }
    }
}
