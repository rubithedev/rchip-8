const std = @import("std");
const Io = std.Io;

const rchip_8 = @import("rchip_8");

// This one is for testing only. Will remove.
pub fn generateTestPattern() [64 * 32]u1 {
    var fb: [64 * 32]u1 = @splat(0);

    for (0..64) |x| {
        fb[x] = 1;
        fb[31 * 64 + x] = 1;
    }

    for (0..32) |y| {
        fb[y * 64] = 1;
        fb[y * 64 + 63] = 1;
    }

    for (8..16) |y| {
        for (12..20) |x| {
            fb[y * 64 + x] = 1;
        }
    }

    for (8..16) |y| {
        for (44..52) |x| {
            fb[y * 64 + x] = 1;
        }
    }

    for (22..26) |y| {
        for (16..48) |x| {
            fb[y * 64 + x] = 1;
        }
    }

    for (20..22) |y| {
        fb[y * 64 + 15] = 1;
        fb[y * 64 + 48] = 1;
    }

    return fb;
}

pub fn main(_: std.process.Init) !void {
    var render = rchip_8.RenderMod.Render.init(.{
        .fg_color = .{ .r = 10, .g = 173, .b = 35, .a = 255 },
    });

    const test_framebuffer: [64 * 32]u1 = generateTestPattern();

    while (!render.shouldClose()) {
        render.draw(test_framebuffer);
    }

    render.deinit();
}
