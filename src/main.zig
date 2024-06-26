const std = @import("std");
const string = @import("./string.zig");

const Allocator = std.mem.Allocator;
const String = string.String;

// max 16kb
const MAX_PACKAGE_JSON = 16384;
const PackageJsonPrefix = "/package.json";
const NrzMode = enum { Run, Help };

const Nrz = struct {
    alloc: Allocator,

    mode: NrzMode,
    command: String,

    const PackageJson = struct {
        scripts: std.StringHashMap([]u8),
    };

    pub fn parse(alloc: Allocator, argv: [][:0]u8) !Nrz {
        if (argv.len < 2) {
            return error.InvalidInput;
        }

        var forwardStart: u8 = 1;

        var mode = NrzMode.Run;
        if (std.ascii.eqlIgnoreCase("run", argv[1])) {
            if (argv.len < 3) {
                return error.InvalidInput;
            }

            forwardStart = 2;
        } else if (std.ascii.eqlIgnoreCase("help", argv[1])) {
            mode = NrzMode.Help;
        }

        var command = try String.init(alloc, "");
        for (forwardStart..argv.len) |i| {
            try command.concat(argv[i]);

            if (i != argv.len - 1) {
                try command.concat(" ");
            }
        }

        return .{
            .alloc = alloc,
            .mode = mode,
            .command = command,
        };
    }

    fn deinit(self: Nrz) void {
        self.command.deinit();
    }

    fn run(self: Nrz) !void {
        const dir = try std.fs.cwd().realpathAlloc(self.alloc, ".");
        defer self.alloc.free(dir);

        var packageJsonPath = try String.init(self.alloc, dir);
        defer packageJsonPath.deinit();

        var fileBuf: ?[]u8 = undefined;

        while (packageJsonPath.len != 0) {
            const prevPackageJsonPathLen = packageJsonPath.len;

            try packageJsonPath.concat(PackageJsonPrefix);

            if (std.fs.openFileAbsoluteZ(packageJsonPath.value(), .{})) |file| {
                defer file.close();

                // TODO: maybe use json reader ?
                fileBuf = try file.reader().readAllAlloc(self.alloc, MAX_PACKAGE_JSON);

                break;
            } else |_| {
                // climb up
            }

            // force to search from old path
            packageJsonPath.chop(prevPackageJsonPathLen);

            if (packageJsonPath.findLast('/')) |nextSlash| {
                packageJsonPath.len = nextSlash;
            } else {
                packageJsonPath.len = 0;
            }
        }

        if (fileBuf) |fileString| {
            defer self.alloc.free(fileString);

            // 2. Basic json parser with scripts hashmap

            const parsed = try std.json.parseFromSlice(PackageJson, self.alloc, fileString, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();

            std.debug.print("{any}\n", .{parsed.value.scripts});
            // std.debug.print("{s}\n", .{fileString});
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
