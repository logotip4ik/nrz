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
        .WhiteBold => "\u{001B}[1;37m",
        .Dimmed => "\u{001B}[2m",
        .Reset => "\u{001B}[0m",
    };
}
