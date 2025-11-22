const std = @import("std");
const vaxis = @import("vaxis");
const game = @import("game.zig");
const types = @import("types.zig");
const config = @import("config.zig");

pub const std_options: std.Options = .{
    // Silence vaxis info logs (e.g., kitty capability detection) so they never hit the TUI.
    .log_level = .err,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .vaxis, .level = .err },
    },
    .logFn = ignoredLogFn,
};

fn ignoredLogFn(comptime _: std.log.Level, comptime _: @Type(.enum_literal), comptime _: []const u8, _: anytype) void {}

const grid_vertical_padding: u16 = 5; // top/bottom border + UI rows
const grid_horizontal_padding: u16 = 2; // left/right border
const space_seg = vaxis.Segment{ .text = " " };

fn calculateGridSize(ws: vaxis.Winsize) struct { width: u32, height: u32 } {
    const height = if (ws.rows > grid_vertical_padding) ws.rows - grid_vertical_padding else 1;
    const width = if (ws.cols > grid_horizontal_padding) ws.cols - grid_horizontal_padding else 1;
    return .{
        .width = @as(u32, @intCast(width)),
        .height = @as(u32, @intCast(height)),
    };
}

fn clearRow(win: vaxis.Window, row: u16, width: u16) void {
    var i: u16 = 0;
    while (i < width) : (i += 1) {
        _ = win.printSegment(space_seg, .{ .col_offset = i, .row_offset = row });
    }
}

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

    try vx.queryTerminalSend(tty.writer());
    const initial_winsize = loop.nextEvent();
    const winsize: vaxis.Winsize = switch (initial_winsize) {
        .winsize => |ws| blk: {
            try vx.resize(allocator, tty.writer(), ws);
            break :blk ws;
        },
        else => .{ .rows = 24, .cols = 80, .x_pixel = 0, .y_pixel = 0 },
    };

    const initial_grid = calculateGridSize(winsize);
    const grid_width = initial_grid.width;
    const grid_height = initial_grid.height;

    var game_instance = try game.Game.init(allocator, grid_width, grid_height);
    defer game_instance.deinit();

    var last_tick_ns: i128 = std.time.nanoTimestamp();
    const tick_interval_ns: i128 = 150_000_000;

    while (true) {
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                        return;
                    }

                    if (key.matches('n', .{})) {
                        try game_instance.reset();
                        last_tick_ns = std.time.nanoTimestamp();
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

                        if (key.matches(vaxis.Key.up, .{}) or key.matches('w', .{})) {
                            game_instance.changeDirection(.Up);
                        } else if (key.matches(vaxis.Key.down, .{}) or key.matches('s', .{})) {
                            game_instance.changeDirection(.Down);
                        } else if (key.matches(vaxis.Key.left, .{}) or key.matches('a', .{})) {
                            game_instance.changeDirection(.Left);
                        } else if (key.matches(vaxis.Key.right, .{}) or key.matches('d', .{})) {
                            game_instance.changeDirection(.Right);
                        }

                        if (key.matches('r', .{})) {
                            try game_instance.reset();
                            last_tick_ns = std.time.nanoTimestamp();
                        }
                    }
                },
                .winsize => |ws| {
                    try vx.resize(allocator, tty.writer(), ws);
                    const new_grid = calculateGridSize(ws);
                    if (new_grid.width != game_instance.grid_width or new_grid.height != game_instance.grid_height) {
                        game_instance.deinit();
                        game_instance = try game.Game.init(allocator, new_grid.width, new_grid.height);
                    }
                },
            }
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

        std.Thread.sleep(8_000_000);
    }
}

fn renderGame(win: vaxis.Window, game_instance: *game.Game) !void {
    const border_offset_x: u16 = 0;
    const border_offset_y: u16 = 0;
    const grid_width = @as(u16, @intCast(game_instance.grid_width));
    const grid_height = @as(u16, @intCast(game_instance.grid_height));

    const border_style = vaxis.Style{
        .fg = .{ .rgb = [_]u8{ 150, 150, 150 } },
    };

    var i: u16 = 0;
    while (i < grid_width + 2) : (i += 1) {
        const top_seg = vaxis.Segment{ .text = "#", .style = border_style };
        const bottom_seg = vaxis.Segment{ .text = "#", .style = border_style };
        _ = win.printSegment(top_seg, .{ .col_offset = border_offset_x + i, .row_offset = border_offset_y });
        _ = win.printSegment(bottom_seg, .{ .col_offset = border_offset_x + i, .row_offset = border_offset_y + grid_height + 1 });
    }

    i = 0;
    while (i < grid_height + 2) : (i += 1) {
        const left_seg = vaxis.Segment{ .text = "#", .style = border_style };
        const right_seg = vaxis.Segment{ .text = "#", .style = border_style };
        _ = win.printSegment(left_seg, .{ .col_offset = border_offset_x, .row_offset = border_offset_y + i });
        _ = win.printSegment(right_seg, .{ .col_offset = border_offset_x + grid_width + 1, .row_offset = border_offset_y + i });
    }

    var y: u32 = 0;
    while (y < game_instance.grid_height) : (y += 1) {
        var x: u32 = 0;
        while (x < game_instance.grid_width) : (x += 1) {
            const pos = types.Position{ .x = x, .y = y };
            const col: u16 = border_offset_x + 1 + @as(u16, @intCast(x));
            const row: u16 = border_offset_y + 1 + @as(u16, @intCast(y));

            if (game_instance.snake_instance.contains(pos)) {
                const head = game_instance.snake_instance.body.items[0];
                const is_head = pos.x == head.x and pos.y == head.y;
                const char = if (is_head)
                    &[_]u8{config.SNAKE_HEAD_CHAR}
                else
                    &[_]u8{config.SNAKE_BODY_CHAR};

                const color: [3]u8 = if (is_head and game_instance.food_collected_flash > 0)
                    [_]u8{ 255, 255, 0 }
                else
                    [_]u8{ 0, 255, 0 };

                const seg = vaxis.Segment{
                    .text = char,
                    .style = .{ .fg = .{ .rgb = color } },
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

    // Clear UI rows to avoid stale characters when text shrinks.
    const ui_width = grid_width + 2;
    clearRow(win, border_offset_y + grid_height + 3, ui_width);
    clearRow(win, border_offset_y + grid_height + 4, ui_width);

    var score_buf: [32]u8 = undefined;
    const score_text = try std.fmt.bufPrint(&score_buf, "Score: {d}", .{game_instance.score});
    const score_color: [3]u8 = if (game_instance.food_collected_flash > 0)
        [_]u8{ 255, 255, 0 }
    else
        [_]u8{ 255, 255, 255 };
    const score_seg = vaxis.Segment{
        .text = score_text,
        .style = .{ .fg = .{ .rgb = score_color } },
    };
    _ = win.printSegment(score_seg, .{ .col_offset = border_offset_x, .row_offset = border_offset_y + grid_height + 3 });

    var speed_buf: [32]u8 = undefined;
    const speed = game_instance.getCurrentSpeed();
    const speed_text = try std.fmt.bufPrint(&speed_buf, "Speed: {d}", .{speed});
    const speed_seg = vaxis.Segment{
        .text = speed_text,
        .style = .{ .fg = .{ .rgb = [_]u8{ 255, 255, 255 } } },
    };
    _ = win.printSegment(speed_seg, .{ .col_offset = border_offset_x + 15, .row_offset = border_offset_y + grid_height + 3 });

    var high_score_buf: [32]u8 = undefined;
    const high_score_text = try std.fmt.bufPrint(&high_score_buf, "High Score: {d}", .{game_instance.high_score});
    const high_score_seg = vaxis.Segment{
        .text = high_score_text,
        .style = .{ .fg = .{ .rgb = [_]u8{ 255, 215, 0 } } },
    };
    _ = win.printSegment(high_score_seg, .{ .col_offset = border_offset_x + 28, .row_offset = border_offset_y + grid_height + 3 });

    const controls_text = "Controls: Arrows/WASD=Move | P/Space=Pause | R/N=Restart | Q=Quit";
    const controls_seg = vaxis.Segment{
        .text = controls_text,
        .style = .{ .fg = .{ .rgb = [_]u8{ 200, 200, 200 } } },
    };
    _ = win.printSegment(controls_seg, .{ .col_offset = border_offset_x, .row_offset = border_offset_y + grid_height + 4 });

    if (game_instance.state == .Countdown) {
        if (game_instance.getCountdownValue()) |countdown| {
            const overlay_y: u16 = border_offset_y + grid_height / 2;
            const countdown_text = switch (countdown) {
                3 => "3",
                2 => "2",
                1 => "1",
                else => "GO",
            };
            const countdown_col: u16 = border_offset_x + (grid_width / 2) -| @as(u16, @intCast(countdown_text.len / 2));
            const countdown_seg = vaxis.Segment{
                .text = countdown_text,
                .style = .{ .fg = .{ .rgb = [_]u8{ 255, 255, 0 } } },
            };
            _ = win.printSegment(countdown_seg, .{ .col_offset = countdown_col, .row_offset = overlay_y });
        }
    }

    if (game_instance.state == .Paused) {
        const overlay_y: u16 = border_offset_y + grid_height / 2;
        const pause_text = "PAUSED";
        const pause_col: u16 = border_offset_x + (grid_width / 2) -| @as(u16, @intCast(pause_text.len / 2));
        const pause_seg = vaxis.Segment{
            .text = pause_text,
            .style = .{ .fg = .{ .rgb = [_]u8{ 255, 255, 0 } } },
        };
        _ = win.printSegment(pause_seg, .{ .col_offset = pause_col, .row_offset = overlay_y });

        const resume_text = "Press P or Space to resume";
        const resume_col: u16 = border_offset_x + (grid_width / 2) -| @as(u16, @intCast(resume_text.len / 2));
        const resume_seg = vaxis.Segment{
            .text = resume_text,
            .style = .{ .fg = .{ .rgb = [_]u8{ 200, 200, 200 } } },
        };
        _ = win.printSegment(resume_seg, .{ .col_offset = resume_col, .row_offset = overlay_y + 1 });
    }

    if (game_instance.state == .GameOver) {
        const overlay_y: u16 = border_offset_y + grid_height / 2;
        const gameover_text = "GAME OVER";
        const gameover_col: u16 = border_offset_x + (grid_width / 2) -| @as(u16, @intCast(gameover_text.len / 2));
        const gameover_seg = vaxis.Segment{
            .text = gameover_text,
            .style = .{ .fg = .{ .rgb = [_]u8{ 255, 0, 0 } } },
        };
        _ = win.printSegment(gameover_seg, .{ .col_offset = gameover_col, .row_offset = overlay_y });

        var final_score_buf: [100]u8 = undefined;
        const final_score_text = try std.fmt.bufPrint(&final_score_buf, "Final Score: {d}", .{game_instance.score});
        const final_score_col: u16 = border_offset_x + (grid_width / 2) -| @as(u16, @intCast(final_score_text.len / 2));
        const final_score_seg = vaxis.Segment{
            .text = final_score_text,
            .style = .{ .fg = .{ .rgb = [_]u8{ 255, 255, 255 } } },
        };
        _ = win.printSegment(final_score_seg, .{ .col_offset = final_score_col, .row_offset = overlay_y + 1 });

        const restart_text = "Press R to restart or Q to quit";
        const restart_col: u16 = border_offset_x + (grid_width / 2) -| @as(u16, @intCast(restart_text.len / 2));
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
