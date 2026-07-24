const std = @import("std");
const print = std.debug.print;
const rlb = @import("raylib");

const Color = rlb.Color;
const Image = rlb.Image;
const Texture = rlb.Texture2D;

const DISPLAY_WIDTH = 64;
const DISPLAY_HEIGHT = 32;
const scale = 12;

const MonochromaticFramebuffer = [DISPLAY_WIDTH * DISPLAY_HEIGHT]u1;
const RGBAFrameBuffer = [DISPLAY_WIDTH * DISPLAY_HEIGHT]Color;

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
    window_name: [:0]const u8,

    pub fn init(options: InitOptions) Render {
        var self = Render{
            .screen_width = options.screen_width,
            .screen_height = options.screen_height,
            .target_fps = options.target_fps,
            .bg_color = options.bg_color,
            .fg_color = options.fg_color,
            .window_name = options.window_name,
        };

        print("[RENDER] init(): Init Window ({}, {}, '{s}')\n", .{ self.screen_width, self.screen_height, self.window_name });
        rlb.InitWindow(self.screen_width, self.screen_height, self.window_name);
        rlb.SetTargetFPS(self.target_fps);

        const image = rlb.GenImageColor(DISPLAY_WIDTH, DISPLAY_HEIGHT, self.bg_color);
        defer rlb.UnloadImage(image);
        self.texture = rlb.LoadTextureFromImage(image);

        return self;
    }

    pub fn deinit(self: *Render) void {
        print("[RENDER] deinit(): Destroying render\n", .{});
        rlb.UnloadTexture(self.texture);
        rlb.CloseWindow();

        self.* = undefined;
    }

    pub fn shouldClose(self: *Render) bool {
        _ = self;
        return rlb.WindowShouldClose();
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
