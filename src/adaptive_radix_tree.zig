const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const MAX_PREFIX: usize = 8; // usually 8 or 10

pub fn AdaptiveRadixTree(comptime V: type) type {
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
            leaf: Leaf,
            node_4: Node4,
            node_16: Node16,
            node_48: Node48,
            node_256: Node256,
        };

        const Leaf = struct {
            key: []const u8,
            value: V,
        };

        /// Small node: Up to 4 children with sorted keys
        const Node4 = struct {
            prefix_len: u8,
            prefix: [MAX_PREFIX]u8,
            num_children: u8,
            keys: [4]u8,
            children: [4]?*Node,
        };

        /// Medium node: up to 16 children with sorted keys
        const Node16 = struct {
            prefix_len: u8,
            prefix: [MAX_PREFIX]u8,
            num_children: u8,
            keys: [16]u8,
            children: [16]?*Node,
        };

        /// Medium node: uses a dense index array for fast lookup
        pub const Node48 = struct {
            prefix_len: u8,
            prefix: [MAX_PREFIX]u8,
            num_children: u8,
            index: [256]u8, // 0xFF = empty, else = index into children[]
            keys: [256]u8, // 0xFF = empty, else = index into children[]
            children: [48]?*Node,
        };

        pub const Node256 = struct {
            prefix_len: u8,
            prefix: [MAX_PREFIX]u8,
            num_children: u8,
            children: [256]?*Node,
        };

        root: ?*Node = null,
        size: usize = 0,

        pub fn init(_: std.mem.Allocator) Self {
            return Self{
                .size = 0,
                .root = null,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            Self.destroyNode(allocator, self.root);
            self.* = .{};
        }

        pub fn lookup(self: *Self, allocator: std.mem.Allocator, key: []const u8) ?*Node {
            _ = self;
            _ = allocator;
            _ = key;
        }

        pub fn delete(self: *Self, allocator: std.mem.Allocator, key: []const u8) ?*Node {
            _ = self;
            _ = allocator;
            _ = key;
        }

        fn allocLeaf(
            allocator: std.mem.Allocator,
            key: []const u8,
            value: V,
        ) !*Node {
            const leaf = try allocator.create(Node);
            leaf.* = Node{
                .leaf = .{ .key = key, .value = value },
            };

            return leaf;
        }

        fn allocNode4(allocator: std.mem.Allocator) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{
                .node_4 = .{
                    .prefix_len = 0,
                    .prefix = undefined,
                    .num_children = 0,
                    .keys = .{0} ** 4,
                    .children = .{null} ** 4,
                },
            };

            return node;
        }

        pub fn insert(self: *Self, allocator: std.mem.Allocator, key: []const u8, value: V) !void {
            if (self.root == null) {
                // tree is empty, just create a leaf
                self.root = try Self.allocLeaf(allocator, key, value);
                self.size += 1;

                return;
            }

            // otherwise insert a node
            return self.insertAt(allocator, self.root.?, key, value, 0);
        }

        fn insertAt(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            key: []const u8,
            value: V,
            depth: usize,
        ) !void {
            switch (node_ptr.*) {
                .leaf => |*old_leaf| {
                    // if this key matches the existing leaf's key then they are the same
                    // and we should just do a simple override of the value
                    if (std.mem.eql(u8, old_leaf.key, key)) {
                        old_leaf.value = value;
                        return;
                    }

                    var i: usize = depth;
                    // find the first differing byte in the keys of `old_leaf` and `key`
                    while (i < old_leaf.key.len and i < key.len and old_leaf.key[i] == key[i]) : (i += 1) {}

                    const old_byte: u8 = if (i < old_leaf.key.len) old_leaf.key[i] else 0;
                    const new_byte: u8 = if (i < key.len) key[i] else 0;

                    // create a copy of the `old_leaf` to make sure we don't lose that information
                    const old_node_leaf_copy = try allocator.create(Node);
                    old_node_leaf_copy.* = Node{ .leaf = old_leaf.* };

                    // create a new leaf for the new key/value pair
                    const new_leaf = try allocator.create(Node);
                    new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                    // create a Node4 in place
                    node_ptr.* = Node{
                        .node_4 = Node4{
                            .prefix_len = @intCast(i - depth),
                            .prefix = undefined,
                            .num_children = 2,
                            .keys = [_]u8{0} ** 4,
                            .children = [_]?*Node{null} ** 4,
                        },
                    };

                    // copy the prefix into the new larger Node4
                    if (node_ptr.node_4.prefix_len > 0) {
                        @memcpy(
                            node_ptr.node_4.prefix[0..node_ptr.node_4.prefix_len],
                            old_node_leaf_copy.leaf.key[depth .. depth + node_ptr.node_4.prefix_len],
                        );
                    }

                    // insert the leaves in sorted order
                    if (old_byte < new_byte) {
                        node_ptr.node_4.keys[0] = old_byte;
                        node_ptr.node_4.children[0] = old_node_leaf_copy;
                        node_ptr.node_4.keys[1] = new_byte;
                        node_ptr.node_4.children[1] = new_leaf;
                    } else {
                        node_ptr.node_4.keys[0] = new_byte;
                        node_ptr.node_4.children[0] = new_leaf;
                        node_ptr.node_4.keys[1] = old_byte;
                        node_ptr.node_4.children[1] = old_node_leaf_copy;
                    }

                    self.size += 1;
                    return;
                },
                .node_4 => |*n4| {
                    // check the prefix
                    const max_cmp = @min(n4.prefix_len, key.len - depth);
                    var i: usize = 0;
                    while (i < max_cmp and n4.prefix[i] == key[depth + i]) : (i += 1) {}

                    // ---------------- prefixes mismatch -> split node ----------------
                    if (i < n4.prefix_len) {
                        const old_byte = n4.prefix[i];
                        const new_byte: u8 = if (depth + i < key.len) key[depth + i] else 0;

                        // new parent node
                        const parent = try allocator.create(Node);
                        parent.* = Node{
                            .node_4 = .{
                                .prefix_len = @intCast(i),
                                .prefix = undefined,
                                .num_children = 0,
                                .keys = [_]u8{0} ** 4,
                                .children = [_]?*Node{null} ** 4,
                            },
                        };
                        @memcpy(parent.node_4.prefix[0..i], n4.prefix[0..i]);

                        // Clone old node
                        const old_child = try allocator.create(Node);
                        old_child.* = node_ptr.*;

                        // fix old child's prefix
                        const skip = i + 1;
                        old_child.node_4.prefix_len -= @intCast(skip);
                        @memmove(
                            old_child.node_4.prefix[0..old_child.node_4.prefix_len],
                            old_child.node_4.prefix[skip .. skip + old_child.node_4.prefix_len],
                        );

                        // create new leaf
                        const new_leaf = try allocator.create(Node);
                        new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                        // insert children
                        parent.node_4.keys[0] = old_byte;
                        parent.node_4.children[0] = old_child;
                        parent.node_4.keys[1] = new_byte;
                        parent.node_4.children[1] = new_leaf;
                        parent.node_4.num_children = 2;

                        // replace node in-place
                        node_ptr.* = parent.*;
                        allocator.destroy(parent);

                        self.size += 1;
                        return;
                    }

                    // ---------------- prefixes match ----------------
                    const next_depth = depth + n4.prefix_len;
                    const b: u8 = if (next_depth < key.len) key[next_depth] else 0;

                    // search for existing child
                    i = 0;
                    while (i < n4.num_children) : (i += 1) {
                        if (n4.keys[i] == b) {
                            return self.insertAt(
                                allocator,
                                n4.children[i].?,
                                key,
                                value,
                                next_depth + 1,
                            );
                        }
                    }

                    // ---------------- insert a new leaf (without growing) ----------------
                    if (n4.num_children < 4) {
                        const new_leaf = try allocator.create(Node);
                        new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                        n4.keys[n4.num_children] = b;
                        n4.children[n4.num_children] = new_leaf;
                        n4.num_children += 1;

                        self.size += 1;
                        return;
                    }

                    // ---- Node4 full, grow to Node16 ----
                    const new_node = try allocator.create(Node);
                    new_node.* = Node{
                        .node_16 = .{
                            .prefix_len = n4.prefix_len,
                            .prefix = n4.prefix,
                            .num_children = n4.num_children,
                            .keys = [_]u8{0} ** 16,
                            .children = [_]?*Node{null} ** 16,
                        },
                    };

                    var n16 = &new_node.node_16;

                    // copy the keys and children from the Node4 to the Node16
                    var j: usize = 0;
                    while (j < n4.num_children) : (j += 1) {
                        n16.keys[j] = n4.keys[j];
                        n16.children[j] = n4.children[j];
                    }

                    // find the sorted position of where the new_leaf should be inserted
                    const insert_pos = blk: {
                        var k: usize = 0;
                        while (k < n16.num_children and n16.keys[k] < b) : (k += 1) {}
                        break :blk k;
                    };

                    // shift right to make room
                    @memmove(
                        n16.keys[insert_pos + 1 .. n16.num_children + 1],
                        n16.keys[insert_pos..n16.num_children],
                    );
                    @memmove(
                        n16.children[insert_pos + 1 .. n16.num_children + 1],
                        n16.children[insert_pos..n16.num_children],
                    );

                    // create the new leaf
                    const new_leaf = try allocator.create(Node);
                    new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                    // insert the new leaf
                    n16.keys[insert_pos] = b;
                    n16.children[insert_pos] = new_leaf;
                    n16.num_children += 1;

                    // replace node_ptr in-place
                    node_ptr.* = new_node.*;
                    allocator.destroy(new_node);

                    self.size += 1;
                    return;
                },

                else => unreachable,
            }
        }

        fn destroyNode(allocator: std.mem.Allocator, node_opt: ?*Node) void {
            if (node_opt == null) return;

            const node: *Node = node_opt.?;

            switch (node.*) {
                .leaf => allocator.destroy(node),
                .node_4 => {
                    for (node.node_4.children) |child| {
                        destroyNode(allocator, child);
                    }
                    allocator.destroy(node);
                },
                .node_16 => {
                    for (node.node_16.children) |child| {
                        destroyNode(allocator, child);
                    }
                    allocator.destroy(node);
                },
                .node_48 => {
                    // keys[i] = idx+1 of children[]
                    var i: usize = 0;
                    while (i < 256) : (i += 1) {
                        const k = node.node_48.keys[i];
                        if (k != 0) {
                            const idx = @as(usize, k) - 1;
                            destroyNode(allocator, node.node_48.children[idx]);
                        }
                    }

                    allocator.destroy(node);
                },
                .node_256 => {
                    for (node.node_256.children) |child| {
                        destroyNode(allocator, child);
                    }
                    allocator.destroy(node);
                },
            }
        }

        pub fn prettyPrint(self: *Self, allocator: std.mem.Allocator) !void {
            if (self.root) |r| {
                try Self.printNodePretty(r, allocator, "", true);
            } else {
                std.debug.print("(empty ART)\n", .{});
            }
        }

        fn printNodePretty(node: *Node, allocator: std.mem.Allocator, prefix: []const u8, is_last: bool) !void {
            const branch = if (is_last) "└── " else "├── ";
            const child_prefix = if (is_last) "    " else "│   ";

            // print current node
            std.debug.print("{s}{s}", .{ prefix, branch });

            switch (node.*) {
                .leaf => |leaf| {
                    std.debug.print("Leaf(key={any}, value={any})\n", .{ leaf.key, leaf.value });
                },

                .node_4 => |n| {
                    std.debug.print("Node4(prefix_len={}, children={})\n", .{ n.prefix_len, n.num_children });

                    // allocate prefix extension
                    const next_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{
                        prefix,
                        child_prefix,
                    });
                    defer allocator.free(next_prefix); // ← FREE IT

                    var i: usize = 0;
                    while (i < n.num_children) : (i += 1) {
                        const last_child = (i + 1 == n.num_children);

                        std.debug.print("{s}{s}{x}\n", .{ next_prefix, if (last_child) "└── key " else "├── key ", n.keys[i] });

                        if (n.children[i]) |c| {
                            try printNodePretty(c, allocator, next_prefix, last_child);
                        }
                    }
                },

                .node_16 => |n| {
                    std.debug.print("Node16(prefix_len={}, children={})\n", .{ n.prefix_len, n.num_children });

                    const next_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{
                        prefix,
                        child_prefix,
                    });
                    defer allocator.free(next_prefix);

                    var i: usize = 0;
                    while (i < n.num_children) : (i += 1) {
                        const last_child = (i + 1 == n.num_children);

                        std.debug.print("{s}{s}{x}\n", .{ next_prefix, if (last_child) "└── key " else "├── key ", n.keys[i] });

                        if (n.children[i]) |c| {
                            try printNodePretty(c, allocator, next_prefix, last_child);
                        }
                    }
                },

                .node_48 => |n| {
                    std.debug.print("Node48(prefix_len={}, children={})\n", .{ n.prefix_len, n.num_children });

                    const next_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{
                        prefix,
                        child_prefix,
                    });
                    defer allocator.free(next_prefix);

                    var count: usize = 0;
                    var b: usize = 0;
                    while (b < 256) : (b += 1) {
                        if (n.keys[b] != 0) {
                            const last_child = (count + 1 == n.num_children);
                            const child_index = @as(usize, n.keys[b]) - 1;

                            std.debug.print("{s}{s}{x}\n", .{ next_prefix, if (last_child) "└── key " else "├── key ", b });

                            if (n.children[child_index]) |c| {
                                try printNodePretty(c, allocator, next_prefix, last_child);
                            }

                            count += 1;
                        }
                    }
                },

                .node_256 => |n| {
                    std.debug.print("Node256(prefix_len={}, children={})\n", .{ n.prefix_len, n.num_children });

                    const next_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{
                        prefix,
                        child_prefix,
                    });
                    defer allocator.free(next_prefix);

                    var count: usize = 0;
                    var b: usize = 0;
                    while (b < 256) : (b += 1) {
                        if (n.children[b]) |c| {
                            const last_child = (count + 1 == n.num_children);

                            std.debug.print("{s}{s}{x}\n", .{ next_prefix, if (last_child) "└── key " else "├── key ", b });

                            try printNodePretty(c, allocator, next_prefix, last_child);

                            count += 1;
                        }
                    }
                },
            }
        }
    };
}

test "init/deinit" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);
}

test "insert into a an empty tree" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree([]const u8).init(allocator);
    defer art.deinit(allocator);

    try testing.expectEqual(0, art.size);

    const k = "hello";
    const v = "world";

    try art.insert(allocator, k, v);

    try testing.expectEqual(1, art.size);
    try testing.expect(std.mem.eql(u8, v, art.root.?.leaf.value));
}

test "upgrade root node from leaf to node_4 on second insert" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    try testing.expectEqual(0, art.size);

    const k1 = "hello";
    const v1 = 1;

    try art.insert(allocator, k1, v1);

    const k2 = "hello_";
    const v2 = 2;
    try art.insert(allocator, k2, v2);

    try testing.expectEqual(2, art.size);
    try testing.expectEqual(2, art.root.?.node_4.num_children);

    try testing.expectEqualStrings(k1, art.root.?.node_4.children[0].?.leaf.key);
    try testing.expectEqual(v1, art.root.?.node_4.children[0].?.leaf.value);

    try testing.expectEqualStrings(k2, art.root.?.node_4.children[1].?.leaf.key);
    try testing.expectEqual(v2, art.root.?.node_4.children[1].?.leaf.value);
}

test "inserting 3 items into the tree does not trigger a Node4 to Node16 upgrade" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    try testing.expectEqual(0, art.size);

    const k1 = "h";
    const v1 = 1;

    try art.insert(allocator, k1, v1);

    const k2 = "hello";
    const v2 = 2;
    try art.insert(allocator, k2, v2);

    const k3 = "help";
    const v3 = 3;
    try art.insert(allocator, k3, v3);

    try testing.expectEqual(3, art.size);
    try testing.expectEqual(2, art.root.?.node_4.num_children);

    // try art.prettyPrint(allocator);
}

test "node4 prefix mismatch split" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    // These two keys share "ab", then diverge at index 2
    // This guarantees a Node4 prefix mismatch split
    try art.insert(allocator, "ab", 1);
    try art.insert(allocator, "abc", 2);
    try art.insert(allocator, "ad", 3);

    // try art.prettyPrint(allocator);

    try testing.expectEqual(3, art.size);

    // Root must be Node4 after split
    const root = art.root orelse return error.TestFailed;

    // there are 2 kiddos
    try testing.expectEqual(2, root.node_4.num_children);
    try testing.expectEqual(1, root.node_4.prefix_len);
    try testing.expectEqual('a', root.node_4.prefix[0]);

    try testing.expectEqual(2, root.node_4.num_children);

    const child_node_4 = root.node_4.children[0].?;

    try testing.expectEqual(0, child_node_4.node_4.prefix_len);

    try testing.expectEqualStrings("ab", child_node_4.node_4.children[0].?.leaf.key);
    try testing.expectEqualStrings("abc", child_node_4.node_4.children[1].?.leaf.key);
    try testing.expectEqualStrings("ad", root.node_4.children[1].?.leaf.key);
}

test "node4 grows to node16" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    // These two keys share "ab", then diverge at index 2
    // This guarantees a Node4 prefix mismatch split
    try art.insert(allocator, "a0", 0);
    try art.insert(allocator, "a1", 1);
    try art.insert(allocator, "a2", 2);
    try art.insert(allocator, "a3", 4);
    try art.insert(allocator, "a4", 4);

    // try art.prettyPrint(allocator);

    try testing.expectEqual(5, art.size);

    const root = art.root orelse return error.TestFailed;

    try testing.expectEqual(5, root.node_16.num_children);
}
