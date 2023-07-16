const std = @import("std");
const io = std.io;
const os = std.os;

const termbox = @import("termbox");
const Termbox = termbox.Termbox;
const Style = termbox.Style;

pub const Context = struct {
    term: *Termbox,
    offset_x: usize,
    offset_y: usize,
    height: usize,
    width: usize,
    at: usize = 0,

    const Error = error{ OutOfMemory, OutOfBounds };

    pub fn init(lines: usize, cols: usize, term: *Termbox) Context {
        return .{
            .term = term,
            .offset_x = 0,
            .offset_y = 0,
            .height = lines,
            .width = cols,
        };
    }

    // Creates a subcontext with relative (to the parent) x, y, lines, cols.
    pub fn subcontext(ctx: *Context, y: usize, x: usize, lines: usize, cols: usize) Error!Context {
        if (x >= ctx.width or y >= ctx.height)
            return error.OutOfBounds;

        return Context{
            .term = ctx.term,

            .offset_x = ctx.offset_x + x,
            .offset_y = ctx.offset_y + y,

            .height = lines,
            .width = cols,
        };
    }

    pub fn move(ctx: *Context, x: usize, y: usize) Error!void {
        if (x >= ctx.width or y >= ctx.height) return error.OutOfBounds;
        ctx.at = y * ctx.width + x;
    }

    pub fn setCell(ctx: *Context, x: usize, y: usize, ch: u21, style: Style) !void {
        if (x >= ctx.width or y >= ctx.height) return error.OutOfBounds;

        ctx.term.setCell(
            x,
            y,
            ch,
            style,
        );
    }

    pub const WriteError = os.WriteError || Error;

    // fallback for bytes that are not valid utf8
    fn writeBytes(self: *Context, bytes: []const u8) WriteError!usize {
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
                try self.putAt(at_x, at_y, c);
            }

            written += 1;
            at_x += 1;
        }

        self.at = at_y * self.width + at_x;

        return written;
    }

    // Writes the string as utf8 code points to the print buffer
    fn writeUnicode(self: *Context, bytes: []const u8) WriteError!usize {
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
                try self.putAt(at_x, at_y, c);
            }

            written += u_size;
            at_x += 1;
            i += u_size;
        }

        self.at = at_y * self.width + at_x;

        return written;
    }

    // implement the zig io.write interface
    pub fn write(ctx: *Context, bytes: []const u8) WriteError!usize {
        if (!std.unicode.utf8ValidateSlice(bytes))
            return ctx.writeBytes(bytes)
        else
            return ctx.writeUnicode(bytes);
    }

    pub const Writer = io.Writer(*Context, WriteError, write);
    pub fn writer(ctx: *Context) Writer {
        return .{ .context = ctx };
    }

    // fmt print interface
    pub fn print(ctx: *Context, comptime format: []const u8, args: anytype) WriteError!void {
        var w = ctx.writer();
        return w.print(format, args);
    }

    // fmt print interface with a specified position
    pub fn printAt(ctx: *Context, comptime format: []const u8, args: anytype, x: usize, y: usize) WriteError!void {
        try ctx.move(x, y);

        var w = ctx.writer();
        return w.print(format, args);
    }

    pub fn putAt(ctx: *Context, x: usize, y: usize, ch: u21) WriteError!void {
        try ctx.setCell(x, y, ch, .{});
    }

    pub fn putN(ctx: *Context, x: usize, y: usize, ch: u21, n: usize) WriteError!void {
        var i: isize = 0;
        while (i < n) : (i += 1) {
            try ctx.putAt(x + i, y, ch);
        }
    }
};

// Drawable type to enable a window view of a larger plane. Aims to implement the api of Context but take in isize coordinates.
// any drawing outside the context will be a noop.
pub const Window = struct {
    ctx: Context,
    pos: @import("Pos.zig"),

    pub const Error = Context.Error;
    pub const WriteError = Context.WriteError;

    fn isOutOfBounds(win: Window, x: isize, y: isize) bool {
        return (x < win.pos.x or y - win.pos.y > win.ctx.height or x >= win.pos.x + @intCast(isize, win.ctx.width) or y <= win.pos.y);
    }

    pub fn move(win: *Window, x: isize, y: isize) void {
        if (win.isOutOfBounds(x, y)) return;

        const rel_x = x - win.pos.x;
        const rel_y = @intCast(isize, win.ctx.height) - (y - win.pos.y);

        win.ctx.move(@intCast(usize, rel_x), @intCast(usize, rel_y)) catch unreachable;
    }

    pub fn setCell(win: *Window, x: isize, y: isize, ch: u21, style: Style) void {
        if (win.isOutOfBounds(x, y)) return;

        const rel_x = x - win.pos.x;
        const rel_y = @intCast(isize, win.ctx.height) - (y - win.pos.y);

        win.ctx.setCell(@intCast(usize, rel_x), @intCast(usize, rel_y), ch, style) catch unreachable;
    }

    // Writes the chars to the buffer horizontally right
    pub fn putHorizontal(win: *Window, x: isize, y: isize, chars: []const u21) void {
        for (chars) |c, i| {
            win.putAt(x + @intCast(isize, i), y, c);
        }
    }

    // Writes the chars to the buffer vertically down
    pub fn putVertical(win: *Window, x: isize, y: isize, chars: []const u21) void {
        for (chars) |c, i| {
            win.putAt(x, y + chars.len - @intCast(isize, i), c);
        }
    }

    pub fn putAt(win: *Window, x: isize, y: isize, ch: u21) void {
        win.setCell(x, y, ch, .{});
    }

    // Write ch n times horizontally right
    // TODO optimise by using win.ctx.putAt in the loop
    pub fn putNHorizontal(win: *Window, x: isize, y: isize, ch: u21, n: usize) void {
        var i: isize = 0;
        while (i < n) : (i += 1) {
            win.putAt(x + i, y, ch);
        }
    }

    // Write ch n times vertically down
    // TODO optimise by using win.ctx.putAt in the loop
    pub fn putNVertical(win: *Window, x: isize, y: isize, ch: u21, n: usize) void {
        var i: isize = 0;
        while (i < n) : (i += 1) {
            win.putAt(x, y + n - i, ch);
        }
    }
};
