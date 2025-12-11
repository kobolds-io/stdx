const std = @import("std");
const testing = std.testing;

pub fn AdaptiveRadixTree(comptime K: type, comptime V: type) type {
    _ = K;
    _ = V;
    return struct {
        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            _ = allocator;
            return Self{};
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            _ = self;
            _ = allocator;
        }
    };
}

test "init/deinit" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree([]const u8, u32).init(allocator);
    defer art.deinit(allocator);
}
