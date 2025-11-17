const std = @import("std");

pub const Position = struct {
    x: u32,
    y: u32,

    pub fn moveInDirection(self: Position, direction: Direction, _: u32, _: u32) Position {
        var new_pos = self;
        switch (direction) {
            .Up => {
                if (self.y == 0) {
                    new_pos.y = std.math.maxInt(u32);
                } else {
                    new_pos.y -= 1;
                }
            },
            .Down => {
                new_pos.y = self.y + 1;
            },
            .Left => {
                if (self.x == 0) {
                    new_pos.x = std.math.maxInt(u32);
                } else {
                    new_pos.x -= 1;
                }
            },
            .Right => {
                new_pos.x = self.x + 1;
            },
        }
        return new_pos;
    }

    pub fn isOutOfBounds(self: Position, grid_width: u32, grid_height: u32) bool {
        return self.x >= grid_width or self.y >= grid_height;
    }
};

pub const Direction = enum {
    Up,
    Down,
    Left,
    Right,
};

pub const CellType = enum {
    Empty,
    Snake,
    Food,
    Wall,
};

pub const GameState = enum {
    Countdown,
    Playing,
    Paused,
    GameOver,
    Victory,
};
