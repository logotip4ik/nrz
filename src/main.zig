const std = @import("std");
const string = @import("./string.zig");

const Allocator = std.mem.Allocator;
const String = string.String;

// max 32kb
const MAX_PACKAGE_JSON = 32768;
const PackageJsonPrefix = "/package.json";
const NodeModulesBinPrefix = "/node_modules/.bin";

const NrzMode = enum { Run, Help, List };

const Nrz = struct {
    alloc: Allocator,

    mode: NrzMode,
    command: ?String,
    options: ?String,

    pub fn parse(alloc: Allocator, argv: [][:0]u8) !Nrz {
        if (argv.len < 2) {
            return .{
                .alloc = alloc,
                .mode = .List,
                .command = null,
                .options = null,
            };
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
        if (self.command) |command| command.deinit();
        if (self.options) |options| options.deinit();
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

    pub fn concatBinPathsToPath(alloc: Allocator, path: *String, cwd: []const u8) !void {
        var cwdString = try String.init(alloc, cwd);
        defer cwdString.deinit();

        try path.concat(":");
        try path.concat(cwdString.value());
        try path.concat(NodeModulesBinPrefix);

        while (cwdString.len > 1) {
            const nextSlash = cwdString.findLast('/');

            if (nextSlash) |idx| {
                if (idx == 0) {
                    // skipping adding `/node_modules/.bin`, very root dir
                    break;
                }

                cwdString.chop(idx);

                try path.concat(":");
                try path.concat(cwdString.value());
                try path.concat(NodeModulesBinPrefix);
            } else {
                cwdString.chop(0);
            }
        }
    }

    const PackageJson = struct {
        scripts: std.json.ArrayHashMap([]u8),
    };

    fn run(self: Nrz) !void {
        const cwdDir = std.process.getCwdAlloc(self.alloc) catch unreachable;
        defer self.alloc.free(cwdDir);

        var packageWalker = try DirIterator.init(self.alloc, cwdDir);
        defer packageWalker.deinit();

        const commandValue = self.command.?.value();
        var runable: ?String = null;

        while (try packageWalker.next()) |entry| {
            const fileString = try entry.packageJson.readToEndAlloc(self.alloc, MAX_PACKAGE_JSON);
            defer self.alloc.free(fileString);

            const packageJson = try std.json.parseFromSlice(PackageJson, self.alloc, fileString, .{ .ignore_unknown_fields = true });
            defer packageJson.deinit();

            if (packageJson.value.scripts.map.get(commandValue)) |script| {
                runable = try String.init(self.alloc, script);
            } else {
                var nodeModulesBinString = try String.init(self.alloc, entry.dir);

                try nodeModulesBinString.concat(NodeModulesBinPrefix);
                try nodeModulesBinString.concat(commandValue);

                if (std.fs.accessAbsoluteZ(nodeModulesBinString.value(), .{})) {
                    runable = nodeModulesBinString;
                } else |_| {
                    nodeModulesBinString.deinit();
                }
            }

            if (runable != null) {
                break;
            }
        }

        const stdout = std.io.getStdOut().writer();

        if (runable) |*command| {
            defer command.deinit();

            const options = self.options.?;

            // white bold $ gray dimmed command with options
            stdout.print("\u{001B}[1;37m$\u{001B}[0m \u{001B}[2m{s} {s}\u{001B}[0m\n\n", .{
                command.value(),
                options.value(),
            }) catch unreachable;

            var envs = try std.process.getEnvMap(self.alloc);
            defer envs.deinit();

            const pathKey = "PATH";
            var pathString = try String.init(self.alloc, envs.get(pathKey).?);
            defer pathString.deinit();

            try Nrz.concatBinPathsToPath(self.alloc, &pathString, cwdDir);

            try envs.put(pathKey, pathString.value());

            if (options.len > 0) {
                try command.concat(" ");
                try command.concat(options.value());
            }

            _ = std.process.execve(self.alloc, &[_][]const u8{
                "/bin/sh",
                "-c",
                command.value(),
            }, &envs) catch {};
        } else {
            stdout.print("\u{001B}[2mcommand not found:\u{001B}[0m \u{001B}[1;37m{s}\u{001B}[0m\n", .{commandValue}) catch unreachable;
        }
    }

    fn help(_: Nrz) void {
        const text =
            \\Supa-Fast™ cross package manager scripts runner and more
            \\
            \\Usage: nrz [command] [...script options]
            \\
            \\Arguments:
            \\  [command] - package manager command (run, more to come...) or script name to run. You can skip this as shorthand to `run`
            \\
            \\Options:
            \\  -h, --help - print this message
            \\
            \\Example:
            \\  nrz              - will print out all scripts from closest package.json
            \\  nrz dev          - run dev command from closest package.json
            \\  nrz eslint ./src - run eslint command from closest node_modules with ./src argument
        ;
        std.io.getStdOut().writeAll(text) catch unreachable;
    }

    fn list(self: Nrz) !void {
        const cwdDir = std.process.getCwdAlloc(self.alloc) catch unreachable;
        defer self.alloc.free(cwdDir);

        var packageWalker = try DirIterator.init(self.alloc, cwdDir);
        defer packageWalker.deinit();

        const stdout = std.io.getStdOut().writer();

        // find first
        if (try packageWalker.next()) |entry| {
            const fileString = try entry.packageJson.readToEndAlloc(self.alloc, MAX_PACKAGE_JSON);
            defer self.alloc.free(fileString);

            const packageJson = try std.json.parseFromSlice(PackageJson, self.alloc, fileString, .{ .ignore_unknown_fields = true });
            defer packageJson.deinit();

            var sciptsIterator = packageJson.value.scripts.map.iterator();

            while (sciptsIterator.next()) |mapEntry| {
                stdout.print("\u{001B}[1;37m{s}\u{001B}[0m:\u{001B}[2m {s}\u{001B}[0m\n", .{ mapEntry.key_ptr.*, mapEntry.value_ptr.* }) catch unreachable;
            }

            stdout.print("\nType \u{001B}[2mnrz help\u{001B}[0m to print help message\n", .{}) catch unreachable;
        } else {
            stdout.print("No package.json was found...\n", .{}) catch unreachable;
        }
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

    switch (nrz.mode) {
        .Run => try nrz.run(),
        .Help => nrz.help(),
        .List => try nrz.list(),
    }
}

test "Construct path bin dirs" {
    const testing = std.testing;

    var path = try String.init(testing.allocator, "path:path2");
    defer path.deinit();

    try Nrz.concatBinPathsToPath(testing.allocator, &path, "/dev/nrz");

    try testing.expectEqualDeep("path:path2:/dev/nrz/node_modules/.bin/:/dev/node_modules/.bin/", path.value());
}
