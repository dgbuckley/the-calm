#!/bin/env python3
from enum import Enum
import random

class tile(Enum):
    INVALID = 0
    NUL = 1
    WALL = 2
    FLOOR = 3


class dungeon:
    walls = {
        0: " ",
        3: "│",
        7: "│",
        10: "│",
        5: "─",
        11: "─",
        16: "─",
        14: "┘",
        18: "┐",
        12: "┌",
        8: "└",
        19: "┴",
        21: "┤",
        23: "┬",
        15: "├",
        26: "┼",
    }

    def __init__(self, x: int, y: int):
        self.layout = [[tile.NUL for rj in range(x)] for j in range(y)]

    def _tile_is(tile, x: int, y: int):
        return tile == layout[y][x]
    
    def generate_room(self, x, y, x_len, y_len):
        for j in range(x_len):
            for k in range(y_len):
                if self.layout[k+y][j+x] != tile.NUL:
                    return 0
        for j in range(x_len):
            for k in range(y_len):
                self.layout[k+y][j+x] = tile.FLOOR
        for j in range(x_len):
            self.layout[y][j+x] = tile.WALL
            self.layout[y+y_len-1][j+x] = tile.WALL
        for j in range(y_len):
            self.layout[y+j][x] = tile.WALL
            self.layout[y+j][x+x_len-1] = tile.WALL
        
        print (x, y, x_len, y_len)
        return 1

    def generate_floor(self):
        fails = 0
        while fails < 5:
            length = random.randint(14, 24)
            width = random.randint(7, 12)
            x = random.randrange(len(self.layout[0])-length)
            y = random.randrange(len(self.layout)-width)
            if self.generate_room(x, y, length, width):
                fails = 0
                print (1)
            else:
                fails += 1

    # above = 3, right = 5, bottom = 7, left = 11
    def find_wall_type(self, x: int, y: int):
        value = 0
        if self.layout[y][x] == tile.WALL:
            if y:
                if self.layout[y - 1][x] == tile.WALL:
                    value += 3
            if x:
                if self.layout[y][x - 1] == tile.WALL:
                    value += 11
            if y != len(self.layout) - 1:
                if self.layout[y + 1][x] == tile.WALL:
                    value += 7
            if x != len(self.layout[0]) - 1:
                if self.layout[y][x + 1] == tile.WALL:
                    value += 5
        return dungeon.walls[value]

    def print(self):
        out = ""
        for j, v in enumerate(self.layout):
            for i, t in enumerate(v):
                if t == tile.WALL:
                    out += self.find_wall_type(i, j)
                else:
                    out += " "
            if j < len(self.layout) - 1:
                out += "\n"
        return out


m = dungeon(100, 50)
m.generate_floor()

# for j in m.layout:
#     print(j)
#     print()

print(m.print())
