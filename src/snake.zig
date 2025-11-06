const std = @import("std");
const types = @import("types.zig");

pub const Snake = struct {
    body: std.ArrayList(types.Position),
    direction: types.Direction,
    growth_pending: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, start_x: u32, start_y: u32) !Snake {
        var body = std.ArrayList(types.Position).init(allocator);
        try body.append(types.Position{ .x = start_x, .y = start_y });

        return Snake{
            .body = body,
            .direction = .Right,
            .growth_pending = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Snake) void {
        self.body.deinit();
    }

    pub fn move(self: *Snake, grid_width: u32, grid_height: u32) !void {
        const head = self.body.items[0];
        const new_head = head.moveInDirection(self.direction, grid_width, grid_height);

        try self.body.insert(0, new_head);

        if (self.growth_pending > 0) {
            self.growth_pending -= 1;
        } else {
            _ = self.body.pop();
        }
    }

    pub fn grow(self: *Snake) void {
        self.growth_pending += 1;
    }

    pub fn checkSelfCollision(self: *Snake) bool {
        const head = self.body.items[0];
        for (self.body.items[1..]) |segment| {
            if (head.x == segment.x and head.y == segment.y) {
                return true;
            }
        }
        return false;
    }

    pub fn contains(self: *Snake, position: types.Position) bool {
        for (self.body.items) |segment| {
            if (segment.x == position.x and segment.y == position.y) {
                return true;
            }
        }
        return false;
    }

    pub fn changeDirection(self: *Snake, new_direction: types.Direction) void {
        const opposite = switch (self.direction) {
            .Up => types.Direction.Down,
            .Down => types.Direction.Up,
            .Left => types.Direction.Right,
            .Right => types.Direction.Left,
        };

        if (new_direction != opposite) {
            self.direction = new_direction;
        }
    }
};
