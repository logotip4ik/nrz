const std = @import("std");

const Self = @This();

pub const Color = enum {
    WhiteBold,
    Dimmed,
    Reset,
};

mode: std.Io.Terminal.Mode,

pub fn init(io: std.Io, environ: std.process.Environ) Self {
    return Self{
        .mode = std.Io.Terminal.Mode.detect(
            io,
            std.Io.File.stdout(),
            environ.containsUnemptyConstant("NO_COLOR"),
            environ.containsUnemptyConstant("CLICOLOR_FORCE"),
        ) catch .no_color,
    };
}

pub inline fn getColor(self: Self, comptime color: Color) []const u8 {
    if (self.mode == .no_color) {
        return "";
    }

    return switch (color) {
        .WhiteBold => "\x1b[1;97m",
        .Dimmed => "\x1b[2m",
        .Reset => "\x1b[0m",
    };
}
