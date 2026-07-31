const std = @import("std");
const Io = std.Io;
const Random = std.Random;
const debug = std.debug;

const Types = @import("types.zig");
const MonochromaticFramebuffer = Types.MonochromaticFramebuffer;

const Timer = @import("chip_timer.zig").ChipTimer;

const NO_KEY_PRESSED = 0xFF;

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

    /// RNG.
    random: Random.DefaultPrng,

    /// Flag to control the step in case the emulator encounters the `Fx0A`
    /// The Chip8 should stop the execution until the user press a key.
    wait_for_key: bool = false,

    /// Stores the last key pressed
    key_pressed: u8 = 0xFF,

    /// Hard Locks the processor. No ticks or steps are executed.
    hard_lock: bool = false,

    pub fn init(io: Io) Chip8 {
        var self = Chip8{
            .display_buffer = @splat(0),
            .keyboard_buffer = @splat(0),
            .memory = @splat(0),
            .stack = @splat(0),
            .v = @splat(0),
            .delay_timer = Timer{},
            .sound_timer = Timer{},
            .random = Random.DefaultPrng.init(@intCast(Io.Clock.awake.now(io).toMicroseconds())),
        };

        // Load font sprites to interpreter memory. 0x000 to 0x1FF.
        for (font_sprites, 0..) |sprite, i| {
            const block_index = i * 5;
            for (0..5, block_index..) |sprite_index, memory_index| {
                self.memory[memory_index] = sprite[sprite_index];
            }
        }

        debug.print("[Chip8]: Initialized!\n", .{});
        return self;
    }

    pub fn loadToMemory(self: *Chip8, block: []const u8) void {
        for (block, 0..) |byte, i| {
            self.memory[0x200 + i] = byte;
        }
    }

    pub fn tickTimers(self: *Chip8) void {
        if (self.hard_lock)
            return;

        debug.print("[Chip8]: Ticking timers\n", .{});
        self.delay_timer.tick();
        self.sound_timer.tick();
    }

    pub fn step(self: *Chip8) void {
        // Check for timers.
        if (self.delay_timer.value > 0) return;

        // Check for locks.
        if (self.wait_for_key or self.hard_lock) return;

        const opcode = self.fetchOpcode();
        self.execute(opcode);
    }

    // Decoders.
    fn execute(self: *Chip8, opcode: u16) void {
        debug.print("[Chip8]: Executing opcode: {x}\n", .{opcode});

        switch (opcode & 0xF000) {
            0x0000 => self.decode0(opcode),
            0x1000 => self.decode1(opcode),
            0x2000 => self.decode2(opcode),
            0x3000 => self.decode3(opcode),
            0x4000 => self.decode4(opcode),
            0x5000 => self.decode5(opcode),
            0x6000 => self.decode6(opcode),
            0x7000 => self.decode7(opcode),
            0x8000 => self.decode8(opcode),
            0x9000 => self.decode9(opcode),
            0xA000 => self.decodeA(opcode),
            0xB000 => self.decodeB(opcode),
            0xC000 => self.decodeC(opcode),
            0xD000 => self.decodeD(opcode),
            0xE000 => self.decodeE(opcode),
            0xF000 => self.decodeF(opcode),

            else => {},
        }
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
        switch (opcode & 0xFF) {
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

    // Instructions.

    fn fetchOpcode(self: *Chip8) u16 {
        const pc: usize = @intCast(self.pc);

        return (@as(u16, self.memory[pc]) << 8) | @as(u16, self.memory[pc + 1]);
    }

    fn advancePc(self: *Chip8) void {
        self.pc += 2;
    }

    fn pushStack(self: *Chip8, value: u16) void {
        debug.print("[Chip8]: Pushing stack {x}\n", .{value});
        self.stack[self.sp] = value;
        self.sp += 1;
    }

    fn popStack(self: *Chip8) u16 {
        self.sp -= 1;

        debug.print("[Chip8]: Popping stack {x}\n", .{self.stack[self.sp]});

        return self.stack[self.sp];
    }

    /// Writes data to the display in rows of 8xN bits.
    fn writeDisplay(self: *Chip8, x: usize, y: usize, height: u4, block: []u8) void {
        self.v[0xF] = 0;

        for (0..height) |i| {
            const sprite_line = block[i];

            for (0..8) |j| {

                // Holy FUCK. My brain is hurting... but it works. I guess...
                const normalized_y = if (y + j >= 32) 0 else y;
                const normalized_x = if (x + i >= 64) 0 else x;

                const flat_display_index = (normalized_y + i) * 64 + normalized_x + j;
                const bit_index: u3 = @intCast(j);
                const sprite_bit: u1 = @intCast((sprite_line >> (7 - bit_index)) & 1);

                if ((self.v[0xF] == 0)) {
                    if (self.display_buffer[flat_display_index] ^ sprite_bit == 1) self.v[0xF] = 1;
                }

                self.display_buffer[flat_display_index] = sprite_bit;
            }
        }
    }

    /// Pressed key event
    pub fn pressedKey(self: *Chip8, key: u4) void {
        debug.print("[Chip8] pressedKey(): Key read {x} \n", .{key});
        self.key_pressed = key;
        self.wait_for_key = false;
    }

    // 0x0 instructions.

    /// 0x00E0 instruction.
    fn opCLS(self: *Chip8) void {
        debug.print("[Chip8] opCLS(): Clearing display\n", .{});
        self.display_buffer = @splat(0);

        self.advancePc();
    }

    /// 0x00EE instruction.
    fn opRET(self: *Chip8) void {
        self.pc = self.popStack();
        debug.print("[Chip8] opRET(): Returning value from subroutine {x}\n", .{self.pc});
    }

    /// 0x0nnn instruction: `SYS addr`
    fn opSYS(self: *Chip8, addr: u16) void {
        // Doesn't do shit. I'm implementing it just in case.
        // Feel free to remove if you want.
        debug.print("[Chip8] opSYS(): SYS operation to {x}. Doesn't do shit.\n", .{addr});

        // For debug proposes, 0x0000 opcode may hard lock the CPU.
        self.hard_lock = true;
    }

    // 0x1 instructions.

    /// 0x1nnn instruction: `JP addr`
    fn opJP(self: *Chip8, addr: u16) void {
        debug.print("[Chip8] opJP(): JUMP to {x}\n", .{addr});
        self.pc = addr;
    }

    // 0x2 instructions.

    /// 0x2nnn instruction: `CALL addr`
    fn opCALL(self: *Chip8, addr: u16) void {
        debug.print("[Chip8] opCALL(): CALL subroutine in {x}\n", .{addr});
        self.pushStack(self.pc);
        self.pc = addr;
    }

    // 0x3 instructions.

    /// 0x3xkk instruction: `SE Vx, byte`
    fn opSE(self: *Chip8, reg: u4, byte: u8) void {
        debug.print("[Chip8] opSE(): Skipping next instruction V{} (0x{X}) if equal to {x}\n", .{
            reg,
            self.v[reg],
            byte,
        });
        self.advancePc();

        if (self.v[reg] == byte) {
            self.advancePc();
        }
    }

    // 0x4 instructions.

    /// 0x4xkk instruction: `SNE Vx, byte`
    fn opSNE(self: *Chip8, reg: u4, byte: u8) void {
        debug.print("[Chip8] opSNE(): Skipping next instruction V{} (0x{X}) is not equal to {x}\n", .{
            reg,
            self.v[reg],
            byte,
        });
        self.advancePc();

        if (self.v[reg] != byte) {
            self.advancePc();
        }
    }

    // 0x5 instructions.

    /// 0x5xy0 instruction: `SE Vx, vy`
    fn opSEVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opSEVxVy(): Skipping next instruction V{} (0x{X}) is not equal to V{} (0x{X})\n", .{
            reg_x, self.v[reg_x],
            reg_y, self.v[reg_y],
        });
        self.advancePc();

        if (self.v[reg_x] == self.v[reg_y]) {
            self.advancePc();
        }
    }

    // 0x6 instructions.

    /// 0x6xkk instruction: `LD Vx, byte`
    fn opLD(self: *Chip8, reg: u4, byte: u8) void {
        debug.print("[Chip8] opLD(): Loading {x} into V{}\n", .{ byte, reg });
        self.v[reg] = byte;

        self.advancePc();
    }

    // 0x7 instructions.

    /// 0x7xkk instruction: `ADD Vx, byte`
    fn opADD(self: *Chip8, reg: u4, byte: u8) void {
        debug.print("[Chip8] opADD(): Adding {x} to V{} (0x{X})\n", .{
            byte,
            reg,
            self.v[reg],
        });
        self.v[reg] += byte;

        self.advancePc();
    }

    // 0x8 instructions.

    /// 0x8xy0 instruction: `LD Vx, Vy`
    fn opLDVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opLDVxVy(): Loading to V{} (0x{X}) to V{} (0x{X})\n", .{
            reg_x, self.v[reg_x],
            reg_y, self.v[reg_y],
        });
        self.v[reg_x] = self.v[reg_y];

        self.advancePc();
    }

    /// 0x8xy1 instruction: `OR Vx, Vy`
    fn opORVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opORVxVy(): Executing bitwise OR with values V{} (0x{X}), V{} (0x{X})\n", .{
            reg_x, self.v[reg_x],
            reg_y, self.v[reg_y],
        });
        self.v[reg_x] |= self.v[reg_y];

        self.advancePc();
    }

    /// 0x8xy2 instruction: `AND Vx, Vy`
    fn opANDVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opANDVxVy(): Executing bitwise AND with values V{} (0x{X}), V{} (0x{X})\n", .{
            reg_x, self.v[reg_x],
            reg_y, self.v[reg_y],
        });
        self.v[reg_x] &= self.v[reg_y];

        self.advancePc();
    }

    /// 0x8xy3 instruction: `XOR Vx, Vy`
    fn opXORVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opXORVxVy(): Executing bitwise XOR with values V{} (0x{X}), V{} (0x{X})\n", .{
            reg_x, self.v[reg_x],
            reg_y, self.v[reg_y],
        });
        self.v[reg_x] ^= self.v[reg_y];

        self.advancePc();
    }

    ///  0x8xy4 instruction: `ADD Vx, Vy`
    fn opADDVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opADDVxVy(): ADD values V{} (0x{X}), V{} (0x{X}). VF receives the carry and Vx holds the last 8 significant bits.\n", .{
            reg_x, self.v[reg_x],
            reg_y, self.v[reg_y],
        });

        const sum = @as(u16, self.v[reg_x]) + @as(u16, self.v[reg_y]);

        self.v[0xF] = if (sum > 0xFF) 1 else 0;
        self.v[reg_x] = @truncate(sum);

        self.advancePc();
    }

    /// 0x8xy5 instruction: `SUB Vx, Vy`
    fn opSUBVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opSUBVxVy(): SUB values V{} (0x{X}), V{} (0x{X}). VF is set to 1 if Vx >= Vy (borrow)\n", .{
            reg_x, self.v[reg_x],
            reg_y, self.v[reg_y],
        });
        self.v[0xF] = if (self.v[reg_x] >= self.v[reg_y]) 1 else 0;

        self.v[reg_x] -%= self.v[reg_y];

        self.advancePc();
    }

    /// 0x8xy6 instruction: `SHR Vx {, Vy}`
    fn opSHRVx_Vy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opSHRVx_Vy(): V{x} (0x{X}) >> 1\n", .{
            reg_x, self.v[reg_x],
        });

        _ = reg_y; // Used just in case we need to be absolutely compliant to the COSMAC VIP.

        self.v[0xF] = self.v[reg_x] & 1;
        self.v[reg_x] >>= 1;

        self.advancePc();
    }

    //  0x8xy7 instruction: `SUBN Vx, Vy`
    fn opSUBNVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opSUBNVxVy(): SUB values V{} (0x{X}), V{} (0x{X}). VF is set to 1 if Vx <= Vy (NOT borrow)\n", .{
            reg_y, self.v[reg_y],
            reg_x, self.v[reg_x],
        });
        self.v[0xF] = if (self.v[reg_y] >= self.v[reg_x]) 1 else 0;

        self.v[reg_x] = self.v[reg_y] -% self.v[reg_x];

        self.advancePc();
    }

    /// 0x8xyE instruction: `SHL Vx {, Vy}`
    fn opSHLVx_Vy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opSHLVx_Vy(): V{x} (0x{X}) << 1\n", .{
            reg_x, self.v[reg_x],
        });

        _ = reg_y; // Used just in case we need to be absolutely compliant to the COSMAC VIP.

        self.v[0xF] = (self.v[reg_x] >> 7) & 1;
        self.v[reg_x] <<= 1;

        self.advancePc();
    }

    // 0x9 instructions.

    /// 0x9xy0 instruction: `SNE Vx, Vy`
    fn opSNEVxVy(self: *Chip8, reg_x: u4, reg_y: u4) void {
        debug.print("[Chip8] opSNEVxVy(): Skipping next instruction V{} (0x{X}) if not equal to V{} (0x{X})\n", .{
            reg_x, self.v[reg_x],
            reg_y, self.v[reg_y],
        });
        self.advancePc();

        if (self.v[reg_x] != self.v[reg_y]) {
            self.advancePc();
        }
    }

    // 0xA instructions.

    /// 0xAnnn instruction: `LD I, addr`
    fn opLDI(self: *Chip8, addr: u16) void {
        debug.print("[Chip8] opLDI(): Loads address {x} to I\n", .{addr});
        self.I = addr;

        self.advancePc();
    }

    // 0xB instructions.

    /// 0xBnnn instruction: `JP V0, addr`
    fn opJPV0(self: *Chip8, addr: u16) void {
        debug.print("[Chip8] opJPV0(): Jumps to V0 (0x{X}) + {x}\n", .{ self.v[0], addr });
        self.pc = self.v[0] + addr;
    }

    // 0xC instructions.

    /// 0xCxkk instruction: `RND Vx, byte`
    fn opRNDVx(self: *Chip8, reg: u4, byte: u8) void {
        debug.print("[Chip8] opRNDVx(): Generated random number and operates an AND with {x} and stores it in V{}\n", .{
            byte, self.v[reg],
        });
        const rand_num = self.random.random().int(u8);
        self.v[reg] = rand_num & byte;

        self.advancePc();
    }

    // 0xD instructions.

    /// 0xDxyn instruction: `DRW Vx, Vy, nibble`
    fn opDRWVxVy(self: *Chip8, reg_x: u4, reg_y: u4, nibble: u4) void {
        debug.print("[Chip8] opDRWVxVy(): Drawing at coordinates [V{} (0x{X}), V{} (0x{X})] {} rows of 8 bits, starting at I (0x{X})\n", .{
            reg_x,  self.v[reg_x],
            reg_y,  self.v[reg_y],
            nibble, self.I,
        });
        const sprite = self.memory[self.I..(self.I + nibble)];
        self.writeDisplay(self.v[reg_x], self.v[reg_y], nibble, sprite);

        self.advancePc();
    }

    // 0xE instructions.

    /// 0xEx9E instruction: SKP Vx
    fn opSKPVx(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] opSKPVx(): Skips next instruction if key with V{x} (0x{X}) value is pressed\n", .{
            reg, self.v[reg],
        });

        self.advancePc();

        if (self.keyboard_buffer[self.v[reg]] == 1) {
            self.advancePc();
        }
    }

    /// 0xExA1 instruction: `SKNP Vx`
    fn opSKNPVx(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] opSKNPVx(): Skips next instruction if key with V{x} (0x{X}) value is not pressed\n", .{
            reg, self.v[reg],
        });

        self.advancePc();

        if (self.keyboard_buffer[self.v[reg]] == 0) {
            self.advancePc();
        }
    }

    // 0xF instructions.

    /// 0xFx07 instruction: `LD Vx, DT`
    fn opLDVxDT(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] opLDVxDT(): Loading DT (0x{X}) to V{x} (0x{X})\n", .{
            self.delay_timer.value,
            reg,
            self.v[reg],
        });
        self.v[reg] = self.delay_timer.value;

        self.advancePc();
    }

    /// 0xFx0A instruction: `LD Vx, K`
    fn opLDVxK(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] 0xFx0A(): Locking CPU until key pressed and stores it at V{x}\n", .{
            reg,
        });

        if (!self.wait_for_key and self.key_pressed == NO_KEY_PRESSED) {
            self.wait_for_key = true;
            return;
        } else {
            self.wait_for_key = false;
            self.v[reg] = self.key_pressed;
            self.key_pressed = NO_KEY_PRESSED;

            self.advancePc();
        }
    }

    /// 0xFx15 instruction: `LD DT, Vx`
    fn opLDDTVx(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] opLDDTVx(): Loading V{x} (0x{X}) to DT\n", .{
            reg,
            self.v[reg],
        });
        self.delay_timer.set(self.v[reg]);

        self.advancePc();
    }

    /// 0xFx18 instruction: `LD ST, Vx`
    fn opLDSTVx(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] opLDSTVx(): Loading V{x} (0x{X}) to ST\n", .{
            reg,
            self.v[reg],
        });
        self.sound_timer.set(self.v[reg]);

        self.advancePc();
    }

    /// 0xFx1E instruction: `ADD I, Vx`
    fn opADDIVx(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] opADDIVx(): ADD I (0x{X}), V{x}\n", .{
            self.I, reg,
        });
        self.I += self.v[reg];

        self.advancePc();
    }

    /// 0xFx29 instruction: `LD F, Vx`
    fn opLDFVx(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] opLDFVx(): Sets I (0x{X}) to the digit sprite stored at V{x} (0x{X})\n", .{
            self.I, reg, self.v[reg],
        });
        self.I = self.v[reg] * 5;
        self.advancePc();
    }

    /// 0xFx33 instruction: `LD B, Vx`
    fn opLDBVx(self: *Chip8, reg: u4) void {
        const value = self.v[reg];

        const hundreds = value / 100;
        const tens = (value / 10) % 10;
        const ones = value % 10;

        debug.print("[Chip8] opLDBVx(): Read V{x} as decimal ({}) (HTO) and writes I = H ({}), I+1 = T ({}), I+2 = O ({})\n", .{
            reg,      self.v[reg],
            hundreds, tens,
            ones,
        });

        self.memory[self.I] = hundreds;
        self.memory[self.I + 1] = tens;
        self.memory[self.I + 2] = ones;

        self.advancePc();
    }

    /// 0xFx55 instruction: `LD [I], Vx`
    fn opLDIVx(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] opLDIVx(): Writing V0 to V{x} into memory starting from I (0x{X})\n", .{
            reg, self.I,
        });
        const len: usize = @intCast(reg + 1);
        @memcpy(self.memory[self.I..(self.I + len)], self.v[0..len]);

        self.advancePc();
    }

    /// 0xFx65 instruction: `LD Vx, [I]`
    fn opLDVxI(self: *Chip8, reg: u4) void {
        debug.print("[Chip8] opLDVxI(): Loading values in I (0x{X}) from V0 to V{x}\n", .{
            self.I, reg,
        });
        const len: usize = @intCast(reg + 1);
        @memcpy(self.v[0..len], self.memory[self.I..(self.I + len)]);

        self.advancePc();
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
