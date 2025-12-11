const std = @import("std");
const testing = std.testing;

pub fn AdaptiveRadixTree(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        const NodeType = enum {
            leaf,
            node_4,
            node_16,
            node_48,
            node_256,
        };

        const Node = union(NodeType) {
            leaf: LeafNode,
            node_4: Node4,
            node_16: Node16,
            node_48: Node48,
            node_256: Node256,
        };

        const LeafNode = struct {
            key: K,
            value: V,
        };

        root: ?*Node = null,
        size: usize = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            _ = allocator;
            return Self{};
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            _ = self;
            _ = allocator;
        }

        pub fn lookup(self: *Self, allocator: std.mem.Allocator, key: K) ?*Node {
            _ = self;
            _ = allocator;
            _ = key;
        }

        pub fn insert(self: *Self, allocator: std.mem.Allocator, key: K, value: V) !void {
            _ = self;
            _ = allocator;
            _ = key;
            _ = value;
        }

        pub fn delete(self: *Self, allocator: std.mem.Allocator, key: K) ?*Node {
            _ = self;
            _ = allocator;
            _ = key;
        }
    };
}

test "init/deinit" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree([]const u8, u32).init(allocator);
    defer art.deinit(allocator);
}
