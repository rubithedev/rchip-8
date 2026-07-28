const std = @import("std");

const print = std.debug.print;

const Types = @import("types.zig");
const MonochromaticFramebuffer = Types.MonochromaticFramebuffer;

const Timer = @import("chip_timer.zig").ChipTimer;

pub const Chip8 = struct {
    /// 64x32 monochromatic display buffer.
    display_buffer: MonochromaticFramebuffer,

    /// 16 keys keyboard buffer.
    keyboard_buffer: [16]u1,

    /// Program memory. Usable from 0x200 to 0xFFF.
    memory: [4096]u8,

    /// Stack memory.
    stack: [16]u16,

    /// Registers. V[0-F]
    v: [16]u8,

    /// Memory index register.
    I: u16 = 0x0,

    /// Program Counter (PC) pseudo-register.
    pc: u16 = 0x200,

    /// Stack Pointer (SP) pseudo-register.
    sp: u8 = 0x0,

    /// Delay timer.
    delay_timer: Timer,

    /// Sound timer.
    sound_timer: Timer,

    /// Flag to control the step in case the emulator encounters the `Fx0A`
    /// The Chip8 should stop the execution until the user press a key.
    wait_for_key: bool = false,

    pub fn init() Chip8 {
        var self = Chip8{
            .display_buffer = @splat(0),
            .keyboard_buffer = @splat(0),
            .memory = @splat(0),
            .stack = @splat(0),
            .v = @splat(0),
            .delay_timer = Timer{},
            .sound_timer = Timer{},
        };

        // Load font sprites to interpreter memory. 0x000 to 0x1FF.
        for (font_sprites, 0..) |sprite, i| {
            const block_index = i * 5;
            for (0..5, block_index..) |sprite_index, memory_index| {
                self.memory[memory_index] = sprite[sprite_index];
            }
        }

        return self;
    }

    pub fn tickTimers(self: *Chip8) void {
        self.delay_timer.tick();
        self.sound_timer.tick();
    }

    pub fn step(self: *Chip8) void {
        if (self.wait_for_key)
            return;
        // TODO: The cool stuff.
    }
};

// I know, I could have just used the hexadecimal values, but now you can
// easily update the fonts as you wish!
//
// Also, it doesn't makes any difference for the zig compiler anyways.
pub const font_sprites = [16][5]u8{
    // 0
    .{
        0b11110000, //  ****
        0b10010000, //  *  *
        0b10010000, //  *  *
        0b10010000, //  *  *
        0b11110000, //  ****
    },

    // 1
    .{
        0b00100000, //   *
        0b01100000, //  **
        0b00100000, //   *
        0b00100000, //   *
        0b01110000, //  ***
    },

    // 2
    .{
        0b11110000, //  ****
        0b00010000, //     *
        0b11110000, //  ****
        0b10000000, //  *
        0b11110000, //  ****
    },

    // 3
    .{
        0b11110000, //  ****
        0b00010000, //     *
        0b11110000, //  ****
        0b00010000, //     *
        0b11110000, //  ****
    },

    // 4
    .{
        0b10010000, //  *  *
        0b10010000, //  *  *
        0b11110000, //  ****
        0b00010000, //     *
        0b00010000, //     *
    },

    // 5
    .{
        0b11110000, //  ****
        0b10000000, //  *
        0b11110000, //  ****
        0b00010000, //     *
        0b11110000, //  ****
    },

    // 6
    .{
        0b11110000, //  ****
        0b10000000, //  *
        0b11110000, //  ****
        0b10010000, //  *  *
        0b11110000, //  ****
    },

    // 7
    .{
        0b11110000, //  ****
        0b00010000, //     *
        0b00100000, //    *
        0b01000000, //   *
        0b01000000, //   *
    },

    // 8
    .{
        0b11110000, //  ****
        0b10010000, //  *  *
        0b11110000, //  ****
        0b10010000, //  *  *
        0b11110000, //  ****
    },

    // 9
    .{
        0b11110000, //  ****
        0b10010000, //  *  *
        0b11110000, //  ****
        0b00010000, //     *
        0b11110000, //  ****
    },

    // A
    .{
        0b11110000, //  ****
        0b10010000, //  *  *
        0b11110000, //  ****
        0b10010000, //  *  *
        0b10010000, //  *  *
    },

    // B
    .{
        0b11100000, //  ***
        0b10010000, //  *  *
        0b11100000, //  ***
        0b10010000, //  *  *
        0b11100000, //  ***
    },

    // C
    .{
        0b11110000, //  ****
        0b10000000, //  *
        0b10000000, //  *
        0b10000000, //  *
        0b11110000, //  ****
    },

    // D
    .{
        0b11100000, //  ***
        0b10010000, //  *  *
        0b10010000, //  *  *
        0b10010000, //  *  *
        0b11100000, //  ***
    },

    // E
    .{
        0b11110000, //  ****
        0b10000000, //  *
        0b11110000, //  ****
        0b10000000, //  *
        0b11110000, //  ****
    },

    // F
    .{
        0b11110000, //  ****
        0b10000000, //  *
        0b11110000, //  ****
        0b10000000, //  *
        0b10000000, //  *
    },
};
