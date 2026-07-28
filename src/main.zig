const std = @import("std");
const Io = std.Io;

const print = std.debug.print;

const rchip_8 = @import("rchip_8");

pub fn main(init: std.process.Init) !void {
    var render = rchip_8.RenderMod.Render.init(.{});

    var cpu = rchip_8.Chip8Mod.Chip8.init();

    var cpu_clock = rchip_8.ClockMod.ChipClock.fromHz(500);
    var timers_clock = rchip_8.ClockMod.ChipClock.fromHz(60);

    var previous = std.Io.Clock.awake.now(init.io).toNanoseconds();

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
