const std = @import("std");
const builtin = @import("builtin");

const string = @import("./string.zig");
const constants = @import("./constants.zig");
const helpers = @import("./helpers.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const String = string.String;
const DirIterator = helpers.DirIterator;
const Suggestor = helpers.Suggestor;

const Nrz = struct {
    alloc: Allocator,

    mode: enum {
        Run,
        List,
        Help,
    },
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

        var availableScripts = std.StringHashMap([]const u8).init(self.alloc);
        defer {
            var iter = availableScripts.iterator();
            while (iter.next()) |entry| {
                self.alloc.free(entry.key_ptr.*);
                self.alloc.free(entry.value_ptr.*);
            }
        }

        while (try packageWalker.next()) |entry| {
            defer entry.packageJson.close();

            const fileString = try entry.packageJson.readToEndAlloc(self.alloc, constants.PackageJsonLenMax);
            defer self.alloc.free(fileString);

            const packageJson = std.json.parseFromSlice(
                PackageJson,
                self.alloc,
                fileString,
                .{
                    .ignore_unknown_fields = true,
                    .allocate = .alloc_if_needed,
                    .duplicate_field_behavior = .use_last,
                    .max_value_len = std.math.maxInt(u16),
                },
            ) catch {
                stdout.print("Failed to parse package.json in {s}.\n", .{entry.dir}) catch unreachable;
                return;
            };

            defer packageJson.deinit();

            const scriptsMap = packageJson.value.scripts.map;

            runable.chop(0);

            if (scriptsMap.get(commandValue)) |script| {
                foundRunable = true;

                try runable.concat(script);
            } else {
                try runable.concat(entry.dir);
                try runable.concat(constants.NodeModulesBinPrefix);
                try runable.concat("/");
                try runable.concat(commandValue);

                if (std.fs.accessAbsolute(runable.value(), .{})) {
                    foundRunable = true;
                } else |_| {
                    var sciptsIterator = scriptsMap.iterator();

                    while (sciptsIterator.next()) |script| {
                        const s = try availableScripts.getOrPut(script.key_ptr.*);
                        if (!s.found_existing) {
                            s.key_ptr.* = try self.alloc.dupe(u8, script.key_ptr.*);
                            s.value_ptr.* = try self.alloc.dupe(u8, script.value_ptr.*);
                        }
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
                "\u{001B}[2mcommand not found:\u{001B}[0m \u{001B}[1;37m{s}\u{001B}[0m\n",
                .{commandValue},
            ) catch unreachable;

            const availableScriptsSize = availableScripts.capacity();
            if (availableScriptsSize == 0) {
                return;
            }

            var availableScriptsList = try std.ArrayList([]const u8).initCapacity(self.alloc, availableScriptsSize);
            defer {
                for (availableScriptsList.items) |item| self.alloc.free(item);
                availableScriptsList.deinit();
            }

            var scriptsIter = availableScripts.keyIterator();
            while (scriptsIter.next()) |key| {
                availableScriptsList.appendAssumeCapacity(key.*);
            }

            const scriptSuggestor = Suggestor{
                .alloc = self.alloc,
                .items = &availableScriptsList,
            };

            stdout.print("\nDid you mean:\n", .{}) catch unreachable;

            var showed: u8 = 0;
            while (scriptSuggestor.next(commandValue)) |suggested| : (showed += 1) {
                if (showed == 3) {
                    break;
                }

                const scriptCommand = availableScripts.get(suggested);

                stdout.print(" - \u{001b}[1;3m{s}\u{001B}[0m: \u{001B}[2m{s}\u{001B}[0m\n", .{ suggested, scriptCommand.? }) catch unreachable;
            }

            return;
        }

        const options = self.options.?;

        var envs = try std.process.getEnvMap(self.alloc);
        defer envs.deinit();

        const pathKey = "PATH";
        var pathString = try String.init(self.alloc, envs.get(pathKey).?);
        defer pathString.deinit();

        try helpers.concatBinPathsToPath(self.alloc, &pathString, cwdDir);

        try envs.put(pathKey, pathString.value());

        if (options.len > 0) {
            try runable.concat(" ");
            try runable.concat(options.value());
        }

        const runnableValue = runable.value();

        // white bold $ gray dimmed command
        stdout.print("\u{001B}[1;37m$\u{001B}[0m \u{001B}[2m{s}\u{001B}[0m\n\n", .{
            runnableValue,
        }) catch unreachable;

        const maybeShell = helpers.findBestShell();

        if (maybeShell) |shell| {
            _ = std.process.execve(self.alloc, &[_][]const u8{
                shell,
                "-c",
                runnableValue,
            }, &envs) catch unreachable;
        } else {
            stdout.print("how are you even working ?\n", .{}) catch unreachable;
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
            \\
        ;
        std.io.getStdOut().writeAll(text) catch unreachable;
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
            const fileString = try entry.packageJson.readToEndAlloc(self.alloc, constants.PackageJsonLenMax);
            defer self.alloc.free(fileString);

            const packageJson = std.json.parseFromSlice(
                PackageJson,
                self.alloc,
                fileString,
                .{
                    .ignore_unknown_fields = true,
                    .allocate = .alloc_if_needed,
                    .duplicate_field_behavior = .use_last,
                    .max_value_len = std.math.maxInt(u16),
                },
            ) catch {
                stdout.print("Failed to parse package.json in {s}.\n", .{entry.dir}) catch unreachable;
                return;
            };
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
    @setFloatMode(.optimized);

    var gpa = comptime if (builtin.mode == .ReleaseFast) std.heap.ArenaAllocator.init(std.heap.page_allocator) else std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var nrz = try Nrz.init(alloc, args);
    defer nrz.deinit();

    switch (nrz.mode) {
        .Run => try nrz.run(),
        .Help => nrz.help(),
        .List => try nrz.list(),
    }
}
