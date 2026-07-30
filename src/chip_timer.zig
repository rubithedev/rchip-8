pub const ChipTimer = struct {
    value: u8 = 0,

    pub fn set(self: *ChipTimer, value: u8) void {
        self.value = value;
    }

    pub fn tick(self: *ChipTimer) void {
        if (self.value > 0)
            self.value -= 1;
    }
};
