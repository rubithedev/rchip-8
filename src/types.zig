const rlb = @import("raylib");

pub const DISPLAY_WIDTH = 64;
pub const DISPLAY_HEIGHT = 32;

pub const MonochromaticFramebuffer = [DISPLAY_WIDTH * DISPLAY_HEIGHT]u1;
pub const RGBAFrameBuffer = [DISPLAY_WIDTH * DISPLAY_HEIGHT]rlb.Color;
