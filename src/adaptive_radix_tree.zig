const std = @import("std");
const testing = std.testing;

const MAX_PREFIX: usize = 8; // usually 8 or 10

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

        /// Small node: Up to 4 children with sorted keys
        const Node4 = struct {
            prefix_len: u8,
            prefix: [MAX_PREFIX]u8,
            num_children: u8,
            keys: [4]u8,
            children: [4]?*Node,
        };

        /// Medium node: up to 16 children. Keys are stored as signed chars for faster comparisons
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
            index: [256]u8, // 0xFF = empty
            children: [48]?*Node,
            keys: [256]u8, // 0 = unused, else = index+1 into children[]
        };

        pub const Node256 = struct {
            prefix_len: u8,
            prefix: [MAX_PREFIX]u8,
            num_children: u16,
            children: [256]?*Node,
        };

        root: ?*Node = null,
        size: usize = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .size = 0,
                .root = null,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            Self.destroyNode(allocator, self.root);
            self.root = null;
            self.size = 0;
        }

        pub fn lookup(self: *Self, allocator: std.mem.Allocator, key: K) ?*Node {
            _ = self;
            _ = allocator;
            _ = key;
        }

        pub fn insert(self: *Self, allocator: std.mem.Allocator, key: K, value: V) !void {
            if (self.root == null) {
                // tree is empty, just create a leaf
                self.root = try Self.allocLeaf(allocator, key, value);
                self.size += 1;

                return;
            }

            // otherwise insert a node
            return self.insertAt(allocator, self.root.?, key, value, 0);
        }

        pub fn delete(self: *Self, allocator: std.mem.Allocator, key: K) ?*Node {
            _ = self;
            _ = allocator;
            _ = key;
        }

        fn allocLeaf(
            allocator: std.mem.Allocator,
            key: K,
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

        fn insertAt(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            key: K,
            value: V,
            depth: usize,
        ) !void {
            switch (node_ptr.*) {
                // .leaf => |*leaf| {
                // // if exact match, overwrite the leaf
                // if (std.mem.eql(u8, leaf.key, key)) {
                //     leaf.value = value;
                //     return;
                // }

                // // leaf key differs and must create a Node4 above
                // const new_node4 = try Self.allocNode4(allocator);
                // const first_key_byte = leaf.key[depth];
                // const second_key_byte = key[depth];

                // // Insert old leaf into Node4
                // var n4 = &new_node4.node_4;

                // n4.keys[0] = first_key_byte;
                // n4.children[0] = node_ptr; // old leaf
                // n4.num_children = 1;

                // // Insert new leaf
                // const new_leaf = try Self.allocLeaf(allocator, key, value);

                // if (second_key_byte < first_key_byte) {
                //     // shift existing child to index 1
                //     n4.keys[1] = first_key_byte;
                //     n4.children[1] = node_ptr;
                //     n4.keys[0] = second_key_byte;
                //     n4.children[0] = new_leaf;
                // } else {
                //     n4.keys[1] = second_key_byte;
                //     n4.children[1] = new_leaf;
                // }

                // n4.num_children = 2;

                // // Replace node_ptr with the new Node4
                // node_ptr.* = new_node4.*;
                // self.size += 1;
                // return;
                // },

                .leaf => |old_leaf| {
                    const new_leaf = try Self.allocLeaf(allocator, key, value);
                    // new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                    // create new Node4
                    const node4 = try Self.allocNode4(allocator);
                    // node4.* = .{
                    //     .node_4 = .{
                    //         .prefix_len = 0,
                    //         .prefix = undefined,
                    //         .num_children = 0,
                    //         .keys = [_]u8{0} ** 4,
                    //         .children = [_]?*Node{null} ** 4,
                    //     },
                    // };

                    // Find first differing byte
                    var idx: usize = 0;
                    while (idx < old_leaf.key.len and idx < key.len and old_leaf.key[idx] == key[idx]) {
                        idx += 1;
                    }
                    // If one key ended, treat missing byte as 0
                    const old_k: u8 = if (idx < old_leaf.key.len) old_leaf.key[idx] else 0;
                    const new_k: u8 = if (idx < key.len) key[idx] else 0;

                    node4.node_4.keys[0] = old_k;
                    node4.node_4.children[0] = self.root;

                    node4.node_4.keys[1] = new_k;
                    node4.node_4.children[1] = new_leaf;

                    node4.node_4.num_children = 2;

                    self.root = node4;
                    self.size += 1;
                },
                .node_4 => |*n4| {
                    const b = key[depth];

                    // Search for existing child
                    var i: usize = 0;
                    while (i < n4.num_children) : (i += 1) {
                        if (n4.keys[i] == b) {
                            // descend
                            return self.insertAt(allocator, n4.children[i].?, key, value, depth + 1);
                        }
                    }

                    // Need to insert new child
                    if (n4.num_children < 4) {
                        const new_leaf = try Self.allocLeaf(allocator, key, value);

                        n4.keys[n4.num_children] = b;
                        n4.children[n4.num_children] = new_leaf;
                        n4.num_children += 1;
                        self.size += 1;
                        return;
                    }

                    // TODO: uprade Node4 to Node16
                    @panic("Node4 full: need Node16 growth");
                },

                else => @panic("Implement other node types next"),
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

    var art = AdaptiveRadixTree([]const u8, u32).init(allocator);
    defer art.deinit(allocator);
}

test "inserting a value into tree" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree([]const u8, u32).init(allocator);
    defer art.deinit(allocator);

    const key_1 = "h";
    const value_1 = 1;

    // add a first value into the tree
    try art.insert(allocator, key_1, value_1);
    try testing.expectEqual(1, art.size);

    try art.prettyPrint(allocator);

    // add a new value to the tree
    const key_2 = "he";
    const value_2 = 2;

    try art.insert(allocator, key_2, value_2);
    try testing.expectEqual(2, art.size);

    try art.prettyPrint(allocator);

    // add a new value to the tree
    const key_3 = "hel";
    const value_3 = 3;

    try art.insert(allocator, key_3, value_3);
    try testing.expectEqual(3, art.size);

    const key_4 = "hell";
    const value_4 = 4;

    try art.insert(allocator, key_4, value_4);
    try testing.expectEqual(4, art.size);

    const key_5 = "hello";
    const value_5 = 5;

    try art.insert(allocator, key_5, value_5);
    try testing.expectEqual(5, art.size);

    const key_6 = "hello_";
    const value_6 = 6;

    try art.insert(allocator, key_6, value_6);
    try testing.expectEqual(6, art.size);

    const key_7 = "hello_w";
    const value_7 = 7;

    try art.insert(allocator, key_7, value_7);
    try testing.expectEqual(7, art.size);

    const key_8 = "hello_wo";
    const value_8 = 8;

    try art.insert(allocator, key_8, value_8);
    try testing.expectEqual(8, art.size);

    // try art.prettyPrint(allocator);
}

test "insert 100 items" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree([]const u8, usize).init(allocator);
    defer art.deinit(allocator);

    const iters: usize = 100;
    var keys = try std.ArrayList([]const u8).initCapacity(allocator, iters);
    defer keys.deinit(allocator);

    for (0..iters) |i| {
        const k = try std.fmt.allocPrint(allocator, "{d}", .{i});
        try art.insert(allocator, k, i);
    }

    try art.prettyPrint(allocator);
}
