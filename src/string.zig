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

        std.mem.copyForwards(u8, buf, string);

        return .{
            .alloc = alloc,
            .buf = buf,
            .len = string.len,
        };
    }

    pub inline fn deinit(self: String) void {
        self.alloc.free(self.buf);
    }

    pub inline fn value(self: String) []const u8 {
        return self.buf[0..self.len];
    }

    inline fn allocate(self: *String) !void {
        self.buf = try self.alloc.realloc(self.buf, self.buf.len * 2);
    }

    pub fn concat(self: *String, string: []const u8) !void {
        while (self.len + string.len + 1 > self.buf.len) {
            try self.allocate();
        }

        std.mem.copyForwards(u8, self.buf[self.len..self.buf.len], string);
        self.len += string.len;
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

    pub inline fn copy(self: String) !String {
        return String.init(self.alloc, self.value());
    }

    pub inline fn chop(self: *String, newEnd: usize) void {
        std.debug.assert(newEnd >= 0);

        self.len = newEnd;
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

    try testing.expectEqualStrings(initString, string.value());
}

test "Can concat strings" {
    const testing = std.testing;

    const initString = "help me";
    const string2 = " with this";

    var string = try String.init(testing.allocator, initString);
    defer string.deinit();

    try testing.expectEqualStrings(initString, string.value());

    try string.concat(string2);

    try testing.expectEqualStrings(initString ++ string2, string.value());
}

test "multiple strings" {
    const testing = std.testing;

    const initString1 = "help me";
    const initString2 = "with this";

    var string1 = try String.init(testing.allocator, initString1);
    defer string1.deinit();

    var string2 = try String.init(testing.allocator, initString2);
    defer string2.deinit();

    try testing.expectEqualStrings(initString1, string1.value());
    try testing.expectEqualStrings(initString2, string2.value());
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
