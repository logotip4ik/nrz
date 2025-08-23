const std = @import("std");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const DirIterator = struct {
    dir: []const u8,
    runFirstIter: bool,

    pub fn init(dir: []const u8) DirIterator {
        return .{
            .dir = dir,
            .runFirstIter = false,
        };
    }

    pub fn next(self: *DirIterator) ?[]const u8 {
        if (self.runFirstIter) {
            // includes leading slash
            const dirname = std.fs.path.dirname(self.dir) orelse return null;

            if (dirname.len == 1) {
                return null;
            }

            self.dir = self.dir[0..dirname.len];
        }

        self.runFirstIter = true;

        return if (self.dir.len == 0) null else self.dir;
    }
};

test {
    const testing = std.testing;
    const a = "/dev/home?/something";

    var iter = DirIterator.init(a);

    try testing.expectEqualStrings("/dev/home?/something", iter.next().?);
    try testing.expectEqualStrings("/dev/home?", iter.next().?);
    try testing.expectEqualStrings("/dev", iter.next().?);
    try testing.expect(iter.next() == null);
    try testing.expect(iter.next() == null);
}

pub fn levenshteinCompare(s: *const []const u8, t: *const []const u8) f16 {
    if (s.len == 0 or t.len == 0) {
        return 0;
    }

    var s1 = s;
    var s2 = t;

    if (s.len > t.len) {
        s1 = t;
        s2 = s;
    }

    const hasPrefixBonus = std.mem.startsWith(u8, s2.*, s1.*);
    const insertionCost: f16 = if (hasPrefixBonus) 0.33 else 1;

    @setFloatMode(.optimized);
    var b1: [1024]f16 = undefined;
    var b2: [1024]f16 = undefined;

    var v0 = b1[0 .. s2.len + 1];
    var v1 = b2[0 .. s2.len + 1];

    for (0..v0.len) |i| v0[i] = @floatFromInt(i);

    for (0..s1.len) |i| {
        v1[0] = @floatFromInt(i);

        for (0..s2.len) |j| {
            const deletion = v0[j + 1] + 1;
            const insertion = v1[j] + insertionCost;
            const substitution = if (s1.*[i] == s2.*[j]) v0[j] else v0[j] + 1;

            v1[j + 1] = @min(deletion, @min(insertion, substitution));
        }

        const temp = v0;
        v0 = v1;
        v1 = temp;
    }

    return v0[s2.len];
}

pub const Suggestor = struct {
    items: *std.array_list.Managed(*[]const u8),

    pub fn next(self: Suggestor, query: []const u8) ?*[]const u8 {
        if (self.items.items.len == 0) {
            return null;
        }

        if (self.items.items.len == 1) {
            return self.items.pop();
        }

        var largestScore: f16 = -100;
        var matched: usize = 0;

        for (self.items.items, 0..) |item, i| {
            @setFloatMode(.optimized);
            const raw_score = levenshteinCompare(item, &query);
            const sum: f16 = @floatFromInt(item.len + query.len);
            const score = 1 - raw_score / sum;

            if (score > largestScore) {
                largestScore = score;
                matched = i;
            }
        }

        return self.items.swapRemove(matched);
    }
};

test {
    const testing = std.testing;

    var available = std.array_list.Managed(*[]const u8).init(testing.allocator);
    defer available.deinit();

    const strings = [_][]const u8{
        "perf-test",
        "dev",
        "clean",
        "lint",
    };

    available.append(@constCast(&strings[0])) catch unreachable;
    available.append(@constCast(&strings[1])) catch unreachable;
    available.append(@constCast(&strings[2])) catch unreachable;
    available.append(@constCast(&strings[3])) catch unreachable;

    var suggestor = Suggestor{
        .items = &available,
    };

    const query = "per";

    const next1 = suggestor.next(query).?;

    try testing.expectEqualStrings("perf-test", next1.*);

    const next2 = suggestor.next(query).?;

    try testing.expectEqualStrings("dev", next2.*);

    // don't care about rest results (currently)
}

pub fn concatBinPathsToPATH(alloc: Allocator, path: []const u8, cwd: []const u8) []const u8 {
    var newPath = path;

    var buf1: [4096]u8 = undefined;
    var buf2: [4096]u8 = undefined;

    var cwdIter = DirIterator.init(cwd);
    var i: u8 = 0;
    while (cwdIter.next()) |chunk| : (i += 1) {
        const buf = if (i % 2 == 0) &buf1 else &buf2;

        newPath = std.fmt.bufPrint(buf, "{s}{c}{s}{c}node_modules{c}.bin", .{
            newPath,
            std.fs.path.delimiter,
            chunk,
            std.fs.path.sep,
            std.fs.path.sep,
        }) catch @panic("if you this, open issue in logotip4ik/nrz with code 001");
    }

    return alloc.dupe(u8, newPath) catch unreachable;
}

test "Construct path bin dirs" {
    const testing = std.testing;
    const path = "path:path2";

    const newpath = concatBinPathsToPATH(testing.allocator, path, "/dev/nrz");
    defer testing.allocator.free(newpath);

    try testing.expectEqualStrings("path:path2:/dev/nrz/node_modules/.bin:/dev/node_modules/.bin", newpath);
}

pub inline fn findBestShell() ?[]const u8 {
    const shells = [_][]const u8{
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

const ReadJsonError = error{ FileRead, InvalidJson, InvalidJsonWithFullBuffer };
pub fn readJson(comptime T: type, alloc: Allocator, file: std.fs.File, buf: []u8) ReadJsonError!std.json.Parsed(T) {
    const contentsLength = file.readAll(buf) catch return error.FileRead;
    const contents = buf[0..contentsLength];

    return std.json.parseFromSlice(
        T,
        alloc,
        contents,
        .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_if_needed,
            .duplicate_field_behavior = .use_last,
            .max_value_len = std.math.maxInt(u16),
        },
    ) catch {
        return if (contentsLength == buf.len)
            error.InvalidJsonWithFullBuffer
        else
            error.InvalidJson;
    };
}

pub fn concatStringArray(alloc: Allocator, strings: []const []const u8, comptime scalar: u8) !?[]const u8 {
    if (strings.len == 0) {
        return null;
    }

    var stringLen: u8 = @intCast(strings.len - 1); // accounts for number of scalars

    for (strings) |string| {
        stringLen += @intCast(string.len);
    }

    const concatenated = try alloc.alloc(u8, stringLen);
    var wrote: u8 = 0;

    for (strings, 0..) |string, i| {
        @memcpy(concatenated[wrote .. wrote + string.len], string);
        wrote += @as(u8, @intCast(string.len)) + 1;

        if (i != strings.len - 1) {
            concatenated[wrote - 1] = scalar;
        }
    }

    return concatenated;
}

test {
    const testing = std.testing;

    const concatenated = try concatStringArray(
        testing.allocator,
        &[_][]const u8{ "hello", "world" },
        ' ',
    );
    defer testing.allocator.free(concatenated);

    try testing.expectEqualStrings("hello world", concatenated);
}
