const std = @import("std");
const Io = std.Io;

const rchip_8 = @import("rchip_8");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var logger = try rchip_8.Logger.init(io);

    try logger.writeln("Testando essa bosta {}\n", .{10});
}
