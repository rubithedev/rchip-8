const std = @import("std");
const Io = std.Io;
const eql = std.mem.eql;

const header =
    \\RCHIP-8: The Rubi's CHIP-8 emulator.
;

const usage =
    \\Usage: {s} --rom [PATH] --bg-color [COLOR] --fg-color [COLOR]
    \\Usage example:
    \\  {s} --rom 'roms/INVADERS'
    \\
    \\Color input format:
    \\  [COLOR]:          "#RRGGBB" - Hexadecimal colors with no alpha.
    \\                    For example, to load an aqua cyan blue: "#00FFFF"
    \\
    \\Arguments:
    \\
    \\  --rom [PATH]:           Loads a ROM to run with from a relative path.
    \\  --fg-color [COLOR]:     Renders the foreground with a specific color.
    \\                          Default if "#FFFFFF".
    \\  --gb-color [COLOR]:     Renders the background with a specific color.
    \\                          Default if "#000000".
    \\  --help:                 Prints this page.
;

const CLIErrors = error{
    ROMPathNotFound,
};

const ArgsValues = struct {
    rom_path: ?[:0]const u8 = null,
    fg_color: ?[:0]const u8 = null,
    bg_color: ?[:0]const u8 = null,
};

pub const CLI = struct {
    stdout_buffer: [2048]u8,
    stdout: Io.File.Writer,

    exe_path: [:0]const u8,
    args: ArgsValues = ArgsValues{},

    pub fn init(io: Io, args: []const [:0]const u8) !CLI {
        var self = CLI{
            .stdout_buffer = @splat(0),
            .stdout = undefined,
            .exe_path = args[0],
        };
        self.stdout = Io.File.Writer.init(.stdout(), io, &self.stdout_buffer);

        // Not elegant, but works.
        // It's not like we need actual infrastructure to parse 3 args. LOL
        var next_arg_rom_path = false;
        var next_arg_fg_color = false;
        var next_arg_bg_color = false;

        for (args[1..]) |arg| {

            // Check argument flag.
            if (next_arg_rom_path) {
                self.args.rom_path = arg;
                next_arg_rom_path = false;
                continue;
            }

            if (next_arg_fg_color) {
                self.args.fg_color = arg;
                next_arg_fg_color = false;
                continue;
            }

            if (next_arg_bg_color) {
                self.args.bg_color = arg;
                next_arg_bg_color = false;
                continue;
            }

            // Set argument flag.
            if (eql(u8, arg, "--rom")) {
                next_arg_rom_path = true;
                continue;
            }

            if (eql(u8, arg, "--fg-color")) {
                next_arg_fg_color = true;
                continue;
            }

            if (eql(u8, arg, "--bg-color")) {
                next_arg_bg_color = true;
                continue;
            }

            if (eql(u8, arg, "--help")) {
                try self.printHelp();
                std.process.exit(0);
            }
        }

        if (self.args.rom_path == null) {
            try self.writeLn("No ROM path!\n", .{});
            try self.printUsage();
            return CLIErrors.ROMPathNotFound;
        }

        return self;
    }

    pub fn wite(self: *CLI, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout.interface.print(fmt, args);
        try self.stdout.interface.flush();
    }

    pub fn writeLn(self: *CLI, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout.interface.print(fmt ++ "\n", args);
        try self.stdout.interface.flush();
    }

    pub fn printHelp(self: *CLI) !void {
        try self.writeLn("{s}\n\n{s}\n", .{ header, usage });
    }

    pub fn printUsage(self: *CLI) !void {
        try self.writeLn(usage, .{ self.exe_path, self.exe_path });
    }
};
