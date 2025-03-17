const std = @import("std");
const mem = @import("./mem.zig");
const helpers = @import("./helpers.zig");

const Nrz = @import("./nrz.zig");

pub fn main() !void {
    const allocator = comptime mem.getAllocator();
    const alloc = allocator.allocator();
    defer allocator.deinit();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        return Nrz.list(alloc);
    }

    var commandStart: u8 = 1;
    const firstArgument = args[1];

    if (std.mem.eql(u8, firstArgument, "-h") or std.mem.eql(u8, firstArgument, "--help")) {
        return Nrz.help();
    } else if (std.mem.startsWith(u8, firstArgument, "--cmp=")) {
        const shell = std.meta.stringToEnum(Nrz.Shell, firstArgument["--cmp=".len..]) orelse {
            return error.UnknownShell;
        };

        return Nrz.genCompletions(shell);
    } else if (std.mem.eql(u8, firstArgument, "--list-cmp")) {
        return Nrz.listCompletions(alloc);
    } else if (std.mem.eql(u8, firstArgument, "--version")) {
        return Nrz.version();
    } else if (std.mem.eql(u8, firstArgument, "run")) {
        if (args.len < 3) {
            return error.InvalidInput;
        }

        commandStart = 2;
    }

    const options = try helpers.concatStringArray(alloc, args[commandStart + 1 ..], ' ');
    defer if (options) |opt| alloc.free(opt);

    try Nrz.run(alloc, args[commandStart], options orelse "");
}
