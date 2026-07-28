const std = @import("std");
const time = std.time;
const Io = std.Io;

pub const ClockOptions = struct {
    clock_hz: u32 = 500, // 500Hz as default.
};

pub const ChipClock = struct {
    clock_hz: u32,
    period: i128,
    accumulator: i128 = 0,

    pub fn init(options: ClockOptions) ChipClock {
        var self = ChipClock{};

        self.clock_hz = options.clock_hz;
        self.period = time.ns_per_s / self.clock_hz;

        return self;
    }

    pub fn updateDelta(self: *ChipClock, delta_ns: i128) void {
        self.accumulator += delta_ns;
    }

    pub fn ready(self: *ChipClock) bool {
        if (self.accumulator >= self.period) {
            self.accumulator -= self.period;

            return true;
        }

        return false;
    }
};
