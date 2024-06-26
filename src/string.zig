const std = @import("std");
const Allocator = std.mem.Allocator;

const STRING_INIT_LEN = 128;

pub const String = struct {
    alloc: Allocator,
    buf: []u8,
    len: usize,

    pub fn init(alloc: Allocator, string: []const u8) !String {
        var bufSize: usize = STRING_INIT_LEN;

        while (string.len > bufSize) {
            bufSize *= 2;
        }

        const buf = try alloc.alloc(u8, bufSize);

        std.mem.copyForwards(u8, buf, string[0..string.len]);
        buf[string.len] = 0;

        return .{
            .alloc = alloc,
            .buf = buf,
            .len = string.len,
        };
    }

    pub fn deinit(self: String) void {
        self.alloc.free(self.buf);
    }

    pub fn value(self: String) [:0]const u8 {
        return self.buf[0..self.len :0];
    }

    fn allocate(self: *String) !void {
        self.*.buf = try self.alloc.realloc(self.*.buf, self.buf.len * 2);
    }

    pub fn concat(self: *String, string: [:0]const u8) !void {
        while (self.len + string.len + 1 > self.buf.len) {
            try self.allocate();
        }

        std.mem.copyForwards(u8, self.*.buf[self.len..self.buf.len], string[0 .. string.len + 1]);
        self.*.len += string.len;
        self.*.buf[self.len] = 0;
    }

    pub fn findLast(self: String, search: u8) ?usize {
        var idx = self.len;
        const string = self.value();

        while (idx > 0) {
            idx -= 1;

            if (string[idx] == search) {
                return idx;
            }
        }

        return null;
    }

    pub fn copy(self: String) !String {
        return String.init(self.alloc, self.value());
    }

    pub const IterReverseChunk = struct {
        separator: u8,
        currentString: String,
        end: ?usize,

        pub fn init(string: String, separator: u8) !IterReverseChunk {
            return .{
                .currentString = try string.copy(),
                .end = string.len,
                .separator = separator,
            };
        }

        pub fn deinit(self: IterReverseChunk) void {
            self.currentString.deinit();
        }

        pub fn next(self: *IterReverseChunk) ?[:0]const u8 {
            if (self.end == null) {
                return null;
            }

            const chunkStart = self.currentString.findLast(self.separator);

            if (chunkStart == null) {
                const stringSlice = self.currentString.buf[0..self.end.? :0];

                self.*.end = chunkStart;

                return stringSlice;
            }

            self.*.currentString.buf[chunkStart.?] = 0;
            self.*.currentString.len = chunkStart.?;

            const stringSlice = self.currentString.buf[chunkStart.? + 1 .. self.end.? :0];

            self.*.end = chunkStart;

            return stringSlice;
        }
    };

    pub fn chunkReversed(self: String, separator: u8) !IterReverseChunk {
        return try IterReverseChunk.init(try self.copy(), separator);
    }
};

test "Correctly initializes" {
    const testing = std.testing;

    const initString = "help me";
    var string = try String.init(testing.allocator, initString);
    defer string.deinit();

    try testing.expectEqual(string.len, initString.len);
}

test "Returns correct value" {
    const testing = std.testing;

    const initString = "help me";
    var string = try String.init(testing.allocator, initString);
    defer string.deinit();

    try testing.expectEqualDeep(initString, string.value());
    try testing.expectEqual(string.value()[initString.len], 0);
    try testing.expectEqual(initString[initString.len], string.value()[initString.len]);
}

test "Can concat strings" {
    const testing = std.testing;

    const initString = "help me";
    const string2 = " with this";

    var string = try String.init(testing.allocator, initString);
    defer string.deinit();

    try testing.expectEqualDeep(initString, string.value());

    try string.concat(string2);

    try testing.expectEqualDeep(initString ++ string2, string.value());
}

test "multiple strings" {
    const testing = std.testing;

    const initString1 = "help me";
    const initString2 = "with this";

    var string1 = try String.init(testing.allocator, initString1);
    defer string1.deinit();

    var string2 = try String.init(testing.allocator, initString2);
    defer string2.deinit();

    try testing.expectEqualDeep(initString1, string1.value());
    try testing.expectEqualDeep(initString2, string2.value());
}

test "Find last char" {
    const testing = std.testing;

    const initString = "ihhehhhhhh";

    var string = try String.init(testing.allocator, initString);
    defer string.deinit();

    const charIdx = string.findLast('i').?;
    try testing.expectEqual(0, charIdx);

    const char2Idx = string.findLast('a');
    try testing.expectEqual(null, char2Idx);

    const char3Idx = string.findLast('h').?;
    try testing.expectEqual(9, char3Idx);
}

test "Reversed chunk" {
    const testing = std.testing;

    const initString = "something/like/this";

    var string = try String.init(testing.allocator, initString);
    defer string.deinit();

    var iter = try String.IterReverseChunk.init(string, '/');
    defer iter.deinit();

    const chunk1 = iter.next();
    try testing.expectEqualDeep("this", chunk1.?);

    const chunk2 = iter.next();
    try testing.expectEqualDeep("like", chunk2.?);

    const chunk3 = iter.next();
    try testing.expectEqualDeep("something", chunk3.?);

    const chunk4 = iter.next();
    try testing.expectEqualDeep(null, chunk4);

    try testing.expectEqualDeep(initString, string.value());
}
