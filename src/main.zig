const std = @import("std");
const builtin = @import("builtin");
const buildOptions = @import("build_options");

const string = @import("./string.zig");
const constants = @import("./constants.zig");
const helpers = @import("./helpers.zig");
const colors = @import("./colors.zig");
const mem = @import("./mem.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const String = string.String;
const Suggestor = helpers.Suggestor;
const Colorist = colors.Colorist;

const Nrz = struct {
    alloc: Allocator,

    mode: enum {
        Run,
        List,
        Help,
        Version,
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
        var commandStart: u8 = 1;

        if (std.mem.eql(u8, "-h", firstArgument) or std.mem.eql(u8, "--help", firstArgument)) {
            return .{
                .alloc = alloc,
                .mode = .Help,
                .command = null,
                .options = null,
            };
        } else if (std.mem.eql(u8, "--version", firstArgument)) {
            return .{
                .alloc = alloc,
                .mode = .Version,
                .command = null,
                .options = null,
            };
        } else if (std.mem.eql(u8, "run", firstArgument)) {
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

        const cwdDir = std.process.getCwdAlloc(self.alloc) catch return;
        defer self.alloc.free(cwdDir);

        const commandValue = self.command.?.value();

        var availableScripts = std.StringHashMap([]const u8).init(self.alloc);
        defer {
            var iter = availableScripts.iterator();
            while (iter.next()) |entry| {
                self.alloc.free(entry.key_ptr.*);
                self.alloc.free(entry.value_ptr.*);
            }
            availableScripts.deinit();
        }

        var runnable: []const u8 = undefined;
        var foundRunnable: ?enum { Script, Bin } = null;

        var dirWalker = helpers.DirIterator.init(cwdDir);
        var pkgPathBuf: [std.fs.max_path_bytes + 1 + std.fs.MAX_NAME_BYTES]u8 = undefined;
        var pkgContentsBuf: [64000]u8 = undefined; // 64kb should be enough for every package.json ?
        while (dirWalker.next()) |dir| {
            const pkgPath = std.fmt.bufPrint(&pkgPathBuf, "{s}{c}package.json", .{
                dir,
                std.fs.path.sep,
            }) catch unreachable;

            const pkgFile = std.fs.openFileAbsolute(pkgPath, .{}) catch continue;
            defer pkgFile.close();

            const packageJson = helpers.readJson(
                PackageJson,
                self.alloc,
                pkgFile,
                &pkgContentsBuf,
            ) catch |err| switch (err) {
                error.FileRead => {
                    stdout.print("Failed reading: {s}\n", .{pkgPath}) catch unreachable;
                    return;
                },
                error.InvalidJson => {
                    stdout.print("Failed at json parsing: {s}\n", .{pkgPath}) catch unreachable;
                    return;
                },
                error.InvalidJsonWithFullBuffer => {
                    stdout.print(
                        "Failed at json parsing (possibly didn't read all of json. Please open issue with 002 code at logotip4ik/nrz): {s}\n",
                        .{pkgPath},
                    ) catch unreachable;
                    return;
                },
            };

            defer packageJson.deinit();

            const scriptsMap = packageJson.value.scripts.map;
            if (scriptsMap.get(commandValue)) |script| {
                // script in package.json could be empty string
                foundRunnable = .Script;

                mem.move(u8, &pkgPathBuf, script);

                runnable = pkgPathBuf[0..script.len];
            } else {
                const binPath = std.fmt.bufPrint(&pkgPathBuf, "{s}{c}node_modules{c}.bin{c}{s}", .{
                    dir,
                    std.fs.path.sep,
                    std.fs.path.sep,
                    std.fs.path.sep,
                    commandValue,
                }) catch @panic("if you see this, open issue at logotip4ik/nrz with code 003");

                if (std.fs.openFileAbsolute(binPath, .{})) |file| {
                    defer file.close();

                    foundRunnable = .Bin;
                    runnable = binPath;
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

            if (foundRunnable != null) {
                var runDir = try std.fs.openDirAbsolute(dir, .{});
                defer runDir.close();

                try runDir.setAsCwd();

                break;
            }
        } else {
            try self.printCommandNotFound(commandValue, &availableScripts);
            return;
        }

        var envs = try std.process.getEnvMap(self.alloc);
        defer envs.deinit();

        const newPath = helpers.concatBinPathsToPATH(self.alloc, envs.get("PATH").?, cwdDir);
        defer self.alloc.free(newPath);
        envs.put("PATH", newPath) catch unreachable;

        if (foundRunnable.? == .Script) {
            var selfExePathBuf: [std.fs.max_path_bytes]u8 = undefined;
            const selfExePath = std.fs.selfExePath(&selfExePathBuf) catch "";
            envs.put("npm_execpath", selfExePath) catch unreachable;

            envs.put("INIT_CWD", cwdDir) catch unreachable;
        }

        const options = self.options orelse return;

        if (options.len > 0) {
            runnable = std.fmt.bufPrint(&pkgContentsBuf, "{s} {s}", .{
                runnable,
                options.value(),
            }) catch unreachable;
        }

        const colorist = Colorist.new();
        stdout.print("{s}${s} {s}{s}{s}\n\n", .{
            colorist.getColor(.WhiteBold),
            colorist.getColor(.Reset),
            //
            colorist.getColor(.Dimmed),
            runnable,
            colorist.getColor(.Reset),
        }) catch unreachable;

        const shell = helpers.findBestShell() orelse {
            stdout.print("how are you even working ?\n", .{}) catch unreachable;
            return;
        };

        if (comptime builtin.mode != .ReleaseFast) {
            // won't run the script, but will allow gpa to log memory leaks
            return;
        }

        _ = std.process.execve(self.alloc, &[_][]const u8{
            shell,
            "-c",
            runnable,
        }, &envs) catch unreachable;
    }

    fn printCommandNotFound(
        self: Nrz,
        command: []const u8,
        availableScripts: *const std.StringHashMap([]const u8),
    ) !void {
        const writer = std.io.getStdOut().writer();
        var buffer = std.io.bufferedWriter(writer);
        var stdout = buffer.writer();
        defer buffer.flush() catch unreachable;

        const colorist = Colorist.new();

        stdout.print("{s}command not found:{s} {s}{s}{s}\n", .{
            colorist.getColor(.Dimmed),
            //
            colorist.getColor(.Reset),
            //
            colorist.getColor(.WhiteBold),
            command,
            colorist.getColor(.Reset),
        }) catch unreachable;

        const availableScriptsSize = availableScripts.count();
        if (availableScriptsSize == 0) {
            return;
        }

        var availableScriptsList = try std.ArrayList(*[]const u8).initCapacity(self.alloc, availableScriptsSize);
        // items inside will be cleared by availableScripts defer statement
        defer availableScriptsList.deinit();

        var scriptsIter = availableScripts.keyIterator();
        while (scriptsIter.next()) |key| {
            availableScriptsList.appendAssumeCapacity(key);
        }

        const scriptSuggestor = Suggestor{
            .items = &availableScriptsList,
        };

        stdout.print("\nDid you mean:\n", .{}) catch unreachable;

        var showed: u8 = 0;
        while (scriptSuggestor.next(command)) |suggested| : (showed += 1) {
            if (showed == 3) {
                break;
            }

            const scriptCommand = availableScripts.get(suggested.*);

            stdout.print(" - {s}{s}{s}: {s}{s}{s}\n", .{
                colorist.getColor(.WhiteBold),
                suggested.*,
                colorist.getColor(.Reset),
                //
                colorist.getColor(.Dimmed),
                scriptCommand.?,
                colorist.getColor(.Reset),
            }) catch unreachable;
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

    fn version(_: Nrz) void {
        const stdout = std.io.getStdOut().writer();

        stdout.print("nrz {d}.{d}.{d}\n", .{
            buildOptions.version.major,
            buildOptions.version.minor,
            buildOptions.version.patch,
        }) catch unreachable;
    }

    fn list(self: Nrz) !void {
        const colorist = Colorist.new();

        const cwdDir = std.process.getCwdAlloc(self.alloc) catch return;
        defer self.alloc.free(cwdDir);

        const writer = std.io.getStdOut().writer();
        var buffer = std.io.bufferedWriter(writer);
        defer buffer.flush() catch unreachable;

        var stdout = buffer.writer();

        var dirWalker = helpers.DirIterator.init(cwdDir);

        var pkgPathBuf: [std.fs.MAX_PATH_BYTES + 1 + std.fs.MAX_NAME_BYTES]u8 = undefined;
        var pkgContentsBuf: [64000]u8 = undefined; // 64kb should be enough for every package.json ?
        while (dirWalker.next()) |dir| {
            const pkgPath = std.fmt.bufPrint(&pkgPathBuf, "{s}{c}package.json", .{
                dir,
                std.fs.path.sep,
            }) catch unreachable;

            const pkgFile = std.fs.openFileAbsolute(pkgPath, .{}) catch continue;
            const packageJson = helpers.readJson(
                PackageJson,
                self.alloc,
                pkgFile,
                &pkgContentsBuf,
            ) catch {
                stdout.print("Failed to parse {s}\n", .{pkgPath}) catch unreachable;
                return;
            };
            defer packageJson.deinit();

            const scriptsMap = packageJson.value.scripts.map;
            var sciptsIterator = scriptsMap.iterator();

            while (sciptsIterator.next()) |script| {
                stdout.print("{s}{s}{s}: {s}{s}{s}\n", .{
                    colorist.getColor(.WhiteBold),
                    script.key_ptr.*,
                    colorist.getColor(.Reset),
                    //
                    colorist.getColor(.Dimmed),
                    script.value_ptr.*,
                    colorist.getColor(.Reset),
                }) catch unreachable;
            }

            stdout.print("\nType {s}nrz -h{s} to print help message\n", .{
                colorist.getColor(.Dimmed),
                colorist.getColor(.Reset),
            }) catch unreachable;

            break;
        } else {
            stdout.print("No package.json was found...\n", .{}) catch unreachable;
        }
    }
};

pub fn main() !void {
    const allocator = comptime mem.getAllocator();
    const alloc = allocator.allocator();
    defer allocator.deinit();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var nrz = try Nrz.init(alloc, args);
    defer nrz.deinit();

    switch (nrz.mode) {
        .Run => try nrz.run(),
        .Help => nrz.help(),
        .List => try nrz.list(),
        .Version => nrz.version(),
    }
}
