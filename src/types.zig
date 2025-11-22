const std = @import("std");

pub const Position = struct {
    x: u32,
    y: u32,

    pub fn moveInDirection(self: Position, direction: Direction, grid_width: u32, grid_height: u32, wrap: bool) Position {
        var new_pos = self;
        switch (direction) {
            .Up => {
                if (wrap) {
                    new_pos.y = (self.y + grid_height - 1) % grid_height;
                } else {
                    new_pos.y = if (self.y == 0) grid_height else self.y - 1;
                }
            },
            .Down => {
                if (wrap) {
                    new_pos.y = (self.y + 1) % grid_height;
                } else {
                    new_pos.y = if (self.y + 1 >= grid_height) grid_height else self.y + 1;
                }
            },
            .Left => {
                if (wrap) {
                    new_pos.x = (self.x + grid_width - 1) % grid_width;
                } else {
                    new_pos.x = if (self.x == 0) grid_width else self.x - 1;
                }
            },
            .Right => {
                if (wrap) {
                    new_pos.x = (self.x + 1) % grid_width;
                } else {
                    new_pos.x = if (self.x + 1 >= grid_width) grid_width else self.x + 1;
                }
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
