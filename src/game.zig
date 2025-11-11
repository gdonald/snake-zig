const std = @import("std");
const types = @import("types.zig");
const snake = @import("snake.zig");
const config = @import("config.zig");

pub const Game = struct {
    snake_instance: snake.Snake,
    food_position: types.Position,
    score: u32,
    state: types.GameState,
    grid_width: u32,
    grid_height: u32,
    tick_counter: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Game {
        return Game{
            .snake_instance = try snake.Snake.init(allocator, width / 2, height / 2),
            .food_position = types.Position{ .x = 0, .y = 0 },
            .score = 0,
            .state = .Playing,
            .grid_width = width,
            .grid_height = height,
            .tick_counter = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Game) void {
        self.snake_instance.deinit();
    }

    pub fn reset(self: *Game) !void {
        self.snake_instance.deinit();
        self.snake_instance = try snake.Snake.init(self.allocator, self.grid_width / 2, self.grid_height / 2);
        self.score = 0;
        self.state = .Playing;
        self.tick_counter = 0;
        try self.spawnFood();
    }

    pub fn update(self: *Game) !void {
        if (self.state != .Playing) return;

        self.tick_counter += 1;

        try self.snake_instance.move(self.grid_width, self.grid_height);

        const head = self.snake_instance.body.items[0];

        if (config.USE_WALLS and head.isOutOfBounds(self.grid_width, self.grid_height)) {
            self.state = .GameOver;
            return;
        }

        if (self.snake_instance.checkSelfCollision()) {
            self.state = .GameOver;
            return;
        }

        if (head.x == self.food_position.x and head.y == self.food_position.y) {
            self.snake_instance.grow();
            self.score += config.BASE_POINTS_PER_FOOD;
            try self.spawnFood();
        }
    }

    pub fn changeDirection(self: *Game, direction: types.Direction) void {
        self.snake_instance.changeDirection(direction);
    }

    pub fn togglePause(self: *Game) void {
        if (self.state == .Playing) {
            self.state = .Paused;
        } else if (self.state == .Paused) {
            self.state = .Playing;
        }
    }

    pub fn getCurrentSpeed(self: *Game) u64 {
        const speed_level = self.score / config.SPEED_INCREASE_INTERVAL;
        return config.INITIAL_TICK_RATE + speed_level;
    }

    pub fn spawnFood(self: *Game) !void {
        var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
        const random = rng.random();

        while (true) {
            const x = random.intRangeAtMost(u32, 0, self.grid_width - 1);
            const y = random.intRangeAtMost(u32, 0, self.grid_height - 1);
            const pos = types.Position{ .x = x, .y = y };

            if (!self.snake_instance.contains(pos)) {
                self.food_position = pos;
                break;
            }
        }
    }
};
