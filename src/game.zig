const std = @import("std");
const types = @import("types.zig");
const snake = @import("snake.zig");
const config = @import("config.zig");

const HIGH_SCORE_FILENAME = "snake_highscore.txt";

fn getHighScoreFilePath(allocator: std.mem.Allocator) ![]u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return std.fs.path.join(allocator, &[_][]const u8{ home, ".config", HIGH_SCORE_FILENAME });
}

fn loadHighScore(allocator: std.mem.Allocator) !u32 {
    const file_path = try getHighScoreFilePath(allocator);
    defer allocator.free(file_path);

    const file = std.fs.openFileAbsolute(file_path, .{}) catch |err| {
        if (err == error.FileNotFound) return 0;
        return err;
    };
    defer file.close();

    var buf: [32]u8 = undefined;
    const bytes_read = try file.readAll(&buf);
    const content = std.mem.trim(u8, buf[0..bytes_read], &std.ascii.whitespace);
    return std.fmt.parseInt(u32, content, 10) catch 0;
}

fn saveHighScore(allocator: std.mem.Allocator, high_score: u32) !void {
    const file_path = try getHighScoreFilePath(allocator);
    defer allocator.free(file_path);

    const dir_path = std.fs.path.dirname(file_path);
    if (dir_path) |dir| {
        std.fs.makeDirAbsolute(dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    const file = try std.fs.createFileAbsolute(file_path, .{});
    defer file.close();

    var buf: [32]u8 = undefined;
    const content = try std.fmt.bufPrint(&buf, "{d}\n", .{high_score});
    try file.writeAll(content);
}

pub const Game = struct {
    snake_instance: snake.Snake,
    food_position: types.Position,
    score: u32,
    high_score: u32,
    state: types.GameState,
    grid_width: u32,
    grid_height: u32,
    tick_counter: u64,
    allocator: std.mem.Allocator,
    queued_direction: ?types.Direction,
    food_collected_flash: u8,
    countdown_ticks: u8,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Game {
        const high_score = loadHighScore(allocator) catch 0;

        var game_state = Game{
            .snake_instance = try snake.Snake.init(allocator, width / 2, height / 2),
            .food_position = types.Position{ .x = std.math.maxInt(u32), .y = std.math.maxInt(u32) },
            .score = 0,
            .high_score = high_score,
            .state = .Countdown,
            .grid_width = width,
            .grid_height = height,
            .tick_counter = 0,
            .allocator = allocator,
            .queued_direction = null,
            .food_collected_flash = 0,
            .countdown_ticks = 30,
        };

        try game_state.spawnFood();
        return game_state;
    }

    pub fn deinit(self: *Game) void {
        self.snake_instance.deinit();
    }

    pub fn reset(self: *Game) !void {
        self.snake_instance.deinit();
        self.snake_instance = try snake.Snake.init(self.allocator, self.grid_width / 2, self.grid_height / 2);
        self.score = 0;
        self.state = .Countdown;
        self.tick_counter = 0;
        self.queued_direction = null;
        self.food_collected_flash = 0;
        self.countdown_ticks = 30;
        try self.spawnFood();
    }

    pub fn update(self: *Game) !void {
        if (self.state == .Countdown) {
            if (self.countdown_ticks > 0) {
                self.countdown_ticks -= 1;
            } else {
                self.state = .Playing;
            }
            return;
        }

        if (self.state != .Playing) return;

        self.tick_counter += 1;

        if (self.food_collected_flash > 0) {
            self.food_collected_flash -= 1;
        }

        if (self.queued_direction) |dir| {
            self.snake_instance.changeDirection(dir);
            self.queued_direction = null;
        }

        try self.snake_instance.move(self.grid_width, self.grid_height, !config.USE_WALLS);

        const head = self.snake_instance.body.items[0];

        if (config.USE_WALLS and head.isOutOfBounds(self.grid_width, self.grid_height)) {
            self.state = .GameOver;
            if (self.score > self.high_score) {
                self.high_score = self.score;
                saveHighScore(self.allocator, self.high_score) catch {};
            }
            return;
        }

        if (self.snake_instance.checkSelfCollision()) {
            self.state = .GameOver;
            if (self.score > self.high_score) {
                self.high_score = self.score;
                saveHighScore(self.allocator, self.high_score) catch {};
            }
            return;
        }

        if (head.x == self.food_position.x and head.y == self.food_position.y) {
            self.snake_instance.grow();
            self.score += config.BASE_POINTS_PER_FOOD;
            self.food_collected_flash = 3;
            try self.spawnFood();
        }
    }

    pub fn changeDirection(self: *Game, direction: types.Direction) void {
        if (self.queued_direction == null) {
            if (self.snake_instance.canChangeDirection(direction)) {
                self.queued_direction = direction;
            }
        }
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

    pub fn getCountdownValue(self: *Game) ?u8 {
        if (self.state != .Countdown) return null;
        // Clamp to 3 so we always render a visible countdown (avoiding stray glyphs when value would be 4).
        return std.math.clamp((self.countdown_ticks / 10) + 1, 1, 3);
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
