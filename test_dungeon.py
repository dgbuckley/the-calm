#!/bin/env python3

import pytest
from main import tile, dungeon

def test_dungeon_find_wall():
    layout = [[tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL],
        [tile.WALL, tile.NUL, tile.NUL, tile.NUL, tile.NUL, tile.WALL, tile.NUL, tile.NUL, tile.NUL, tile.WALL],
        [tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL],
        [tile.WALL, tile.NUL, tile.NUL, tile.NUL, tile.NUL, tile.WALL, tile.NUL, tile.NUL, tile.NUL, tile.WALL],
        [tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL, tile.WALL]]

    expect = """┌────┬───┐
│    │   │
├────┼───┤
│    │   │
└────┴───┘"""

    d = dungeon(10, 5)
    d.layout = layout
    assert d.print() == expect


map = [[0 for j in range(10)] for k in range(10)]

for k in range(2):
    for j in range(2):
        map[j+1][k+2] = 1

for j in map:
    print(j)