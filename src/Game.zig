const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;
const Random = std.rand.Random;

const Chunk = @import("Chunk.zig");
const Game = @This();

ally: Allocator,
rand: Random,
chunks: List(*Chunk),
active_chunks: List(*Chunk),

// Initialize the game struct. Game data is not setup here and needs to be loaded or generated.
pub fn init(ally: Allocator, rand: Random) !*Game {
    var game = try ally.create(Game);
    game.* = .{
        .ally = ally,
        .rand = rand,
        .chunks = .{},
        .active_chunks = .{},
    };

    return game;
}

// Release the memory used by Game
pub fn deinit(game: *Game) void {
    for (game.chunks.items) |*c| c.*.deinit(game.ally);
    game.chunks.deinit(game.ally);
    game.active_chunks.deinit(game.ally);
    var ally = game.ally;
    ally.destroy(game);
}

// Generate a new game
pub fn newGame(game: *Game) !void {
    try game.chunks.append(game.ally, try Chunk.init(game.ally, .{ .x = 0, .y = 0 }, game.rand));
    try game.active_chunks.append(game.ally, game.chunks.items[0]);
}
