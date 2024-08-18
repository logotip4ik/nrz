const std = @import("std");
const builtin = @import("builtin");

const string = @import("string");
const suggest = @import("suggest");

const Allocator = std.mem.Allocator;
const String = string.String;
const Suggestor = suggest.Suggestor;

// max 32kb
const MAX_PACKAGE_JSON = 32768;
const PackageJsonPrefix = "/package.json";
const NodeModulesBinPrefix = "/node_modules/.bin";

const NrzMode = enum {
    Run,
    List,
    Help,
};

const Nrz = struct {
    alloc: Allocator,

    mode: NrzMode,
    command: ?String,
    options: ?String,

    pub fn init(alloc: Allocator, argv: [][]const u8) !Nrz {
        if (argv.len < 2) {
            return .{
                .alloc = alloc,
                .mode = .List,
                .command = null,
                .options = null,
            };
        }

        const firstArgument = argv[1];

        if (std.mem.eql(u8, "-h", firstArgument) or std.mem.eql(u8, "--help", firstArgument)) {
            return .{
                .alloc = alloc,
                .mode = .Help,
                .command = null,
                .options = null,
            };
        }

        var commandStart: u8 = 1;

        if (std.mem.eql(u8, "run", firstArgument)) {
            if (argv.len < 3) {
                return error.InvalidInput;
            }

            commandStart = 2;
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
            .mode = .Run,
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

        inline fn setNext(self: *DirIterator) bool {
            if (self.dir.findLast('/')) |nextSlash| {
                self.dir.chop(nextSlash);

                return true;
            } else {
                return false;
            }
        }

        inline fn next(self: *DirIterator) !?struct { packageJson: std.fs.File, dir: []const u8 } {
            while (self.setNext()) {
                self.prevDirLen = self.dir.len;

                try self.dir.concat(PackageJsonPrefix);

                if (std.fs.openFileAbsolute(self.dir.value(), .{})) |file| {
                    self.dir.chop(self.prevDirLen);

                    return .{ .packageJson = file, .dir = self.dir.value() };
                } else |_| {
                    self.dir.chop(self.prevDirLen);
                }
            }

            return null;
        }
    };

    inline fn concatBinPathsToPath(alloc: Allocator, path: *String, cwd: []const u8) !void {
        var cwdString = try String.init(alloc, cwd);
        defer cwdString.deinit();

        try path.concat(":");
        try path.concat(cwdString.value());
        try path.concat(NodeModulesBinPrefix);

        while (cwdString.len > 1) {
            const nextSlash = cwdString.findLast('/');

            if (nextSlash) |idx| {
                if (idx == 0) {
                    // skipping adding `/node_modules/.bin` at the very root
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

    inline fn findBestShell() ?[]const u8 {
        const shells = &[_][]const u8{
            "/bin/bash",
            "/usr/bin/bash",
            "/bin/sh",
            "/usr/bin/sh",
            "/bin/zsh",
            "/usr/bin/zsh",
            "/usr/local/bin/zsh",
        };

        inline for (shells) |shell| {
            if (std.fs.accessAbsolute(shell, .{})) {
                return shell;
            } else |_| {}
        }

        return null;
    }

    const PackageJson = struct {
        scripts: std.json.ArrayHashMap([]const u8),
    };

    fn run(self: Nrz) !void {
        const stdout = std.io.getStdOut().writer();

        const cwdDir = std.process.getCwdAlloc(self.alloc) catch unreachable;
        defer self.alloc.free(cwdDir);

        var packageWalker = try DirIterator.init(self.alloc, cwdDir);
        defer packageWalker.deinit();

        const commandValue = self.command.?.value();

        var foundRunable = false;
        var runable = try String.init(self.alloc, "");
        defer runable.deinit();

        var availableScripts = std.ArrayList([]const u8).init(self.alloc);
        defer {
            for (availableScripts.items) |item| self.alloc.free(item);
            availableScripts.deinit();
        }

        while (try packageWalker.next()) |entry| {
            defer entry.packageJson.close();

            const fileString = try entry.packageJson.readToEndAlloc(self.alloc, MAX_PACKAGE_JSON);
            defer self.alloc.free(fileString);

            const packageJson = try std.json.parseFromSlice(
                PackageJson,
                self.alloc,
                fileString,
                .{ .ignore_unknown_fields = true },
            );
            defer packageJson.deinit();

            const scriptsMap = packageJson.value.scripts.map;

            if (scriptsMap.get(commandValue)) |script| {
                foundRunable = true;

                runable.chop(0);
                try runable.concat(script);
            } else {
                try runable.concat(entry.dir);
                try runable.concat(NodeModulesBinPrefix);
                try runable.concat("/");
                try runable.concat(commandValue);

                if (std.fs.accessAbsolute(runable.value(), .{})) {
                    foundRunable = true;
                } else |_| {
                    var sciptsIterator = scriptsMap.iterator();

                    while (sciptsIterator.next()) |script| {
                        const scriptKeyCopy = try self.alloc.alloc(u8, script.key_ptr.len);

                        std.mem.copyForwards(u8, scriptKeyCopy, script.key_ptr.*);

                        try availableScripts.append(scriptKeyCopy);
                    }
                }
            }

            if (foundRunable) {
                var runDir = try std.fs.cwd().openDir(entry.dir, .{});
                defer runDir.close();

                try runDir.setAsCwd();

                break;
            }
        } else {
            stdout.print(
                "\u{001B}[2mcommand not found:\u{001B}[0m \u{001B}[1;37m{s}\u{001B}[0m\n\nDid you mean:\n",
                .{commandValue},
            ) catch unreachable;

            var scriptSuggestor = try Suggestor.init(self.alloc, availableScripts);
            defer scriptSuggestor.deinit();

            var showed: u8 = 0;

            while (try scriptSuggestor.next(commandValue)) |suggested| : (showed += 1) {
                if (showed == 3) {
                    break;
                }

                try stdout.print(" - \u{001b}[3m{s}\u{001B}[0m\n", .{suggested});
            }

            return;
        }

        const options = self.options.?;

        // white bold $ gray dimmed command with options
        stdout.print("\u{001B}[1;37m$\u{001B}[0m \u{001B}[2m{s} {s}\u{001B}[0m\n\n", .{
            runable.value(),
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
            try runable.concat(" ");
            try runable.concat(options.value());
        }

        const maybeShell = Nrz.findBestShell();

        if (maybeShell) |shell| {
            _ = std.process.execve(self.alloc, &[_][]const u8{
                shell,
                "-c",
                runable.value(),
            }, &envs) catch unreachable;
        } else {
            stdout.print("how are you even working ?", .{}) catch unreachable;
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
        std.io.getStdOut().writeAll(text ++ "\n") catch unreachable;
    }

    fn list(self: Nrz) !void {
        const cwdDir = std.process.getCwdAlloc(self.alloc) catch unreachable;
        defer self.alloc.free(cwdDir);

        var packageWalker = try DirIterator.init(self.alloc, cwdDir);
        defer packageWalker.deinit();

        const writer = std.io.getStdOut().writer();
        var buffer = std.io.bufferedWriter(writer);
        var stdout = buffer.writer();

        // find first
        if (try packageWalker.next()) |entry| {
            const fileString = try entry.packageJson.readToEndAlloc(self.alloc, MAX_PACKAGE_JSON);
            defer self.alloc.free(fileString);

            const packageJson = try std.json.parseFromSlice(PackageJson, self.alloc, fileString, .{ .ignore_unknown_fields = true });
            defer packageJson.deinit();

            var sciptsIterator = packageJson.value.scripts.map.iterator();

            while (sciptsIterator.next()) |mapEntry| {
                stdout.print("\u{001B}[1;37m{s}\u{001B}[0m:\u{001B}[2m {s}\u{001B}[0m\n", .{
                    mapEntry.key_ptr.*,
                    mapEntry.value_ptr.*,
                }) catch unreachable;
            }

            stdout.print("\nType \u{001B}[2mnrz help\u{001B}[0m to print help message\n", .{}) catch unreachable;
        } else {
            stdout.print("No package.json was found...\n", .{}) catch unreachable;
        }

        try buffer.flush();
    }
};

pub fn main() !void {
    var gpa = comptime if (builtin.mode == .ReleaseFast) std.heap.ArenaAllocator.init(std.heap.page_allocator) else std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const nrz = try Nrz.init(alloc, args);
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

    try testing.expectEqualStrings("path:path2:/dev/nrz/node_modules/.bin:/dev/node_modules/.bin", path.value());
}
