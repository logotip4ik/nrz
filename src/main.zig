const std = @import("std");
const mem = @import("./mem.zig");
const helpers = @import("./helpers.zig");
const Colorist = @import("colorist.zig");

const Nrz = @import("./nrz.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var threads: std.Io.Threaded = .init_single_threaded;
    // `replaceProcess` will fail without this. `init_single_threaded` uses failing allocator and
    // `replaceProcess` needs allocator for ... something.
    threads.allocator = alloc;

    defer threads.deinit();

    const io = threads.io();

    const args = try init.args.toSlice(alloc);
    const colorist: Colorist = .init(io, init.environ);

    if (args.len < 2) {
        return Nrz.list(alloc, io, colorist);
    }

    var commandStart: u8 = 1;
    const firstArgument = args[1];

    if (std.mem.eql(u8, firstArgument, "-h") or std.mem.eql(u8, firstArgument, "--help")) {
        return try Nrz.help(io);
    } else if (std.mem.startsWith(u8, firstArgument, "--cmp=")) {
        const shell = std.meta.stringToEnum(Nrz.Shell, firstArgument["--cmp=".len..]) orelse {
            return error.UnknownShell;
        };

        return Nrz.genCompletions(io, shell);
    } else if (std.mem.eql(u8, firstArgument, "--list-cmp")) {
        return Nrz.listCompletions(alloc, io);
    } else if (std.mem.eql(u8, firstArgument, "--version")) {
        return Nrz.version(io);
    } else if (std.mem.eql(u8, firstArgument, "run")) {
        if (args.len < 3) {
            return error.InvalidInput;
        }

        commandStart = 2;
    }

    const options = try helpers.concatStringArray(alloc, args[commandStart + 1 ..], ' ');
    defer alloc.free(options);

    var envs = try init.environ.createMap(alloc);

    try Nrz.run(
        alloc,
        io,
        colorist,
        &envs,
        args[commandStart],
        options
    );
}
