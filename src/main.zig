const std = @import("std");
const string = @import("./string.zig");

const Allocator = std.mem.Allocator;
const String = string.String;

// max 16kb
const MAX_PACKAGE_JSON = 16384;
const PackageJsonPrefix = "/package.json";
const NodeModulesPrefix = "/node_modules";
const NrzMode = enum { Run, Help };

const Nrz = struct {
    alloc: Allocator,

    mode: NrzMode,
    command: String,
    options: String,

    const PackageJson = struct {
        scripts: std.json.ArrayHashMap([]u8),
    };

    pub fn parse(alloc: Allocator, argv: [][:0]u8) !Nrz {
        if (argv.len < 2) {
            return error.InvalidInput;
        }

        var commandStart: u8 = 1;

        var mode = NrzMode.Run;
        if (std.ascii.eqlIgnoreCase("run", argv[1])) {
            if (argv.len < 3) {
                return error.InvalidInput;
            }

            commandStart = 2;
        } else if (std.ascii.eqlIgnoreCase("help", argv[1])) {
            mode = NrzMode.Help;
        }

        const command = try String.init(alloc, argv[commandStart]);

        var options = try String.init(alloc, "");
        for (commandStart + 1..argv.len) |i| {
            try options.concat(argv[i]);

            if (i != argv.len - 1) {
                try options.concat(" ");
            }
        }

        return .{
            .alloc = alloc,
            .mode = mode,
            .command = command,
            .options = options,
        };
    }

    fn deinit(self: Nrz) void {
        self.command.deinit();
        self.options.deinit();
    }

    fn run(self: Nrz) !void {
        const cwdDir = try std.fs.cwd().realpathAlloc(self.alloc, ".");

        var packagePath = try String.init(self.alloc, cwdDir);
        defer packagePath.deinit();

        self.alloc.free(cwdDir);

        var fileBuf: ?[]u8 = undefined;

        while (packagePath.len != 0) {
            const prevPackageJsonPathLen = packagePath.len;

            try packagePath.concat(PackageJsonPrefix);

            if (std.fs.openFileAbsoluteZ(packagePath.value(), .{})) |file| {
                defer file.close();

                // TODO: maybe use json reader ?
                fileBuf = try file.reader().readAllAlloc(self.alloc, MAX_PACKAGE_JSON);
                packagePath.chop(prevPackageJsonPathLen);

                break;
            } else |_| {
                // climb up
            }

            // force to search from old path
            packagePath.chop(prevPackageJsonPathLen);

            if (packagePath.findLast('/')) |nextSlash| {
                packagePath.len = nextSlash;
            } else {
                packagePath.len = 0;
            }
        }

        if (fileBuf) |fileString| {
            defer self.alloc.free(fileString);

            var nodeModulesBinPath = try packagePath.copy();
            defer nodeModulesBinPath.deinit();

            try nodeModulesBinPath.concat(NodeModulesPrefix);
            try nodeModulesBinPath.concat(".bin");

            std.debug.print("{s}\n", .{nodeModulesBinPath.value()});
            if (std.fs.openDirAbsoluteZ(nodeModulesBinPath.value(), .{ .iterate = true })) |dir| {
                defer dir.close();

                std.debug.print("{s}\n", .{nodeModulesBinPath.value()});
            } else |_| {}

            const parsed = try std.json.parseFromSlice(PackageJson, self.alloc, fileString, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();

            if (parsed.value.scripts.map.get(self.command.value())) |script| {
                std.debug.print("Will run this command \"{s}: {s}\"\n", .{ self.command.value(), script });
            }

            std.debug.print("{s}\n", .{packagePath.value()});
        } else {
            std.debug.print("No package.json was found.", .{});
        }

        // 3. Check if node_modules/.bin dir has run command
        // 4. Execute command by directly calling bin executable or package.json command with
        // correct env
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const nrz = try Nrz.parse(alloc, args);
    defer nrz.deinit();

    try nrz.run();

    std.debug.print("nrz option: {s}\n", .{@tagName(nrz.mode)});
    std.debug.print("nrz command: {s}\n", .{nrz.command.value()});

    // // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
