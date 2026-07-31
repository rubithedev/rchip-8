const std = @import("std");
const Io = std.Io;

const debug = std.debug;

const rchip_8 = @import("rchip_8");

const Chip8 = rchip_8.Chip8Mod.Chip8;
const RenderMod = rchip_8.RenderMod;
const Render = RenderMod.Render;
const Clock = rchip_8.ClockMod.ChipClock;
const CLI = rchip_8.CLIMod.CLI;

const NO_REGISTER_KEYMAP = RenderMod.NO_REGISTER_KEYMAP;

pub fn main(init: std.process.Init) !void {
    const arena_allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena_allocator);
    const cli = try CLI.init(init.io, args);

    var render = Render.init(.{});
    defer render.deinit();

    var cpu = Chip8.init(init.io);

    try cpu.loadFileToMemory(cli.args.rom_path.?);

    initMainLoop(&render, &cpu, init.io);
}

fn initMainLoop(render: *Render, cpu: *Chip8, io: Io) void {
    var cpu_clock = Clock.fromHz(700);
    var timers_clock = Clock.fromHz(60);

    var previous = std.Io.Clock.awake.now(io).toNanoseconds();

    while (!render.shouldClose()) {
        const now = std.Io.Clock.awake.now(io).toNanoseconds();
        const delta = now - previous;
        previous = now;

        cpu_clock.update(delta);
        timers_clock.update(delta);

        const cpu_ticks = cpu_clock.consume();
        const timers_ticks = timers_clock.consume();

        for (0..timers_ticks) |_| cpu.tickTimers();
        for (0..cpu_ticks) |_| {
            render.readKeyboard();
            @memcpy(cpu.keyboard_buffer[0..], render.keyboard_input[0..]);

            if (cpu.wait_for_key) {
                const key = render.readKeyPressed();
                if (key != NO_REGISTER_KEYMAP)
                    cpu.pressedKey(@truncate(key));
            }

            cpu.step();
        }

        render.draw(cpu.display_buffer);

        if (cpu.sound_timer.value > 0) {
            render.playBuzzer();
        } else {
            render.stopBuzzer();
        }
    }
}
