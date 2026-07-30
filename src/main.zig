const std = @import("std");
const Io = std.Io;

const print = std.debug.print;

const rchip_8 = @import("rchip_8");

const program: [30]u8 = .{
    0xA0, 0x00, // LD I, 0x00
    0x60, 0x1E, // LD V0, 0x1E
    0x61, 0x0B, // LD V1, 0x0B
    0x62, 0x05, // LD V2, 0x05
    0x63, 0x00, // LD V3, 0x00
    0x64, 0x2F, // LD V4, 0x2F

    0x43, 0x10, // SEN V3, 0x10
    0xA0, 0x00, // LD I, 0x00
    0x43, 0x10, // SEN V3, 0x10
    0x63, 0x00, // LD V3, 0x00

    0xD0, 0x15, // DWR V0, V1, 0x5
    0x73, 0x01, // ADD V3, 0x01
    0xF2, 0x1E, // ADD I, V2
    0xF4, 0x15, // LD DT, V4
    0x12, 0x0A, // JP 0x20A
};

pub fn main(init: std.process.Init) !void {
    var render = rchip_8.RenderMod.Render.init(.{});

    var cpu = rchip_8.Chip8Mod.Chip8.init(init.io);

    var cpu_clock = rchip_8.ClockMod.ChipClock.fromHz(500);
    var timers_clock = rchip_8.ClockMod.ChipClock.fromHz(60);

    var previous = std.Io.Clock.awake.now(init.io).toNanoseconds();

    cpu.loadToMemory(program[0..]);

    while (!render.shouldClose()) {
        const now = std.Io.Clock.awake.now(init.io).toNanoseconds();
        const delta = now - previous;
        previous = now;

        cpu_clock.update(delta);
        timers_clock.update(delta);

        const cpu_ticks = cpu_clock.consume();
        const timers_ticks = timers_clock.consume();

        for (0..cpu_ticks) |_| cpu.step();
        for (0..timers_ticks) |_| cpu.tickTimers();

        render.draw(cpu.display_buffer);
    }

    render.deinit();
}
