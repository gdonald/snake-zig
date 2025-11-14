const std = @import("std");
const vaxis = @import("vaxis");
const game = @import("game.zig");
const types = @import("types.zig");
const config = @import("config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    try loop.start();
    defer loop.stop();

    var game_instance = try game.Game.init(allocator, config.GRID_WIDTH, config.GRID_HEIGHT);
    defer game_instance.deinit();
    try game_instance.spawnFood();

    var last_tick_ns: i128 = std.time.nanoTimestamp();
    const tick_interval_ns: i128 = 100_000_000;

    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                    break;
                }

                if (game_instance.state == .GameOver) {
                    if (key.matches('r', .{})) {
                        try game_instance.reset();
                        last_tick_ns = std.time.nanoTimestamp();
                    }
                } else {
                    if (key.matches('p', .{}) or key.matches(' ', .{})) {
                        game_instance.togglePause();
                    }

                    if (game_instance.state == .Playing) {
                        if (key.matches(vaxis.Key.up, .{}) or key.matches('w', .{})) {
                            game_instance.changeDirection(.Up);
                        } else if (key.matches(vaxis.Key.down, .{}) or key.matches('s', .{})) {
                            game_instance.changeDirection(.Down);
                        } else if (key.matches(vaxis.Key.left, .{}) or key.matches('a', .{})) {
                            game_instance.changeDirection(.Left);
                        } else if (key.matches(vaxis.Key.right, .{}) or key.matches('d', .{})) {
                            game_instance.changeDirection(.Right);
                        }
                    }

                    if (key.matches('r', .{})) {
                        try game_instance.reset();
                        last_tick_ns = std.time.nanoTimestamp();
                    }
                }
            },
            .winsize => |ws| {
                try vx.resize(allocator, tty.writer(), ws);
            },
        }

        const current_time = std.time.nanoTimestamp();
        if (current_time - last_tick_ns >= tick_interval_ns) {
            try game_instance.update();
            last_tick_ns = current_time;
        }

        const win = vx.window();
        win.clear();

        try renderGame(win, &game_instance);

        try vx.render(tty.writer());
    }
}

fn renderGame(win: vaxis.Window, game_instance: *game.Game) !void {
    const border_offset_x: u16 = 2;
    const border_offset_y: u16 = 2;

    const border_style = vaxis.Style{
        .fg = .{ .rgb = [_]u8{ 150, 150, 150 } },
    };

    var i: u16 = 0;
    while (i < config.GRID_WIDTH + 2) : (i += 1) {
        const top_seg = vaxis.Segment{ .text = "#", .style = border_style };
        const bottom_seg = vaxis.Segment{ .text = "#", .style = border_style };
        _ = win.printSegment(top_seg, .{ .col_offset = border_offset_x + i, .row_offset = border_offset_y });
        _ = win.printSegment(bottom_seg, .{ .col_offset = border_offset_x + i, .row_offset = border_offset_y + config.GRID_HEIGHT + 1 });
    }

    i = 0;
    while (i < config.GRID_HEIGHT + 2) : (i += 1) {
        const left_seg = vaxis.Segment{ .text = "#", .style = border_style };
        const right_seg = vaxis.Segment{ .text = "#", .style = border_style };
        _ = win.printSegment(left_seg, .{ .col_offset = border_offset_x, .row_offset = border_offset_y + i });
        _ = win.printSegment(right_seg, .{ .col_offset = border_offset_x + config.GRID_WIDTH + 1, .row_offset = border_offset_y + i });
    }

    var y: u32 = 0;
    while (y < config.GRID_HEIGHT) : (y += 1) {
        var x: u32 = 0;
        while (x < config.GRID_WIDTH) : (x += 1) {
            const pos = types.Position{ .x = x, .y = y };
            const col: u16 = border_offset_x + 1 + @as(u16, @intCast(x));
            const row: u16 = border_offset_y + 1 + @as(u16, @intCast(y));

            if (game_instance.snake_instance.contains(pos)) {
                const head = game_instance.snake_instance.body.items[0];
                const char = if (pos.x == head.x and pos.y == head.y)
                    &[_]u8{config.SNAKE_HEAD_CHAR}
                else
                    &[_]u8{config.SNAKE_BODY_CHAR};

                const seg = vaxis.Segment{
                    .text = char,
                    .style = .{ .fg = .{ .rgb = [_]u8{ 0, 255, 0 } } },
                };
                _ = win.printSegment(seg, .{ .col_offset = col, .row_offset = row });
            } else if (pos.x == game_instance.food_position.x and pos.y == game_instance.food_position.y) {
                const seg = vaxis.Segment{
                    .text = &[_]u8{config.FOOD_CHAR},
                    .style = .{ .fg = .{ .rgb = [_]u8{ 255, 0, 0 } } },
                };
                _ = win.printSegment(seg, .{ .col_offset = col, .row_offset = row });
            }
        }
    }

    var score_buf: [100]u8 = undefined;
    const score_text = try std.fmt.bufPrint(&score_buf, "Score: {d}", .{game_instance.score});
    const score_seg = vaxis.Segment{
        .text = score_text,
        .style = .{ .fg = .{ .rgb = [_]u8{ 255, 255, 255 } } },
    };
    _ = win.printSegment(score_seg, .{ .col_offset = border_offset_x, .row_offset = border_offset_y + config.GRID_HEIGHT + 3 });

    var speed_buf: [100]u8 = undefined;
    const speed = game_instance.getCurrentSpeed();
    const speed_text = try std.fmt.bufPrint(&speed_buf, "Speed: {d}", .{speed});
    const speed_seg = vaxis.Segment{
        .text = speed_text,
        .style = .{ .fg = .{ .rgb = [_]u8{ 255, 255, 255 } } },
    };
    _ = win.printSegment(speed_seg, .{ .col_offset = border_offset_x + 15, .row_offset = border_offset_y + config.GRID_HEIGHT + 3 });

    const controls_text = "Controls: Arrows/WASD=Move | P/Space=Pause | R=Restart | Q=Quit";
    const controls_seg = vaxis.Segment{
        .text = controls_text,
        .style = .{ .fg = .{ .rgb = [_]u8{ 200, 200, 200 } } },
    };
    _ = win.printSegment(controls_seg, .{ .col_offset = border_offset_x, .row_offset = border_offset_y + config.GRID_HEIGHT + 4 });

    if (game_instance.state == .Paused) {
        const overlay_y: u16 = border_offset_y + @as(u16, @intCast(config.GRID_HEIGHT / 2));
        const pause_text = "PAUSED";
        const pause_col: u16 = border_offset_x + @as(u16, @intCast(config.GRID_WIDTH / 2)) -| @as(u16, @intCast(pause_text.len / 2));
        const pause_seg = vaxis.Segment{
            .text = pause_text,
            .style = .{ .fg = .{ .rgb = [_]u8{ 255, 255, 0 } } },
        };
        _ = win.printSegment(pause_seg, .{ .col_offset = pause_col, .row_offset = overlay_y });

        const resume_text = "Press P or Space to resume";
        const resume_col: u16 = border_offset_x + @as(u16, @intCast(config.GRID_WIDTH / 2)) -| @as(u16, @intCast(resume_text.len / 2));
        const resume_seg = vaxis.Segment{
            .text = resume_text,
            .style = .{ .fg = .{ .rgb = [_]u8{ 200, 200, 200 } } },
        };
        _ = win.printSegment(resume_seg, .{ .col_offset = resume_col, .row_offset = overlay_y + 1 });
    }

    if (game_instance.state == .GameOver) {
        const overlay_y: u16 = border_offset_y + @as(u16, @intCast(config.GRID_HEIGHT / 2));
        const gameover_text = "GAME OVER";
        const gameover_col: u16 = border_offset_x + @as(u16, @intCast(config.GRID_WIDTH / 2)) -| @as(u16, @intCast(gameover_text.len / 2));
        const gameover_seg = vaxis.Segment{
            .text = gameover_text,
            .style = .{ .fg = .{ .rgb = [_]u8{ 255, 0, 0 } } },
        };
        _ = win.printSegment(gameover_seg, .{ .col_offset = gameover_col, .row_offset = overlay_y });

        var final_score_buf: [100]u8 = undefined;
        const final_score_text = try std.fmt.bufPrint(&final_score_buf, "Final Score: {d}", .{game_instance.score});
        const final_score_col: u16 = border_offset_x + @as(u16, @intCast(config.GRID_WIDTH / 2)) -| @as(u16, @intCast(final_score_text.len / 2));
        const final_score_seg = vaxis.Segment{
            .text = final_score_text,
            .style = .{ .fg = .{ .rgb = [_]u8{ 255, 255, 255 } } },
        };
        _ = win.printSegment(final_score_seg, .{ .col_offset = final_score_col, .row_offset = overlay_y + 1 });

        const restart_text = "Press R to restart or Q to quit";
        const restart_col: u16 = border_offset_x + @as(u16, @intCast(config.GRID_WIDTH / 2)) -| @as(u16, @intCast(restart_text.len / 2));
        const restart_seg = vaxis.Segment{
            .text = restart_text,
            .style = .{ .fg = .{ .rgb = [_]u8{ 200, 200, 200 } } },
        };
        _ = win.printSegment(restart_seg, .{ .col_offset = restart_col, .row_offset = overlay_y + 2 });
    }
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};
