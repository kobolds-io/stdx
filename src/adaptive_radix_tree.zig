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
            leaf: Leaf,
            node_4: Node4,
            node_16: Node16,
            node_48: Node48,
            node_256: Node256,
        };

        const Leaf = struct {
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
                .leaf => |old_leaf| {
                    // If identical key, replace value and return same leaf pointer
                    if (std.mem.eql(u8, old_leaf.key, key)) {
                        node_ptr.leaf.value = value;
                        return;
                    }

                    // allocate a new leaf for the incomming KV
                    const new_leaf = try allocator.create(Node);
                    new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                    const old_leaf_clone = try allocator.create(Node);
                    old_leaf_clone.* = .{ .leaf = .{ .key = old_leaf.key, .value = old_leaf.value } };

                    // find first differing byte
                    var idx: usize = 0;
                    while (idx < old_leaf.key.len and idx < key.len and old_leaf.key[idx] == key[idx]) {
                        idx += 1;
                    }

                    // if one key ended, treat missing byte as 0
                    const old_k: u8 = if (idx < old_leaf.key.len) old_leaf.key[idx] else 0;
                    const new_k: u8 = if (idx < key.len) key[idx] else 0;

                    // override the node_ptr with the new Node4. *Note that this means that `old_leaf`
                    // and `node_ptr.leaf` no longer are the same!
                    node_ptr.* = Node{
                        .node_4 = Node4{
                            .prefix_len = @intCast(idx),
                            .prefix = undefined,
                            .num_children = 2,
                            .keys = [_]u8{0} ** 4,
                            .children = [_]?*Node{null} ** 4,
                        },
                    };

                    // std.debug.print("idx: {}, old_leaf.key.len: {}, old_leaf: {any}\n", .{ idx, old_leaf.key.len, old_leaf });
                    // micro optimization
                    if (idx > 0) {
                        @memcpy(node_ptr.node_4.prefix[0..idx], old_leaf.key[0..idx]);
                    }

                    // install children in sorted order (old then new or new then old depending on byte)
                    if (old_k <= new_k) {
                        node_ptr.node_4.keys[0] = old_k;
                        node_ptr.node_4.children[0] = old_leaf_clone;

                        node_ptr.node_4.keys[1] = new_k;
                        node_ptr.node_4.children[1] = new_leaf;
                    } else {
                        node_ptr.node_4.keys[0] = new_k;
                        node_ptr.node_4.children[0] = new_leaf;

                        node_ptr.node_4.keys[1] = old_k;
                        node_ptr.node_4.children[1] = old_leaf_clone;
                    }

                    self.size += 1;
                },
                .node_4 => |*n4| {
                    const b = key[depth];

                    // search for existing child
                    var i: usize = 0;
                    while (i < n4.num_children) : (i += 1) {
                        if (n4.keys[i] == b) {
                            // descend (child may be replaced in-place)
                            return self.insertAt(allocator, n4.children[i].?, key, value, depth + 1);
                        }
                    }

                    // Need to insert new child LeafNode and to keep the keys sorted
                    if (n4.num_children < n4.children.len) {
                        const new_leaf = try allocator.create(Node);
                        new_leaf.* = Node{ .leaf = .{ .key = key, .value = value } };

                        i = 0;
                        while (i < n4.num_children and n4.keys[i] < b) : (i += 1) {}

                        // shift keys and children right one slot to make room. Ranges are safe
                        // because n4.num_children < n4.children.len
                        @memmove(n4.keys[i + 1 .. n4.num_children + 1], n4.keys[i..n4.num_children]);
                        @memmove(n4.children[i + 1 .. n4.num_children + 1], n4.children[i..n4.num_children]);

                        // insert the new leaf
                        n4.keys[i] = b;
                        n4.children[i] = new_leaf;
                        n4.num_children += 1;
                        self.size += 1;
                        return;
                    }

                    // upgrade to Node16
                    const new_node = try allocator.create(Node);
                    new_node.* = Node{
                        .node_16 = .{
                            .prefix_len = n4.prefix_len,
                            .prefix = n4.prefix,
                            .num_children = 0,
                            .keys = .{0} ** 16,
                            .children = .{null} ** 16,
                        },
                    };

                    // Copy existing children
                    var j: usize = 0;
                    while (j < n4.children.len) : (j += 1) {
                        new_node.node_16.keys[j] = n4.keys[j];
                        new_node.node_16.children[j] = n4.children[j];
                    }

                    new_node.node_16.num_children = 4;

                    node_ptr.* = new_node.*;
                    allocator.destroy(new_node);

                    // Continue inserting into the new Node16
                    var n16 = &node_ptr.node_16;

                    // Insert new key at end (unsorted for now)
                    const new_leaf = try allocator.create(Node);
                    new_leaf.* = Node{ .leaf = .{ .key = key, .value = value } };

                    n16.keys[n16.num_children] = b;
                    n16.children[n16.num_children] = new_leaf;
                    n16.num_children += 1;

                    // insertion-sort the last element backward; use k, not j
                    var k: usize = n16.num_children - 1;
                    while (k > 0 and n16.keys[k - 1] > n16.keys[k]) : (k -= 1) {
                        std.mem.swap(u8, &n16.keys[k - 1], &n16.keys[k]);
                        std.mem.swap(?*Node, &n16.children[k - 1], &n16.children[k]);
                    }

                    self.size += 1;
                    return;
                },
                .node_16 => |n16| {
                    const b: u8 = key[depth];

                    // search for existing child
                    var i: usize = 0;
                    while (i < n16.num_children) : (i += 1) {
                        if (n16.keys[i] == b) {
                            // descend (child may be replaced in-place)
                            return self.insertAt(allocator, n16.children[i].?, key, value, depth + 1);
                        }
                    }

                    // If Node16 is not full, insert new key in sorted order
                    std.debug.print("n16.num_children: {}\n", .{n16.num_children});
                    // if (n16.num_children < n16.children.len) {
                    //     const new_leaf = try allocator.create(Node);
                    //     new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                    //     // Find insert position to keep keys sorted
                    //     i = 0;
                    //     while (i < n16.num_children and n16.keys[i] < b) : (i += 1) {}

                    //     // Shift keys and children to make room
                    //     @memmove(node_ptr.node_16.keys[i + 1 .. n16.num_children + 1], n16.keys[i..n16.num_children]);
                    //     @memmove(node_ptr.node_16.children[i + 1 .. n16.num_children + 1], n16.children[i..n16.num_children]);

                    //     node_ptr.node_16.keys[i] = b;
                    //     node_ptr.node_16.children[i] = new_leaf;
                    //     node_ptr.node_16.num_children += 1;
                    //     self.size += 1;
                    //     return;
                    // }

                    if (n16.num_children < n16.children.len) {
                        const new_leaf = try allocator.create(Node);
                        new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                        // Find insert position to keep keys sorted
                        i = 0;
                        while (i < n16.num_children and n16.keys[i] < b) : (i += 1) {}

                        // Shift keys and children to make room
                        @memmove(node_ptr.node_16.keys[i + 1 .. n16.num_children + 1], n16.keys[i..n16.num_children]);
                        @memmove(node_ptr.node_16.children[i + 1 .. n16.num_children + 1], n16.children[i..n16.num_children]);

                        node_ptr.node_16.keys[i] = b;
                        node_ptr.node_16.children[i] = new_leaf;
                        node_ptr.node_16.num_children += 1;
                        self.size += 1;
                        return;
                    }

                    // Node16 full → upgrade to Node48
                    const new_node = try allocator.create(Node);
                    new_node.* = Node{
                        .node_48 = Node48{
                            .prefix_len = n16.prefix_len,
                            .prefix = n16.prefix,
                            .num_children = n16.num_children,
                            .index = [_]u8{0xFF} ** 256,
                            .children = [_]?*Node{null} ** 48,
                            .keys = [_]u8{0} ** 256,
                        },
                    };

                    std.debug.print("here!@!!!!\n", .{});

                    var n48 = &new_node.node_48;

                    // Copy all existing children into Node48
                    for (0..n16.num_children) |j| {
                        const k = n16.keys[j];
                        n48.children[j] = n16.children[j];
                        n48.index[k] = @intCast(j);
                        n48.keys[k] = @intCast(j + 1);
                    }

                    // Replace node_ptr in-place with new Node48
                    node_ptr.* = new_node.*;
                    allocator.destroy(new_node);

                    // Insert the new leaf into Node48
                    const new_leaf = try allocator.create(Node);
                    new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                    // Find first free slot in children[]
                    var slot: usize = 0;
                    while (slot < node_ptr.node_48.children.len) : (slot += 1) {
                        if (node_ptr.node_48.children[slot] == null) break;
                    }

                    node_ptr.node_48.children[slot] = new_leaf;
                    node_ptr.node_48.index[b] = @intCast(slot);
                    node_ptr.node_48.keys[b] = @intCast(slot + 1);
                    node_ptr.node_48.num_children += 1;

                    self.size += 1;
                    return;
                },

                // .node_16 => |*n16| {
                //     const new_node = try allocator.create(Node);
                //     new_node.* = Node{
                //         .node_48 = .{
                //             .prefix_len = n16.prefix_len,
                //             .prefix = n16.prefix,
                //             .num_children = n16.num_children,
                //             .index = .{0xFF} ** 256, // 0xFF = empty
                //             .children = .{null} ** 48,
                //             .keys = .{0} ** 256,
                //         },
                //     };

                //     var n48 = &new_node.node_48;

                //     // Copy existing Node16 children into Node48
                //     var i: usize = 0;
                //     while (i < n16.num_children) : (i += 1) {
                //         const k = n16.keys[i];
                //         // position in children[]
                //         n48.index[k] = @intCast(i);
                //         // copy child pointer
                //         n48.children[i] = n16.children[i];
                //         // mark key as used
                //         n48.keys[k] = @intCast(i + 1);
                //     }

                //     node_ptr.* = new_node.*;
                //     allocator.destroy(new_node);

                //     // Insert new key into Node48
                //     const b: u8 = key[depth];
                //     const new_leaf = try Self.allocLeaf(allocator, key, value);

                //     // Find first empty child slot
                //     var slot: usize = 0;
                //     while (slot < 48) : (slot += 1) {
                //         if (n48.children[slot] == null) break;
                //     }

                //     n48.children[slot] = new_leaf;
                //     n48.index[b] = @intCast(slot);
                //     n48.keys[b] = @intCast(slot + 1);
                //     n48.num_children += 1;

                //     self.size += 1;
                //     return;
                // },
                .node_48 => |*n48| {
                    const b = key[depth];

                    // Look up existing child
                    const child_idx = n48.index[b];
                    if (child_idx != 0xFF) {
                        const pos = @as(usize, child_idx);
                        return self.insertAt(allocator, n48.children[pos].?, key, value, depth + 1);
                    }

                    // Insert into Node48 if not full
                    if (n48.num_children < 48) {
                        const new_leaf = try Self.allocLeaf(allocator, key, value);

                        // Find first free slot
                        var slot: usize = 0;
                        while (slot < 48) : (slot += 1) {
                            if (n48.children[slot] == null) break;
                        }

                        n48.children[slot] = new_leaf;
                        n48.index[b] = @intCast(slot);
                        n48.keys[b] = @intCast(slot + 1);
                        n48.num_children += 1;
                        self.size += 1;
                        return;
                    }

                    // Node48 is full → grow to Node256
                    const new_node = try allocator.create(Node);
                    new_node.* = Node{
                        .node_256 = .{
                            .prefix_len = n48.prefix_len,
                            .prefix = n48.prefix,
                            .num_children = n48.num_children,
                            .children = .{null} ** 256,
                        },
                    };

                    var n256 = &new_node.node_256;

                    // Copy Node48 → Node256
                    var byte: usize = 0;
                    while (byte < 256) : (byte += 1) {
                        const k = n48.keys[byte];
                        if (k != 0) {
                            const idx = @as(usize, k) - 1;
                            n256.children[byte] = n48.children[idx];
                        }
                    }

                    node_ptr.* = new_node.*;
                    allocator.destroy(new_node);

                    // Now insert into Node256
                    const new_leaf = try Self.allocLeaf(allocator, key, value);
                    n256.children[b] = new_leaf;
                    n256.num_children += 1;
                    self.size += 1;

                    return;
                },
                .node_256 => |*n256| {
                    const b = key[depth];

                    // Existing child?
                    if (n256.children[b]) |c| {
                        return self.insertAt(allocator, c, key, value, depth + 1);
                    }

                    // Insert directly
                    const new_leaf = try Self.allocLeaf(allocator, key, value);
                    n256.children[b] = new_leaf;
                    n256.num_children += 1;
                    self.size += 1;

                    return;
                },

                // else => @panic("Implement other node types next"),
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

    const key_2 = "he";
    const value_2 = 2;

    try art.insert(allocator, key_2, value_2);
    try testing.expectEqual(2, art.size);

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

    const key_9 = "hello_wor";
    const value_9 = 9;

    try art.insert(allocator, key_9, value_9);
    try testing.expectEqual(9, art.size);

    // const key_10 = "hello_worl";
    // const value_10 = 10;

    // try art.insert(allocator, key_10, value_10);
    // try testing.expectEqual(10, art.size);

    // const key_11 = "hello_world";
    // const value_11 = 11;

    // try art.insert(allocator, key_11, value_11);
    // try testing.expectEqual(11, art.size);

    try art.prettyPrint(allocator);
}

// test "insert 100 items" {
//     const allocator = testing.allocator;

//     var art = AdaptiveRadixTree([]const u8, usize).init(allocator);
//     defer art.deinit(allocator);

//     const iters: usize = 100;
//     var keys = try std.ArrayList([]const u8).initCapacity(allocator, iters);
//     defer keys.deinit(allocator);

//     const prefix = "prefix";
//     for (0..iters) |i| {
//         const k = try std.fmt.allocPrint(allocator, "{s}{d}", .{ prefix, i });
//         try keys.append(allocator, k);
//         try art.insert(allocator, k, i);
//     }

//     try testing.expectEqual(iters, art.size);

//     defer {
//         for (keys.items) |k| {
//             allocator.free(k);
//         }
//     }

//     try art.prettyPrint(allocator);
// }
