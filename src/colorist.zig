const std = @import("std");

const Self = @This();

pub const Color = enum {
    WhiteBold,
    Dimmed,
    Reset,
};

termInfo: std.Io.tty.Config,

pub fn new() Self {
    return Self{
        .termInfo = .detect(std.fs.File.stdout()),
    };
}

pub inline fn getColor(self: Self, comptime color: Color) []const u8 {
    if (self.termInfo == .no_color) {
        return "";
    }

    return switch (color) {
        .WhiteBold => "\x1b[1;97m",
        .Dimmed => "\x1b[2m",
        .Reset => "\x1b[0m",
    };
}
