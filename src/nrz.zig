const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("./helpers.zig");
const mem = @import("./mem.zig");
const buildOptions = @import("build_options");

const Colorist = @import("./colorist.zig");
const Suggestor = helpers.Suggestor;

const Self = @This();

pub const Shell = enum { Zsh, Bash, Fish };

const PackageJson = struct {
    scripts: std.json.ArrayHashMap([]const u8),
};

pub fn run(alloc: std.mem.Allocator, command: []const u8, options: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    const cwdDir = std.process.getCwdAlloc(alloc) catch return;
    defer alloc.free(cwdDir);

    var availableScripts = std.StringHashMap([]const u8).init(alloc);
    defer {
        var iter = availableScripts.iterator();
        while (iter.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
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
            alloc,
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
        if (scriptsMap.get(command)) |script| {
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
                command,
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
                        s.key_ptr.* = try alloc.dupe(u8, script.key_ptr.*);
                        s.value_ptr.* = try alloc.dupe(u8, script.value_ptr.*);
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
        try printCommandNotFound(alloc, command, &availableScripts);
        return;
    }

    var envs = try std.process.getEnvMap(alloc);
    defer envs.deinit();

    const newPath = helpers.concatBinPathsToPATH(alloc, envs.get("PATH").?, cwdDir);
    defer alloc.free(newPath);
    envs.put("PATH", newPath) catch unreachable;

    if (foundRunnable.? == .Script) {
        var selfExePathBuf: [std.fs.max_path_bytes]u8 = undefined;
        const selfExePath = std.fs.selfExePath(&selfExePathBuf) catch "";
        envs.put("npm_execpath", selfExePath) catch unreachable;

        envs.put("INIT_CWD", cwdDir) catch unreachable;
    }

    if (options.len > 0) {
        runnable = std.fmt.bufPrint(&pkgContentsBuf, "{s} {s}", .{
            runnable,
            options,
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

    _ = std.process.execve(alloc, &[_][]const u8{
        shell,
        "-c",
        runnable,
    }, &envs) catch unreachable;
}

fn printCommandNotFound(
    alloc: std.mem.Allocator,
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

    var availableScriptsList = try std.ArrayList(*[]const u8).initCapacity(alloc, availableScriptsSize);
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

pub fn help() void {
    const text =
        \\Supa-Fast™ cross package manager scripts runner and more
        \\
        \\Usage: nrz [command] [...script options]
        \\
        \\Arguments:
        \\  [command] - package manager command (run, more to come...) or script name to run. You can skip this as shorthand to `run`
        \\
        \\Options:
        \\  -h, --help          - print this message
        \\  --cmp=Zsh|Bash|Fish - generate completions for shells
        \\  --list-cmp          - list available scripts for completions
        \\
        \\Example:
        \\  nrz              - will print out all scripts from closest package.json
        \\  nrz dev          - run dev command from closest package.json
        \\  nrz eslint ./src - run eslint command from closest node_modules with ./src argument
        \\
    ;
    std.io.getStdOut().writeAll(text) catch unreachable;
}

pub fn version() void {
    const stdout = std.io.getStdOut().writer();

    stdout.print("nrz {d}.{d}.{d}\n", .{
        buildOptions.version.major,
        buildOptions.version.minor,
        buildOptions.version.patch,
    }) catch unreachable;
}

pub fn list(alloc: std.mem.Allocator, config: struct { showAsCompletions: bool = false }) !void {
    const colorist = Colorist.new();

    const cwdDir = std.process.getCwdAlloc(alloc) catch return;
    defer alloc.free(cwdDir);

    const writer = std.io.getStdOut().writer();
    var buffer = std.io.bufferedWriter(writer);
    defer buffer.flush() catch unreachable;

    var stdout = buffer.writer();

    var dirWalker = helpers.DirIterator.init(cwdDir);

    var pkgPathBuf: [std.fs.max_path_bytes + 1 + std.fs.MAX_NAME_BYTES]u8 = undefined;
    var pkgContentsBuf: [64000]u8 = undefined; // 64kb should be enough for every package.json ?
    while (dirWalker.next()) |dir| {
        const pkgPath = std.fmt.bufPrint(&pkgPathBuf, "{s}{c}package.json", .{
            dir,
            std.fs.path.sep,
        }) catch unreachable;

        const pkgFile = std.fs.openFileAbsolute(pkgPath, .{}) catch continue;
        const packageJson = helpers.readJson(
            PackageJson,
            alloc,
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
            if (config.showAsCompletions) {
                for (script.key_ptr.*) |char| {
                    if (char == ':') {
                        stdout.writeByte('\\') catch unreachable;
                    }
                    stdout.writeByte(char) catch unreachable;
                }
                stdout.print(" - {s}\n", .{script.value_ptr.*}) catch unreachable;
            } else {
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
        }
    }

    if (!config.showAsCompletions) {
        stdout.print("\nType {s}nrz -h{s} to print help message\n", .{
            colorist.getColor(.Dimmed),
            colorist.getColor(.Reset),
        }) catch unreachable;
    }
}

pub fn genCompletions(shell: Shell) !void {
    const completions = switch (shell) {
        .Zsh =>
        \\#compdef nrz
        \\_mycommand() {
        \\  local output=$(nrz --list-cmp)
        \\  local -a lines=(${(f)output})
        \\  local -a completions
        \\
        \\  for line in "${lines[@]}"; do
        \\    local value=${line%% - *}
        \\    local description=${line#* - }
        \\    completions+=("$value:$description")
        \\  done
        \\
        \\  _describe 'nrz subcommand' completions
        \\}
        \\
        \\compdef _mycommand nrz
        \\
        ,
        .Bash =>
        \\_nrz_completion() {
        \\    local cur prev opts
        \\    COMPREPLY=()
        \\    cur="${COMP_WORDS[COMP_CWORD]}"
        \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
        \\
        \\    if [[ "$COMP_CWORD" -eq 1 ]]; then
        \\        local output=$(nrz --list-cmp)
        \\        local -a subcommands
        \\        while IFS=' - ' read -r value description; do
        \\            subcommands+=("$value")
        \\        done <<< "$output"
        \\        COMPREPLY=($(compgen -W "${subcommands[*]}" -- "$cur"))
        \\    fi
        \\}
        \\complete -F _nrz_completion nrz
        \\
        ,
        .Fish =>
        \\function _nrz_completions
        \\    set -l output (nrz --list-cmp)
        \\    for line in $output
        \\        set -l parts (string split " - " $line)
        \\        if test (count $parts) -ge 2
        \\            set -l value $parts[1]
        \\            set -l description (string join " - " $parts[2..])
        \\            complete -c nrz -a "$value" -d "$description"
        \\        end
        \\    end
        \\end
        \\
        \\complete -c nrz -f --no-files -x -n "not __fish_seen_subcommand_from _nrz_completions" -a "(_nrz_completions)"
        \\
        ,
    };

    std.io.getStdOut().writeAll(completions) catch unreachable;
}
