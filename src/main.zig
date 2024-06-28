const std = @import("std");
const string = @import("./string.zig");

const Allocator = std.mem.Allocator;
const String = string.String;

// max 16kb
const MAX_PACKAGE_JSON = 16384;
const PackageJsonPrefix = "/package.json";
const NodeModulesBinPrefix = "/node_modules/.bin/";

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

    const DirIterator = struct {
        alloc: Allocator,
        dir: String,
        prevDirLen: usize,

        pub fn init(alloc: Allocator, startDir: []const u8) !DirIterator {
            var dir = try String.init(alloc, startDir);
            try dir.concat("/");

            return .{
                .alloc = alloc,
                .dir = dir,
                .prevDirLen = dir.len,
            };
        }

        pub fn deinit(self: DirIterator) void {
            self.dir.deinit();
        }

        fn setNext(self: *DirIterator) bool {
            if (self.dir.findLast('/')) |nextSlash| {
                self.dir.chop(nextSlash);

                return true;
            } else {
                return false;
            }
        }

        pub fn next(self: *DirIterator) !?struct { packageJson: std.fs.File, dir: [:0]const u8 } {
            while (self.setNext()) {
                self.prevDirLen = self.dir.len;

                try self.dir.concat(PackageJsonPrefix);

                if (std.fs.openFileAbsoluteZ(self.dir.value(), .{})) |file| {
                    self.dir.chop(self.prevDirLen);

                    return .{ .packageJson = file, .dir = self.dir.value() };
                } else |_| {
                    self.dir.chop(self.prevDirLen);
                }
            }

            return null;
        }
    };

    fn run(self: Nrz) !void {
        const cwdDir = try std.process.getCwdAlloc(self.alloc);
        defer self.alloc.free(cwdDir);

        var packageWalker = try DirIterator.init(self.alloc, cwdDir);
        defer packageWalker.deinit();

        while (try packageWalker.next()) |entry| {
            const fileString = try entry.packageJson.readToEndAlloc(self.alloc, MAX_PACKAGE_JSON);
            defer self.alloc.free(fileString);

            const packgeJson = try std.json.parseFromSlice(PackageJson, self.alloc, fileString, .{ .ignore_unknown_fields = true });
            defer packgeJson.deinit();

            if (packgeJson.value.scripts.map.get(self.command.value())) |script| {
                _ = script;
                break;
            } else {
                var nodeModulesBinString = try String.init(self.alloc, entry.dir);
                defer nodeModulesBinString.deinit();

                try nodeModulesBinString.concat(NodeModulesBinPrefix);
                try nodeModulesBinString.concat(self.command.value());

                std.debug.print("{s}\n", .{nodeModulesBinString.value()});

                if (std.fs.accessAbsoluteZ(nodeModulesBinString.value(), .{})) {
                    break;
                } else |_| {
                    // noop
                }
            }
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
