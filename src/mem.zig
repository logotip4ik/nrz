const std = @import("std");
const builtin = @import("builtin");

pub fn getAllocator() type {
    if (builtin.mode == .ReleaseFast) {
        return struct {
            pub fn allocator() std.mem.Allocator {
                return std.heap.c_allocator;
            }

            pub fn deinit() void {}
        };
    } else {
        return struct {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};

            pub fn allocator() std.mem.Allocator {
                return gpa.allocator();
            }

            pub fn deinit() void {
                _ = gpa.deinit();
            }
        };
    }
}

// https://github.com/ghostty-org/ghostty/blob/main/src/fastmem.zig
pub inline fn move(comptime T: type, dest: []T, source: []const T) void {
    if (comptime builtin.link_libc) {
        _ = memmove(dest.ptr, source.ptr, source.len * @sizeOf(T));
    } else {
        std.mem.copyForwards(T, dest, source);
    }
}

extern "c" fn memmove(*anyopaque, *const anyopaque, usize) *anyopaque;