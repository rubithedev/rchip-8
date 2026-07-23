const std = @import("std");
const Io = std.Io;

// Manage the std writer so I don't need to do it all the time.
pub const Logger = struct {
    stdout_buffer: [2048]u8,
    stdout: Io.File.Writer,

    pub fn init(io: Io) !Logger {
        var self: Logger = undefined;
        self.stdout = Io.File.Writer.init(.stdout(), io, &self.stdout_buffer);

        return self;
    }

    pub fn writeln(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout.interface.print(fmt, args);
        try self.stdout.interface.flush();
    }
};
