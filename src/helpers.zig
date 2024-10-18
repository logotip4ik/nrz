const std = @import("std");

const string = @import("./string.zig");
const constants = @import("./constants.zig");

const Allocator = std.mem.Allocator;
const String = string.String;
const assert = std.debug.assert;

pub const DirIterator = struct {
    alloc: Allocator,
    dir: String,
    prevDirLen: u32,

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

    inline fn hasNext(self: *DirIterator) bool {
        if (self.dir.findLast('/')) |nextSlash| {
            self.dir.chop(nextSlash);

            return true;
        } else {
            return false;
        }
    }

    pub inline fn next(self: *DirIterator) !?struct { packageJson: std.fs.File, dir: []const u8 } {
        while (self.hasNext()) {
            self.prevDirLen = self.dir.len;

            try self.dir.concat(constants.PackageJsonPrefix);

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

// source: https://github.com/XolborGames/FuzzyString/blob/main/src/levenshtein.lua
fn levenshtein_raw(alloc: Allocator, s: []const u8, t: []const u8) !f16 {
    if (s.len == 0 or t.len == 0) {
        return 0;
    }

    var s1 = s;
    var s2 = t;

    if (s.len > t.len) {
        s1 = t;
        s2 = s;
    }

    const hasPrefixBonus = std.mem.startsWith(u8, s2, s1);
    const insertionCost: f16 = if (hasPrefixBonus) 0.33 else 1;

    var v0 = try alloc.alloc(f16, s2.len + 1);
    defer alloc.free(v0);
    var v1 = try alloc.alloc(f16, s2.len + 1);
    defer alloc.free(v1);

    for (0..v0.len) |i| v0[i] = @floatFromInt(i);

    for (0..s1.len) |i| {
        v1[0] = @floatFromInt(i);

        for (0..s2.len) |j| {
            const deletion = v0[j + 1] + 1;
            const insertion = v1[j] + insertionCost;
            const substitution = if (s1[i] == s2[j]) v0[j] else v0[j] + 1;

            v1[j + 1] = @min(deletion, @min(insertion, substitution));
        }

        const temp = v0;
        v0 = v1;
        v1 = temp;
    }

    return v0[s2.len];
}

fn levenshtein(alloc: Allocator, s: []const u8, t: []const u8) !f16 {
    const score = try levenshtein_raw(alloc, s, t);
    const sum: f16 = @floatFromInt(s.len + t.len);
    return 1 - score / sum;
}

pub const Suggestor = struct {
    alloc: Allocator,
    items: *std.ArrayList([]const u8),

    pub fn next(self: Suggestor, query: []const u8) ?[]const u8 {
        if (self.items.items.len == 0) {
            return null;
        }

        if (self.items.items.len == 1) {
            return self.items.pop();
        }

        var largestScore: f16 = -100;
        var matched: usize = 0;

        for (self.items.items, 0..) |item, i| {
            const score = levenshtein(self.alloc, item, query) catch -100;

            if (score > largestScore) {
                largestScore = score;
                matched = i;
            }
        }

        return self.items.swapRemove(matched);
    }
};

pub inline fn concatBinPathsToPath(alloc: Allocator, path: *String, cwd: []const u8) !void {
    var cwdString = try String.init(alloc, cwd);
    defer cwdString.deinit();

    try path.concat(":");
    try path.concat(cwdString.value());
    try path.concat(constants.NodeModulesBinPrefix);

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
            try path.concat(constants.NodeModulesBinPrefix);
        } else {
            cwdString.chop(0);
        }
    }
}

pub inline fn findBestShell() ?[]const u8 {
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

test {
    const testing = std.testing;

    var available = std.ArrayList([]const u8).init(testing.allocator);
    defer available.deinit();
    try available.appendSlice(&[_][]const u8{
        "perf-test",
        "dev",
        "clean",
        "lint",
    });

    var suggestor = try Suggestor.init(testing.allocator, available);
    defer suggestor.deinit();

    const query = "per";

    const next1 = (try suggestor.next(query)).?;

    try testing.expectEqualDeep("perf-test", next1);

    const next2 = (try suggestor.next(query)).?;

    try testing.expectEqualDeep("dev", next2);

    // don't care about rest results (currently)
}

test "Construct path bin dirs" {
    const testing = std.testing;

    var path = try String.init(testing.allocator, "path:path2");
    defer path.deinit();

    try concatBinPathsToPath(testing.allocator, &path, "/dev/nrz");

    try testing.expectEqualStrings("path:path2:/dev/nrz/node_modules/.bin:/dev/node_modules/.bin", path.value());
}
