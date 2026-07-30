const std = @import("std");
const time = std.time;
const Io = std.Io;

const print = std.debug.print;

pub const ClockOptions = struct {
    clock_hz: u32 = 500, // 500Hz as default.
};

pub const ChipClock = struct {
    period: i128 = 0,
    accumulator: i128 = 0,

    pub fn fromHz(clock_hz: u32) ChipClock {
        return ChipClock{
            .period = time.ns_per_s / clock_hz,
        };
    }

    pub fn update(self: *ChipClock, delta_ns: i128) void {
        self.accumulator += delta_ns;
    }

    pub fn consume(self: *ChipClock) u32 {
        const ticks = @divTrunc(self.accumulator, self.period);
        self.accumulator = @mod(self.accumulator, self.period);

        return @intCast(ticks);
    }
};
