const std = @import("std");

const Allocator = std.mem.Allocator;

// source: https://github.com/XolborGames/FuzzyString/blob/main/src/levenshtein.lua
fn levenshtein_raw(alloc: Allocator, s: []const u8, t: []const u8) !f16 {
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
    items: std.ArrayList([]const u8),

    pub fn init(alloc: Allocator, list: std.ArrayList([]const u8)) !Suggestor {
        return .{
            .alloc = alloc,
            .items = try list.clone(),
        };
    }

    pub fn deinit(self: Suggestor) void {
        self.items.deinit();
    }

    pub fn next(self: *Suggestor, query: []const u8) !?[]const u8 {
        if (self.items.items.len == 0) {
            return null;
        }

        if (self.items.items.len == 1) {
            return self.items.pop();
        }

        var largestScore: f16 = -100;
        var matched: usize = 0;

        for (self.items.items, 0..) |item, i| {
            const score = try levenshtein(self.alloc, item, query);

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

    const string = "per";

    const next1 = (try suggestor.next(string)).?;

    try testing.expectEqualDeep("perf-test", next1);

    const next2 = (try suggestor.next(string)).?;

    try testing.expectEqualDeep("dev", next2);

    // don't care about rest results (currently)
}
