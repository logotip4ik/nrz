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
    threads.allocator = alloc;

    defer threads.deinit();

    const io = threads.io();

    const args = try init.args.toSlice(alloc);
    const colorist: Colorist = .init(io, init.environ);

    if (args.len < 2) {
        return Nrz.list(alloc, io, colorist);
    }

    var cwdChange: ?[]const u8 = null;
    var argsSkipped: u8 = 0;

    const firstArgument = args[1];
    if (std.mem.startsWith(u8, firstArgument, "--prefix=")) {
        cwdChange = firstArgument["--prefix=".len..];
        argsSkipped = 1;
    } else if (std.mem.startsWith(u8, firstArgument, "--cwd=")) {
        cwdChange = firstArgument["--cwd=".len..];
        argsSkipped = 1;
    } else if (std.mem.eql(u8, firstArgument, "--prefix") or std.mem.eql(u8, firstArgument, "--cwd")) {
        if (args.len >= 3) {
            cwdChange = args[2];
            argsSkipped = 2;
        }
    }

    if (cwdChange) |dir| {
        const cwdDir = try std.Io.Dir.openDirAbsolute(io, dir, .{});
        defer cwdDir.close(io);
        try std.process.setCurrentDir(io, cwdDir);
    }

    var commandStart: u8 = 1 + argsSkipped;
    const effectiveArgs = args[commandStart..];

    if (effectiveArgs.len < 1) {
        return Nrz.list(alloc, io, colorist);
    }

    const command = effectiveArgs[0];

    if (std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "--help")) {
        return try Nrz.help(io);
    } else if (std.mem.startsWith(u8, command, "--cmp=")) {
        const shell = std.meta.stringToEnum(Nrz.Shell, command["--cmp=".len..]) orelse {
            return error.UnknownShell;
        };

        return Nrz.genCompletions(io, shell);
    } else if (std.mem.eql(u8, command, "--list-cmp")) {
        return Nrz.listCompletions(alloc, io);
    } else if (std.mem.eql(u8, command, "--version")) {
        return Nrz.version(io);
    } else if (std.mem.eql(u8, command, "run")) {
        if (effectiveArgs.len < 2) {
            return error.InvalidInput;
        }

        commandStart += 1;
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
        options,
    );
}
