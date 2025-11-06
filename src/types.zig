pub const Position = struct {
    x: u32,
    y: u32,

    pub fn moveInDirection(self: Position, direction: Direction, grid_width: u32, grid_height: u32) Position {
        var new_pos = self;
        switch (direction) {
            .Up => {
                if (self.y == 0) {
                    new_pos.y = grid_height - 1;
                } else {
                    new_pos.y -= 1;
                }
            },
            .Down => {
                new_pos.y = (self.y + 1) % grid_height;
            },
            .Left => {
                if (self.x == 0) {
                    new_pos.x = grid_width - 1;
                } else {
                    new_pos.x -= 1;
                }
            },
            .Right => {
                new_pos.x = (self.x + 1) % grid_width;
            },
        }
        return new_pos;
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
    Playing,
    Paused,
    GameOver,
    Victory,
};
