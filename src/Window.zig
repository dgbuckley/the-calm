const std = @import("std");
const io = std.io;
const os = std.os;

const termbox = @import("termbox");
const Termbox = termbox.Termbox;
const Style = termbox.Style;

const Pos = @import("./Pos.zig");

const Window = @This();

term: *Termbox,
offset: Pos,
height: usize,
width: usize,
at: usize = 0,

const Errors = error{ OutOfMemory, OutOfBounds };

pub fn init(lines: usize, cols: usize, term: *Termbox) Window {
    return .{
        .term = term,
        .offset = .{ .x = 0, .y = 0 },
        .height = lines,
        .width = cols,
    };
}

fn rel(a: isize, b: isize) usize {
    return std.math.absCast(a - b);
}

pub fn move(self: *Window, x: isize, y: isize) void {
    const abs_x = rel(self.offset.x, x);
    const abs_y = self.height - rel(self.offset.y, y);
    self.at = abs_y * self.width + abs_x;
}

pub fn setCell(self: *Window, x: isize, y: isize, ch: u21, style: Style) void {
    const abs_x = rel(self.offset.x, x);
    const abs_y = self.height - rel(self.offset.y, y);

    self.term.setCell(
        abs_x,
        abs_y,
        ch,
        style,
    );
}

pub const WriteError = os.WriteError;

// implement the Zig writer interface
// TODO handle chars wider than 1
fn writeBytes(self: *Window, bytes: []const u8) WriteError!usize {
    var at_x = self.at % self.width;
    var at_y = self.at / self.width;

    const max_x = self.width;
    const max_y = self.height;

    var written: usize = 0;
    for (bytes) |c| {
        if (c == '\n' or c == '\r') {
            at_y += 1;
            at_x = 0;
            written += 1;
            continue;
        }

        // If we overflow the height value then just return as if we wrote
        // all of the bytes requested. No point in writing bytes that won't
        // be printed.
        if (at_y >= max_y) {
            return bytes.len;
        }

        if (at_x < max_x) {
            try self.putAt(self.offset.x + @intCast(isize, at_x), self.offset.y + @intCast(isize, self.height - at_y), c);
        }

        written += 1;
        at_x += 1;
    }

    self.at = at_y * self.width + at_x;

    return written;
}

fn writeUnicode(self: *Window, bytes: []const u8) WriteError!usize {
    std.debug.assert(std.unicode.utf8ValidateSlice(bytes));

    var at_x = self.at % self.width;
    var at_y = self.at / self.width;

    const max_x = self.width;
    const max_y = self.height;

    var written: usize = 0;

    var i: usize = 0;
    while (i < bytes.len) {
        const u_size = std.unicode.utf8ByteSequenceLength(bytes[i]) catch unreachable;
        const c = std.unicode.utf8Decode(bytes[i .. i + u_size]) catch unreachable;

        if (c == '\n' or c == '\r') {
            at_y += 1;
            at_x = 0;
            written += 1;
            continue;
        }

        // If we overflow the height value then just return as if we wrote
        // all of the bytes requested. No point in writing bytes that won't
        // be printed.
        if (at_y >= max_y) {
            return bytes.len;
        }

        if (at_x < max_x) {
            try self.putAt(self.offset.x + @intCast(isize, at_x), self.offset.y + @intCast(isize, self.height - at_y), c);
        }

        written += u_size;
        at_x += 1;
        i += u_size;
    }

    self.at = at_y * self.width + at_x;

    return written;
}

pub fn write(self: *Window, bytes: []const u8) WriteError!usize {
    if (!std.unicode.utf8ValidateSlice(bytes))
        return self.writeBytes(bytes)
    else
        return self.writeUnicode(bytes);
}

pub const Writer = io.Writer(*Window, WriteError, write);
pub fn writer(win: *Window) Writer {
    return .{ .context = win };
}

// fmt print interface
pub fn print(self: *Window, comptime format: []const u8, args: anytype) WriteError!void {
    var w = self.writer();
    return w.print(format, args);
}

// fmt print interface with a specified position
pub fn printAt(self: *Window, comptime format: []const u8, args: anytype, x: isize, y: isize) WriteError!void {
    self.move(x, y);

    var w = self.writer();
    return w.print(format, args);
}

pub fn putAt(self: *Window, x: isize, y: isize, ch: u21) WriteError!void {
    // Why?
    if (rel(self.offset.x, x) == self.width - 1 and rel(self.offset.y, y) == self.height - 1) {
        self.setCell(x, y, ch, .{});
        return;
    }

    self.setCell(x, y, ch, .{});
}

pub fn putN(self: *Window, x: isize, y: isize, ch: u21, n: usize) WriteError!void {
    var i: isize = 0;
    while (i < n) : (i += 1) {
        try self.putAt(x + i, y, ch);
    }
}
