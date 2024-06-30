const std = @import("std");
const fts = @cImport({
    @cInclude("fuzzy.c");
});

const Allocator = std.mem.Allocator;

// source: https://github.com/XolborGames/FuzzyString/blob/main/src/levenshtein.lua
fn levenshtein_raw(alloc: Allocator, s: []const u8, t: []const u8) !u8 {
    var s1 = s;
    var s2 = t;

    if (s.len > t.len) {
        s1 = t;
        s2 = s;
    }

    var v0 = try alloc.alloc(u8, s2.len + 1);
    defer alloc.free(v0);
    var v1 = try alloc.alloc(u8, s2.len + 1);
    defer alloc.free(v1);

    for (0..v0.len) |i| v0[i] = @truncate(i);

    for (0..s1.len) |i| {
        v1[0] = @truncate(i);

        for (0..s2.len) |j| {
            const deletionCost = v0[j + 1] + 1;
            const insertionCost = v1[j] + 1;
            const substitutionCost = if (s1[i] == s2[j]) v0[j] else v0[j] + 1;

            v1[j + 1] = @min(deletionCost, @min(insertionCost, substitutionCost));
        }

        const temp = v0;
        v0 = v1;
        v1 = temp;
    }

    return v0[s2.len];
}

fn levenshtein(alloc: Allocator, s: []const u8, t: []const u8) !f16 {
    const score: f16 = @floatFromInt(try levenshtein_raw(alloc, s, t));
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
