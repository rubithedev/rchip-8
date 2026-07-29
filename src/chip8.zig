const std = @import("std");

const print = std.debug.print;

const Types = @import("types.zig");
const MonochromaticFramebuffer = Types.MonochromaticFramebuffer;

const Timer = @import("chip_timer.zig").ChipTimer;

// Bit extraction helpers.

/// Extracts the NNN bits as in:
///
/// 0xAnnn: `LD I, addr`
///
/// 16 bits are reserved so we don't have to cast it from u12 to u16 all the
/// time, since this we will always use it in addressing.
fn extractNNN(opcode: u16) u16 {
    return opcode & 0x0FFF;
}

/// Extracts the X bits as in:
///
/// 0x6xkk: `LD Vx, byte`
fn extractX(opcode: u16) u4 {
    return @intCast((opcode >> 8) & 0xF);
}

/// Extracts the Y bits as in:
///
/// 0x8xy0: `LD Vx, Vy`
fn extractY(opcode: u16) u4 {
    return @intCast((opcode >> 4) & 0xF);
}

/// Extracts the KK bits as in:
///
/// 0x7xkk: `ADD Vx, byte`
fn extractKK(opcode: u16) u8 {
    return @intCast(opcode & 0x00FF);
}

/// Extracts the N bits as in:
///
/// 0xDxyn: `DRW Vx, Vy, nibble`
fn extractN(opcode: u16) u4 {
    return @intCast(opcode & 0xF);
}

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

        const opcode = self.fetchOpcode();
        self.execute(opcode);
    }

    // Decoders.
    fn execute(self: *Chip8, opcode: u16) void {
        switch (opcode & 0xF000) {
            0x0 => self.decode0(opcode),
            0x1 => self.decode1(opcode),
            0x2 => self.decode2(opcode),
            0x3 => self.decode3(opcode),
            0x4 => self.decode4(opcode),
            0x5 => self.decode5(opcode),
            0x6 => self.decode6(opcode),
            0x7 => self.decode7(opcode),
            0x8 => self.decode8(opcode),
            0x9 => self.decode9(opcode),
            0xA => self.decodeA(opcode),
            0xB => self.decodeB(opcode),
            0xC => self.decodeC(opcode),
            0xD => self.decodeD(opcode),
            0xE => self.decodeE(opcode),
            0xF => self.decodeF(opcode),

            else => {},
        }
    }

    // Instructions.

    fn fetchOpcode(self: *Chip8) u16 {
        const pc: usize = @intCast(self.pc);

        return (@as(u16, self.memory[pc]) << 8) | @as(u16, self.memory[pc + 1]);
    }

    fn advancePc(self: *Chip8) void {
        self.pc += 2;
    }

    fn decode0(self: *Chip8, opcode: u16) void {
        switch (opcode & 0x00FF) {
            0xE0 => self.opCLS(),
            0xEE => self.opRET(),
            else => {
                const addr = extractNNN(opcode);
                self.opSYS(addr);
            },
        }
    }

    fn decode1(self: *Chip8, opcode: u16) void {
        const addr = extractNNN(opcode);

        self.opJP(addr);
    }

    fn decode2(self: *Chip8, opcode: u16) void {
        const addr = extractNNN(opcode);

        self.opCALL(addr);
    }

    fn decode3(self: *Chip8, opcode: u16) void {
        const reg: u4 = extractX(opcode);
        const byte: u8 = extractKK(opcode);

        self.opSE(reg, byte);
    }

    fn decode4(self: *Chip8, opcode: u16) void {
        const reg: u4 = extractX(opcode);
        const byte: u8 = extractKK(opcode);

        self.opSNE(reg, byte);
    }

    fn decode5(self: *Chip8, opcode: u16) void {
        const reg_x = extractX(opcode);
        const reg_y = extractY(opcode);

        self.opSEVxVy(reg_x, reg_y);
    }

    fn decode6(self: *Chip8, opcode: u16) void {
        const reg = extractX(opcode);
        const byte: u8 = extractKK(opcode);

        self.opLD(reg, byte);
    }

    fn decode7(self: *Chip8, opcode: u16) void {
        const reg = extractX(opcode);
        const byte: u8 = extractKK(opcode);

        self.opADD(reg, byte);
    }

    fn decode8(self: *Chip8, opcode: u16) void {
        switch (opcode & 0xF) {
            0x0 => {
                const reg_x = extractX(opcode);
                const reg_y = extractY(opcode);

                self.opLDVxVy(reg_x, reg_y);
            },
            0x1 => {
                const reg_x = extractX(opcode);
                const reg_y = extractY(opcode);

                self.opORVxVy(reg_x, reg_y);
            },
            0x2 => {
                const reg_x = extractX(opcode);
                const reg_y = extractY(opcode);

                self.opANDVxVy(reg_x, reg_y);
            },
            0x3 => {
                const reg_x = extractX(opcode);
                const reg_y = extractY(opcode);

                self.opXORVxVy(reg_x, reg_y);
            },
            0x4 => {
                const reg_x = extractX(opcode);
                const reg_y = extractY(opcode);

                self.opADDVxVy(reg_x, reg_y);
            },
            0x5 => {
                const reg_x = extractX(opcode);
                const reg_y = extractY(opcode);

                self.opSUBVxVy(reg_x, reg_y);
            },
            0x6 => {
                const reg_x = extractX(opcode);
                const reg_y = extractY(opcode);

                self.opSHRVx_Vy(reg_x, reg_y);
            },
            0x7 => {
                const reg_x = extractX(opcode);
                const reg_y = extractY(opcode);

                self.opSUBNVxVy(reg_x, reg_y);
            },
            0xE => {
                const reg_x = extractX(opcode);
                const reg_y = extractY(opcode);

                self.opSHLVx_Vy(reg_x, reg_y);
            },

            else => {},
        }
    }

    fn decode9(self: *Chip8, opcode: u16) void {
        const reg_x = extractX(opcode);
        const reg_y = extractY(opcode);

        self.opSNEVxVy(reg_x, reg_y);
    }

    fn decodeA(self: *Chip8, opcode: u16) void {
        const addr = extractNNN(opcode);

        self.opLDI(addr);
    }

    fn decodeB(self: *Chip8, opcode: u16) void {
        const addr = extractNNN(opcode);

        self.opJP(addr);
    }

    fn decodeC(self: *Chip8, opcode: u16) void {
        const reg = extractX(opcode);
        const byte = extractKK(opcode);

        self.opRNDVx(reg, byte);
    }

    fn decodeD(self: *Chip8, opcode: u16) void {
        const reg_x = extractX(opcode);
        const reg_y = extractY(opcode);
        const nibble = extractN(opcode);

        self.opDRWVxVy(reg_x, reg_y, nibble);
    }

    fn decodeE(self: *Chip8, opcode: u16) void {
        switch (opcode & 0xFF) {
            0x9E => {
                const reg = extractX(opcode);

                self.opSKPVx(reg);
            },
            0xA1 => {
                const reg = extractX(opcode);

                self.opSKNPVx(reg);
            },

            else => {},
        }
    }

    fn decodeF(self: *Chip8, opcode: u16) void {
        switch (opcode * 0xFF) {
            0x07 => {
                const reg = extractX(opcode);

                self.opLDVxDT(reg);
            },
            0x0A => {
                const reg = extractX(opcode);

                self.opLDVxK(reg);
            },
            0x15 => {
                const reg = extractX(opcode);

                self.opLDDTVx(reg);
            },
            0x18 => {
                const reg = extractX(opcode);

                self.opLDSTVx(reg);
            },
            0x1E => {
                const reg = extractX(opcode);

                self.opADDIVx(reg);
            },
            0x29 => {
                const reg = extractX(opcode);

                self.opLDFVx(reg);
            },
            0x33 => {
                const reg = extractX(opcode);

                self.opLDBVx(reg);
            },
            0x55 => {
                const reg = extractX(opcode);

                self.opLDIVx(reg);
            },
            0x65 => {
                const reg = extractX(opcode);

                self.opLDVxI(reg);
            },

            else => {},
        }
    }

    // 0x0 instructions.

    /// 0x00E0 instruction.
    fn opCLS(self: *Chip8) void {
        self.display_buffer = @splat(0);
    }

    /// 0x00EE instruction.
    fn opRET(self: *Chip8) void {
        _ = self;
        // TODO: Implement.
    }

    /// 0x0nnn instruction: `SYS addr`
    fn opSYS(self: *Chip8, addr: u16) void {
        // Doesn't do shit. I'm implementing it just in case.
        // Feel free to remove if you want.
        _ = self;
        _ = addr;
    }

    // 0x1 instructions.

    /// 0x1nnn instruction: `JP addr`
    fn opJP(self: *Chip8, addr: u16) void {
        _ = self;
        _ = addr;
        // TODO: Implement.
    }

    // 0x2 instructions.

    /// 0x2nnn instruction: `CALL addr`
    fn opCALL(self: *Chip8, addr: u16) void {
        _ = self;
        _ = addr;
        // TODO: Implement.
    }

    // 0x3 instructions.

    /// 0x3xkk instruction: `SE Vx, byte`
    fn opSE(self: *Chip8, reg: u4, byte: u8) void {
        _ = self;
        _ = reg;
        _ = byte;
        // TODO: Implement.
    }

    // 0x4 instructions.

    /// 0x4xkk instruction: `SNE Vx, byte`
    fn opSNE(self: *Chip8, reg: u4, byte: u8) void {
        _ = self;
        _ = reg;
        _ = byte;
        // TODO: Implement.
    }

    // 0x5 instructions.

    /// 0x5xy0 instruction: `SE Vx, vy`
    fn opSEVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    // 0x6 instructions.

    /// 0x6xkk instruction: `LD Vx, byte`
    fn opLD(self: *Chip8, reg: u4, byte: u8) void {
        _ = self;
        _ = reg;
        _ = byte;
        // TODO: Implement.
    }

    // 0x7 instructions.

    /// 0x7xkk instruction: `ADD Vx, byte`
    fn opADD(self: *Chip8, reg: u4, byte: u8) void {
        _ = self;
        _ = reg;
        _ = byte;
        // TODO: Implement.
    }

    // 0x8 instructions.

    /// 0x8xy0 instruction: `LD Vx, Vy`
    fn opLDVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    /// 0x8xy1 instruction: `OR Vx, Vy`
    fn opORVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    /// 0x8xy2 instruction: `AND Vx, Vy`
    fn opANDVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    /// 0x8xy3 instuction: `XOR Vx, Vy`
    fn opXORVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    ///  0x8xy4 instruction: `ADD Vx, Vy`
    fn opADDVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    /// 0x8xy5 instruction: `SUB Vx, Vy`
    fn opSUBVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    /// 0x8xy6 instruction: `SHR Vx {, Vy}`
    fn opSHRVx_Vy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    //  0x8xy7 instruction: `SUBN Vx, Vy`
    fn opSUBNVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    /// 0x8xyE instruction: `SHL Vx {, Vy}`
    fn opSHLVx_Vy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    // 0x9 instructions.

    /// 0x9xy0 instruction: `SNE Vx, Vy`
    fn opSNEVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        // TODO: Implement.
    }

    // 0xA instructions.

    /// 0xAnnn instruction: `LD I, addr`
    fn opLDI(self: *Chip8, addr: u16) void {
        _ = self;
        _ = addr;
        // TODO: Implement.
    }

    // 0xB instructions.

    /// 0xBnnn instruction: `JP V0, addr`
    fn opJPV0(self: *Chip8, addr: u16) void {
        _ = self;
        _ = addr;
        // TODO: Implement.
    }

    // 0xC instructions.

    /// 0xCxkk instruction: `RND Vx, byte`
    fn opRNDVx(self: *Chip8, reg: u4, byte: u8) void {
        _ = self;
        _ = reg;
        _ = byte;
        // TODO: Implement.
    }

    // 0xD instructions.

    /// 0xDxyn instruction: `DRW Vx, Vy, nibble`
    fn opDRWVxVy(self: *Chip8, reg_x: u4, reg_y: u4, nibble: u4) void {
        _ = self;
        _ = reg_x;
        _ = reg_y;
        _ = nibble;
        // TODO: Implement.
    }

    // 0xE instructions.

    /// 0xEx9E instruction: SKP Vx
    fn opSKPVx(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    /// 0xExA1 instruction: `SKNP Vx`
    fn opSKNPVx(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    // 0xF instructions.

    /// 0xFx07 instruction: `LD Vx, DT`
    fn opLDVxDT(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    /// 0xFx0A instruction: `LD Vx, K`
    fn opLDVxK(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    /// 0xFx15 instruction: `LD DT, Vx`
    fn opLDDTVx(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    /// 0xFx18 instruction: `LD ST, Vx`
    fn opLDSTVx(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    /// 0xFx1E instruction: `ADD I, Vx`
    fn opADDIVx(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    /// 0xFx29 instruction: `LD F, Vx`
    fn opLDFVx(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    /// 0xFx33 instruction: `LD B, Vx`
    fn opLDBVx(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    /// 0xFx55 instruction: `LD [I], Vx`
    fn opLDIVx(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
    }

    /// 0xFx65 instruction: `LD Vx, [I]`
    fn opLDVxI(self: *Chip8, reg: u4) void {
        _ = self;
        _ = reg;
        // TODO: Implement.
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
