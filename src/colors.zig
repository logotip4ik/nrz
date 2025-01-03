const std = @import("std");

pub const Colorist = struct {
    const Self = @This();

    pub const Color = enum {
        WhiteBold,
        Dimmed,
        Reset,
    };

    noColor: bool,

    pub fn new() Self {
        var buffer: [512]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const alloc = fba.allocator();

        const noColorEnv = std.process.getEnvVarOwned(alloc, "NO_COLOR") catch "";

        return Self{
            .noColor = !std.mem.eql(u8, noColorEnv, ""),
        };
    }

    pub inline fn getColor(self: Self, comptime color: Color) []const u8 {
        if (self.noColor) {
            return "";
        }

        return switch (color) {
            .WhiteBold => "\u{001B}[1;37m",
            .Dimmed => "\u{001B}[2m",
            .Reset => "\u{001B}[0m",
        };
    }
};
