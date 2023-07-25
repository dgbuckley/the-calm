const std = @import("std");

const Allocator = std.mem.Allocator;

const Line = Pos.Line;
const Pos = @import("Pos.zig");
const Room = @import("Room.zig");

const Chunk = @This();

pos: Pos,
rooms: std.ArrayListUnmanaged(*Room),
rng: std.rand.Random,

const Width: isize = 120;
const Height: isize = 120;

pub fn init(ally: Allocator, pos: Pos, rng: std.rand.Random) Allocator.Error!*Chunk {
    std.debug.assert(@mod(pos.x, Chunk.Width) == 0 and @mod(pos.y, Chunk.Height) == 0);
    var chunk: *Chunk = try ally.create(Chunk);
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

const Point = struct {
    // Bottom left of a room
    p: Pos,
    // All neighbors
    n: std.AutoHashMapUnmanaged(usize, *Point),
    id: usize,
};

const Triangle = struct {
    // Three points in clockwise orientation, making a traingle
    points: [3]*Point,
    contains: std.ArrayListUnmanaged(*Point),
    list: LinkedList(Triangle, "list").Node,

    // Three points in clockwise orientation, making a traingle
    fn init(ally: Allocator, points: [3]*Point, contains: []const *Point) !*Triangle {
        std.debug.assert(Pos.orientation(points[0].p, points[1].p, points[2].p) == .Clockwise);

        var t = try ally.create(Triangle);
        t.* = Triangle{
            .points = points,
            .contains = std.ArrayListUnmanaged(*Point){},
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

    fn is_inside(t: Triangle, p: *Point) bool {
        const o1 = Pos.orientation(t.points[0].p, t.points[1].p, p.p);
        const o2 = Pos.orientation(t.points[1].p, t.points[2].p, p.p);
        const o3 = Pos.orientation(t.points[2].p, t.points[0].p, p.p);

        return (o1 == .Clockwise and o1 == o2 and o1 == o3);
    }

    // Returns true if the point is inside a circle formed by the triangles 3 points.
    fn in_circle(tri: Triangle, p: Point) bool {
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
            .{ tri.points[2].p.x, tri.points[2].p.y, (std.math.pow(isize, tri.points[2].p.x, 2) + std.math.pow(isize, tri.points[2].p.y, 2)), 1 },
            .{ tri.points[1].p.x, tri.points[1].p.y, (std.math.pow(isize, tri.points[1].p.x, 2) + std.math.pow(isize, tri.points[1].p.y, 2)), 1 },
            .{ tri.points[0].p.x, tri.points[0].p.y, (std.math.pow(isize, tri.points[0].p.x, 2) + std.math.pow(isize, tri.points[0].p.y, 2)), 1 },
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

test "Triangle in_circle" {
    // TODO replace usage of Pos with Point then uncomment test

    // const testing = std.testing;
    // var tri = try Triangle.init(testing.allocator, .{ Pos{ .x = -100, .y = 100 }, Pos{ .x = 100, .y = 100 }, Pos{ .x = 100, .y = -100 } }, &[_]*Point{});
    // defer tri.deinit(testing.allocator);

    // // Inside triangle, guarateed inside
    // try testing.expect(tri.in_circle(Pos{ .x = 50, .y = 50 }));

    // // Guaranteed outside by orientation
    // try testing.expect(!tri.in_circle(Pos{ .x = 150, .y = 150 }));
    // try testing.expect(!tri.in_circle(Pos{ .x = -200, .y = 150 }));
    // try testing.expect(!tri.in_circle(Pos{ .x = 150, .y = -200 }));

    // // Outside triangle, inside circle
    // try testing.expect(tri.in_circle(Pos{ .x = -50, .y = -50 }));
    // try testing.expect(tri.in_circle(Pos{ .x = 110, .y = 0 }));
    // try testing.expect(tri.in_circle(Pos{ .x = 0, .y = 110 }));

    // // Outside
    // try testing.expect(!tri.in_circle(Pos{ .x = -200, .y = -200 }));
    // try testing.expect(!tri.in_circle(Pos{ .x = 200, .y = 0 }));
    // try testing.expect(!tri.in_circle(Pos{ .x = 0, .y = 200 }));
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

                return self;
            }
        };
    };
}

fn halls_from_points(ally: Allocator, point: *Point, room_map: [ROOMS]?*Room) !void {
    var neighbors = blk: {
        var it = point.n.iterator();
        var list = std.ArrayListUnmanaged(*Point){};
        while (it.next()) |n| {
            _ = n.value_ptr.*.n.remove(point.id);
            try list.append(ally, n.value_ptr.*);
        }
        break :blk list.toOwnedSlice(ally);
    };
    point.n.clearAndFree(ally);

    for (neighbors) |n| {
        if (n.id == std.math.maxInt(usize)) continue;
        try room_map[point.id].?.join(ally, room_map[n.id].?);
        try halls_from_points(ally, n, room_map);
    }
}

const ROOMS = 6;
fn generateRooms(chunk: *Chunk, ally: Allocator) !void {

    // room_store stores the rooms in memory
    var room_store: [ROOMS]PotentialRoom = undefined;

    // generate 50 random rooms
    for (room_store) |*room| {
        const width = chunk.rng.intRangeAtMost(u32, 8, 15);
        const height = chunk.rng.intRangeAtMost(u32, 8, 15);
        const x = chunk.rng.intRangeAtMost(isize, chunk.pos.x, chunk.pos.x + Width - @as(isize, width) - 1);
        const y = chunk.rng.intRangeAtMost(isize, chunk.pos.y, chunk.pos.y + Height - @as(isize, height) - 1);

        room.* = PotentialRoom{
            .pos = .{ .x = x, .y = y },
            .width = width,
            .height = height,
            .connections = std.ArrayListUnmanaged(usize){},
        };
    }

    // Use optional pointers to eliminate rooms
    var rooms: [ROOMS + 3]?Point = undefined;
    for (rooms[3..]) |*room, i| {
        room.* = Point{ .id = i, .p = room_store[i].pos, .n = .{} };
    }
    // Add Bounding points fully encompasing chunck in triangle
    rooms[0] = Point{ .p = Pos{ .x = chunk.pos.x - Height - 1, .y = chunk.pos.y - 1 }, .id = std.math.maxInt(usize), .n = .{} };
    rooms[1] = Point{ .p = Pos{ .x = chunk.pos.x + Width / 2, .y = chunk.pos.y + Height + Width / 2 + 1 }, .id = std.math.maxInt(usize), .n = .{} };
    rooms[2] = Point{ .p = Pos{ .x = chunk.pos.x + Width + Height, .y = chunk.pos.y - 1 }, .id = std.math.maxInt(usize), .n = .{} };

    for (rooms[3..]) |maybe_room, i| {
        var room = room_store[maybe_room.?.id];
        for (rooms[3 + i + 1 ..]) |maybe_r| {
            if (maybe_r == null) continue;
            var r = room_store[maybe_r.?.id];

            const gap: isize = 6;
            if (r.pos.y < room.pos.y + room.height + gap and r.pos.x < room.pos.x + room.width + gap and r.pos.y + r.height + gap > room.pos.y and r.pos.x + r.width + gap > room.pos.x) {
                rooms[i + 3] = null;
                break;
            }
        }
    }

    var triangle_buf = std.heap.ArenaAllocator.init(ally);
    defer triangle_buf.deinit();

    var triangles = LinkedList(Triangle, "list"){ .head = null };

    var bounds = try Triangle.init(triangle_buf.allocator(), [3]*Point{ &rooms[0].?, &rooms[1].?, &rooms[2].? }, &.{});
    for (rooms[3..]) |*p| {
        if (p.* == null) continue;
        std.debug.assert(bounds.is_inside(&p.*.?));
        try bounds.contains.append(ally, &p.*.?);
    }

    triangles.insert(&bounds.list);

    var point = bounds.contains.pop();
    var tri = bounds;
    loop: while (true) {
        var t1 = try Triangle.init(triangle_buf.allocator(), .{ tri.points[0], tri.points[1], point }, &.{});
        var t2 = try Triangle.init(triangle_buf.allocator(), .{ tri.points[1], tri.points[2], point }, &.{});
        var t3 = try Triangle.init(triangle_buf.allocator(), .{ tri.points[2], tri.points[0], point }, &.{});
        _ = tri.list.insert_after(&t1.list);
        _ = tri.list.insert_after(&t2.list);
        _ = tri.list.insert_after(&t3.list);

        // move all points into the new triangles
        for ([_]*Triangle{ t1, t2, t3 }) |t| {
            for (t.points) |p, i| {
                var p1 = t.points[(i + 1) % 3];
                var p2 = t.points[(i + 2) % 3];

                try p.n.put(ally, p1.id, p1);
                try p.n.put(ally, p2.id, p2);
            }

            for (tri.contains.items) |p| {
                // Can be optimized by no running oriantation for each point more than just on each newly created line
                if (t.is_inside(p)) try t.contains.append(ally, p);
            }
        }

        // TODO check for delaunay and swap if needed

        var old = tri;
        defer old.deinit(triangle_buf.allocator());
        tri = if (tri.list.next) |t| t.data() else break;
        point = tri.contains.popOrNull() orelse blk: {
            var n = tri.list.next;
            while (n) |next_node| : (n = next_node.next) {
                var next = next_node.data();
                var p = next.contains.popOrNull() orelse continue;
                tri = next;
                break :blk p;
            } else break :loop;
        };
    }

    var room_map: [ROOMS]?*Room = .{null} ** ROOMS;
    for (rooms[3..]) |mp| {
        if (mp == null) continue;
        var p = mp.?;

        var r = try Room.init(ally, p.p, room_store[p.id].width, room_store[p.id].height);
        try chunk.rooms.append(ally, r);
        room_map[p.id] = r;
    }

    var node: ?Point = blk: {
        for (rooms[3..]) |mp| {
            if (mp) |p| break :blk p;
        } else break :blk null;
    };

    if (node) |*n| try halls_from_points(ally, n, room_map);
}
