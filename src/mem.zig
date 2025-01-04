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
