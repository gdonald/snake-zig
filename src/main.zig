const std = @import("std");
const vaxis = @import("vaxis");

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

    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                    break;
                }
            },
            .winsize => |ws| {
                try vx.resize(allocator, tty.writer(), ws);
            },
        }

        const win = vx.window();
        win.clear();

        const msg = "Hello, Snake! Press 'q' to quit.";
        const col: u16 = @intCast((win.width / 2) -| (msg.len / 2));
        const row: u16 = @intCast(win.height / 2);

        const seg = vaxis.Segment{
            .text = msg,
            .style = .{
                .fg = .{ .rgb = [_]u8{ 0, 255, 0 } },
            },
        };
        _ = win.printSegment(seg, .{ .col_offset = col, .row_offset = row });

        try vx.render(tty.writer());
    }
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};
