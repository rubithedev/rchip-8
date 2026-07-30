const std = @import("std");
const debug = std.debug;
const rlb = @import("raylib");

const Color = rlb.Color;
const Image = rlb.Image;
const Texture = rlb.Texture2D;

const Types = @import("types.zig");
const DISPLAY_WIDTH = Types.DISPLAY_WIDTH;
const DISPLAY_HEIGHT = Types.DISPLAY_HEIGHT;
const scale = 12;

pub const NO_REGISTER_KEYMAP = 0x1F;

const MonochromaticFramebuffer = Types.MonochromaticFramebuffer;
const RGBAFrameBuffer = Types.RGBAFrameBuffer;

pub const InitOptions = struct {
    screen_width: i32 = DISPLAY_WIDTH * scale,
    screen_height: i32 = DISPLAY_HEIGHT * scale,
    target_fps: i32 = 60,
    bg_color: Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    fg_color: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    window_name: [:0]const u8 = "RCHIP-8",
};

pub const Render = struct {
    screen_width: i32,
    screen_height: i32,
    target_fps: i32,
    bg_color: Color,
    fg_color: Color,
    texture: Texture = undefined,
    framebuffer: RGBAFrameBuffer = undefined,
    keyboard_input: [16]u1,
    window_name: [:0]const u8,

    pub fn init(options: InitOptions) Render {
        var self = Render{
            .screen_width = options.screen_width,
            .screen_height = options.screen_height,
            .target_fps = options.target_fps,
            .bg_color = options.bg_color,
            .fg_color = options.fg_color,
            .keyboard_input = @splat(0),
            .window_name = options.window_name,
        };

        debug.print("[RENDER] init(): Init Window ({}, {}, '{s}')\n", .{ self.screen_width, self.screen_height, self.window_name });
        rlb.InitWindow(self.screen_width, self.screen_height, self.window_name);
        rlb.SetTargetFPS(self.target_fps);

        const image = rlb.GenImageColor(DISPLAY_WIDTH, DISPLAY_HEIGHT, self.bg_color);
        defer rlb.UnloadImage(image);
        self.texture = rlb.LoadTextureFromImage(image);

        return self;
    }

    pub fn deinit(self: *Render) void {
        debug.print("[RENDER] deinit(): Destroying render\n", .{});
        rlb.UnloadTexture(self.texture);
        rlb.CloseWindow();

        self.* = undefined;
    }

    pub fn shouldClose(self: *Render) bool {
        _ = self;
        return rlb.WindowShouldClose();
    }

    pub fn readKeyboard(self: *Render) void {

        // Skip keyboard reading if no key is pressed.
        if (rlb.IsKeyDown(rlb.KEY_NULL)) {
            self.keyboard_input = @splat(0);
            return;
        }

        self.keyboard_input[0x0] = @intFromBool(rlb.IsKeyDown(rlb.KEY_ZERO));
        self.keyboard_input[0x1] = @intFromBool(rlb.IsKeyDown(rlb.KEY_ONE));
        self.keyboard_input[0x2] = @intFromBool(rlb.IsKeyDown(rlb.KEY_TWO));
        self.keyboard_input[0x3] = @intFromBool(rlb.IsKeyDown(rlb.KEY_THREE));
        self.keyboard_input[0x4] = @intFromBool(rlb.IsKeyDown(rlb.KEY_FOUR));
        self.keyboard_input[0x5] = @intFromBool(rlb.IsKeyDown(rlb.KEY_FIVE));
        self.keyboard_input[0x6] = @intFromBool(rlb.IsKeyDown(rlb.KEY_SIX)); //   LOL
        self.keyboard_input[0x7] = @intFromBool(rlb.IsKeyDown(rlb.KEY_SEVEN)); // LOL
        self.keyboard_input[0x8] = @intFromBool(rlb.IsKeyDown(rlb.KEY_EIGHT));
        self.keyboard_input[0x9] = @intFromBool(rlb.IsKeyDown(rlb.KEY_NINE));
        self.keyboard_input[0xA] = @intFromBool(rlb.IsKeyDown(rlb.KEY_A));
        self.keyboard_input[0xB] = @intFromBool(rlb.IsKeyDown(rlb.KEY_B));
        self.keyboard_input[0xC] = @intFromBool(rlb.IsKeyDown(rlb.KEY_C));
        self.keyboard_input[0xD] = @intFromBool(rlb.IsKeyDown(rlb.KEY_D));
        self.keyboard_input[0xE] = @intFromBool(rlb.IsKeyDown(rlb.KEY_E));
        self.keyboard_input[0xF] = @intFromBool(rlb.IsKeyDown(rlb.KEY_F));
    }

    pub fn readKeyPressed(self: *Render) u5 {
        _ = self;
        const key: u5 = switch (@as(i32, @intCast(rlb.GetKeyPressed()))) {
            rlb.KEY_ZERO => 0x0,
            rlb.KEY_ONE => 0x1,
            rlb.KEY_TWO => 0x2,
            rlb.KEY_THREE => 0x3,
            rlb.KEY_FOUR => 0x4,
            rlb.KEY_FIVE => 0x5,
            rlb.KEY_SIX => 0x6,
            rlb.KEY_SEVEN => 0x7,
            rlb.KEY_EIGHT => 0x8,
            rlb.KEY_NINE => 0x9,
            rlb.KEY_A => 0xA,
            rlb.KEY_B => 0xB,
            rlb.KEY_C => 0xC,
            rlb.KEY_D => 0xD,
            rlb.KEY_E => 0xE,
            rlb.KEY_F => 0xF,

            else => NO_REGISTER_KEYMAP,
        };

        return key;
    }

    pub fn draw(self: *Render, framebuffer: MonochromaticFramebuffer) void {
        mono2RGBA(
            framebuffer,
            &self.framebuffer,
            self.fg_color,
            self.bg_color,
        );

        rlb.BeginDrawing();
        {
            rlb.UpdateTexture(self.texture, &self.framebuffer);
            rlb.DrawTextureEx(
                self.texture,
                .{ .x = 0, .y = 0 },
                0.0,
                scale,
                rlb.WHITE,
            );
        }
        rlb.EndDrawing();
    }
};

fn mono2RGBA(
    framebuffer: MonochromaticFramebuffer,
    rgba_framebuffer: *RGBAFrameBuffer,
    fg_color: Color,
    bg_color: Color,
) void {
    for (0..DISPLAY_HEIGHT) |y| {
        for (0..DISPLAY_WIDTH) |x| {
            const i = y * DISPLAY_WIDTH + x;
            rgba_framebuffer[i] = if (framebuffer[i] == 1) fg_color else bg_color;
        }
    }
}
