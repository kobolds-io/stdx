const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const MAX_PREFIX: usize = 8; // usually 8 or 10
const TERMINATOR: u8 = 0xFF; // handles the edge case

const InsertError = std.mem.Allocator.Error || error{
    TreeInvariantViolation,
};

const DeleteResult = enum {
    node_found,
    node_removed, // node still exists
    node_deleted, // caller must remove this child pointer
};

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
            num_children: u16,
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

        pub fn lookup(self: *Self, key: []const u8) ?V {
            if (self.root == null) return null;

            return self.lookupAt(self.root.?, key, 0);
        }

        fn lookupAt(self: *Self, node: *Node, key: []const u8, depth: usize) ?V {
            switch (node.*) {
                .leaf => |leaf| {
                    if (std.mem.eql(u8, leaf.key, key)) {
                        return leaf.value;
                    }

                    return null;
                },
                .node_4 => |*n4| {
                    return lookupInnerNode(
                        self,
                        n4.prefix_len,
                        &n4.prefix,
                        n4.keys[0..n4.num_children],
                        n4.children[0..n4.num_children],
                        key,
                        depth,
                    );
                },
                .node_16 => |*n16| {
                    return lookupInnerNode(
                        self,
                        n16.prefix_len,
                        &n16.prefix,
                        n16.keys[0..n16.num_children],
                        n16.children[0..n16.num_children],
                        key,
                        depth,
                    );
                },
                .node_48 => |*n48| return lookupNode48(self, n48, key, depth),
                .node_256 => |*n256| return lookupNode256(self, n256, key, depth),
            }
        }

        fn lookupInnerNode(
            self: *Self,
            prefix_len: u8,
            prefix: *const [MAX_PREFIX]u8,
            keys: []const u8,
            children: []const ?*Node,
            key: []const u8,
            depth: usize,
        ) ?V {
            const max_cmp = @min(prefix_len, key.len - depth);
            var i: usize = 0;
            while (i < max_cmp and prefix.*[i] == key[depth + i]) : (i += 1) {}

            if (i < prefix_len) return null;

            const next_depth = depth + prefix_len;
            const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

            for (keys, 0..) |k, idx| {
                if (k == b) {
                    return self.lookupAt(children[idx].?, key, next_depth + 1);
                }
            }

            return null;
        }

        fn lookupNode48(
            self: *Self,
            n48: *Node48,
            key: []const u8,
            depth: usize,
        ) ?V {
            const max_cmp = @min(n48.prefix_len, key.len - depth);
            var i: usize = 0;
            while (i < max_cmp and n48.prefix[i] == key[depth + i]) : (i += 1) {}

            if (i < n48.prefix_len) return null;

            const next_depth = depth + n48.prefix_len;
            const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

            const idx = n48.index[b];
            if (idx == 0xFF) return null;

            return self.lookupAt(
                n48.children[idx].?,
                key,
                next_depth + 1,
            );
        }

        fn lookupNode256(
            self: *Self,
            n256: *Node256,
            key: []const u8,
            depth: usize,
        ) ?V {
            const max_cmp = @min(n256.prefix_len, key.len - depth);
            var i: usize = 0;
            while (i < max_cmp and n256.prefix[i] == key[depth + i]) : (i += 1) {}

            if (i < n256.prefix_len) return null;

            const next_depth = depth + n256.prefix_len;
            const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

            if (n256.children[b]) |child| {
                return self.lookupAt(child, key, next_depth + 1);
            }

            return null;
        }

        pub fn delete(self: *Self, allocator: std.mem.Allocator, key: []const u8) bool {
            if (self.root == null) return false;

            const res = self.deleteAt(allocator, self.root.?, key, 0);
            if (res) {
                self.size -= 1;
                if (self.size == 0) self.root = null;
            }

            return res;
        }

        fn deleteAt(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            key: []const u8,
            depth: usize,
        ) bool {
            switch (node_ptr.*) {
                .leaf => |leaf| {
                    if (!std.mem.eql(u8, leaf.key, key)) return false;

                    allocator.destroy(node_ptr);
                    return true;
                },
                .node_4 => |*n4| {
                    // ---------------- prefix compare ----------------
                    var i: usize = 0;
                    while (i < n4.prefix_len and depth + i < key.len and n4.prefix[i] == key[depth + i]) : (i += 1) {}

                    // prefix mismatch -> key not present
                    if (i < n4.prefix_len) return false;

                    const next_depth = depth + n4.prefix_len;
                    const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

                    // ---------------- lookup child ----------------
                    var idx: usize = 0;
                    while (idx < n4.num_children) : (idx += 1) {
                        if (n4.keys[idx] == b) {
                            // if there is no child deleted, then there was not match!
                            if (!self.deleteAt(allocator, n4.children[idx].?, key, next_depth + 1)) return false;

                            // handle the case where the last child was removed
                            if (idx == n4.num_children - 1) {
                                n4.keys[idx] = 0;
                                n4.children[idx] = null;
                            } else {
                                // shift children and keys left
                                var j: usize = idx;
                                while (j < n4.num_children) : (j += 1) {
                                    // handle the case where we cannot shift left
                                    if (j == 0) continue;

                                    // shift left
                                    n4.keys[j - 1] = n4.keys[j];
                                    n4.children[j - 1] = n4.children[j];

                                    // clean shifted slots
                                    n4.keys[j] = 0;
                                    n4.children[j] = null;
                                }
                            }

                            n4.num_children -= 1;

                            if (n4.num_children == 1) {
                                // if there is only a single child left, shrink this Node4
                                self.shrinkNode4(allocator, node_ptr, n4);
                            } else if (n4.num_children == 0) {
                                // destroy this node
                                allocator.destroy(node_ptr);
                            }

                            return true;
                        }
                    }

                    // child with byte b not found -> key not present
                    return false;
                },
                .node_16 => |*n16| {
                    // ---------------- prefix compare ----------------
                    var i: usize = 0;
                    while (i < n16.prefix_len and depth + i < key.len and n16.prefix[i] == key[depth + i]) : (i += 1) {}

                    // prefix mismatch -> key not present
                    if (i < n16.prefix_len) return false;

                    const next_depth = depth + n16.prefix_len;
                    const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

                    // ---------------- lookup child ----------------
                    var idx: usize = 0;
                    while (idx < n16.num_children) : (idx += 1) {
                        if (n16.keys[idx] == b) {
                            // if there is no child deleted, then there was not match!
                            // ---------------- recursive delete ----------------
                            if (!self.deleteAt(allocator, n16.children[idx].?, key, next_depth + 1)) return false;

                            // handle the case where the last child was removed
                            if (idx == n16.num_children - 1) {
                                n16.keys[idx] = 0;
                                n16.children[idx] = null;
                            } else {
                                // shift children and keys left
                                var j: usize = idx;
                                while (j < n16.num_children) : (j += 1) {
                                    // handle the case where we cannot shift left
                                    if (j == 0) continue;

                                    // shift left
                                    n16.keys[j - 1] = n16.keys[j];
                                    n16.children[j - 1] = n16.children[j];

                                    // clean shifted slots
                                    n16.keys[j] = 0;
                                    n16.children[j] = null;
                                }
                            }

                            n16.num_children -= 1;

                            // ---------------- shrink / destroy ----------------
                            if (n16.num_children <= 4) {
                                // if there is only a single child left, shrink this Node4 into a Leaf
                                self.shrinkNode16ToNode4(allocator, node_ptr, n16);
                            } else if (n16.num_children == 0) {
                                allocator.destroy(node_ptr);
                            }

                            return true;
                        }
                    }

                    // child with byte b not found -> key not present
                    return false;
                },
                .node_48 => |*n48| {
                    // ---------------- prefix compare ----------------
                    var i: usize = 0;
                    while (i < n48.prefix_len and depth + i < key.len and n48.prefix[i] == key[depth + i]) : (i += 1) {}

                    // prefix mismatch -> key not present
                    if (i < n48.prefix_len) return false;

                    const next_depth = depth + n48.prefix_len;
                    const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

                    // ---------------- lookup child ----------------
                    const key_idx = n48.keys[b];
                    if (key_idx == 0) return false; // child does not exist

                    const child_idx: usize = @intCast(key_idx - 1);
                    const child_ptr = n48.children[child_idx].?;

                    // ---------------- recursive delete ----------------
                    if (!self.deleteAt(allocator, child_ptr, key, next_depth + 1)) return false;

                    // clear key mapping
                    n48.keys[b] = 0;

                    // if last child, just clear slot
                    if (child_idx == n48.num_children - 1) {
                        n48.children[child_idx] = null;
                    } else {
                        // shift children left
                        var j: usize = child_idx;
                        while (j + 1 < n48.num_children) : (j += 1) {
                            n48.children[j] = n48.children[j + 1];
                        }
                        n48.children[n48.num_children - 1] = null;

                        // fix key indices that pointed past removed child
                        var k: usize = 0;
                        while (k < n48.keys.len) : (k += 1) {
                            const v = n48.keys[k];
                            if (v != 0 and v - 1 > child_idx) {
                                n48.keys[k] = v - 1;
                            }
                        }
                    }

                    n48.num_children -= 1;

                    // ---------------- shrink / destroy ----------------
                    if (n48.num_children <= 16) {
                        self.shrinkNode48ToNode16(allocator, node_ptr, n48);
                    } else if (n48.num_children == 0) {
                        allocator.destroy(node_ptr);
                    }

                    return true;
                },
                .node_256 => |*n256| {
                    // ---------------- prefix check ----------------
                    var i: usize = 0;
                    while (i < n256.prefix_len and
                        depth + i < key.len and
                        n256.prefix[i] == key[depth + i]) : (i += 1)
                    {}

                    // prefix mismatch -> key not present
                    if (i < n256.prefix_len) return false;

                    const next_depth = depth + n256.prefix_len;
                    const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

                    // no child -> key not present
                    const child = n256.children[b] orelse return false;

                    // ---------------- recursive delete ----------------
                    if (!self.deleteAt(allocator, child, key, next_depth + 1)) return false;

                    // child was deleted -> clear slot
                    n256.children[b] = null;
                    n256.num_children -= 1;

                    // ---------------- shrink / destroy ----------------
                    if (n256.num_children <= 48) {
                        self.shrinkNode256ToNode48(allocator, node_ptr, n256);
                    } else if (n256.num_children == 0) {
                        // should never hit this since the node always shrinks
                        allocator.destroy(node_ptr);
                    }

                    return true;
                },
            }
        }

        fn shrinkNode4(_: Self, allocator: std.mem.Allocator, parent: *Node, n4: *Node4) void {
            assert(n4.num_children == 1);

            const child = n4.children[0].?;
            switch (child.*) {
                .leaf => {
                    parent.* = child.*;
                    allocator.destroy(child);
                },
                else => {},
            }
        }

        fn shrinkNode16ToNode4(_: Self, allocator: std.mem.Allocator, parent: *Node, n16: *Node16) void {
            assert(n16.num_children <= 4);

            // create a new node4
            var new_node = Node{
                .node_4 = .{
                    .children = [_]?*Node{null} ** 4,
                    .keys = [_]u8{0} ** 4,
                    .num_children = n16.num_children,
                    .prefix = undefined,
                    .prefix_len = 0,
                },
            };

            const n4 = &new_node.node_4;

            // copy the prefix
            @memcpy(n4.prefix[0..n16.prefix_len], n16.prefix[0..n16.prefix_len]);
            n4.prefix_len = n16.prefix_len;

            // copy the children and keys
            var i: usize = 0;
            while (i < n16.num_children) : (i += 1) {
                n4.keys[i] = n16.keys[i];
                n4.children[i] = n16.children[i];
            }

            // destroy the n16
            parent.* = new_node;
            _ = allocator;
        }

        fn shrinkNode48ToNode16(
            _: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            n48: *Node48,
        ) void {
            // Node48 should only shrink when <= 16 children
            assert(n48.num_children <= 16);

            // Allocate new Node16
            // const new_node = allocator.create(Node) catch unreachable;
            var new_node = Node{
                .node_16 = .{
                    .prefix_len = n48.prefix_len,
                    .prefix = n48.prefix,
                    .num_children = n48.num_children,
                    .keys = [_]u8{0} ** 16,
                    .children = [_]?*Node{null} ** 16,
                },
            };

            var n16 = &new_node.node_16;

            // Rebuild Node16 from Node48
            var out_idx: usize = 0;
            var b: usize = 0;
            while (b < 256) : (b += 1) {
                const k = n48.keys[b];
                if (k != 0) {
                    const child_idx = @as(usize, k) - 1;

                    n16.keys[out_idx] = @intCast(b);
                    n16.children[out_idx] = n48.children[child_idx];
                    out_idx += 1;
                }
            }

            assert(out_idx == n16.num_children);

            // Replace node in place
            node_ptr.* = new_node;
            _ = allocator;
            // allocator.destroy(new_node);
        }

        fn shrinkNode256ToNode48(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            n256: *Node256,
        ) void {
            _ = self;
            _ = allocator;
            // Node256 should only shrink when it fits into Node48
            std.debug.assert(n256.num_children <= 48);

            // Allocate new Node48
            // const new_node = allocator.create(Node) catch unreachable;
            var new_node = Node{
                .node_48 = .{
                    .prefix_len = n256.prefix_len,
                    .prefix = n256.prefix,
                    .num_children = @intCast(n256.num_children),
                    .index = [_]u8{0xFF} ** 256,
                    .keys = [_]u8{0} ** 256,
                    .children = [_]?*Node{null} ** 48,
                },
            };

            var n48 = &new_node.node_48;

            // Rebuild Node48 from Node256
            var slot: usize = 0;
            var b: usize = 0;
            while (b < 256) : (b += 1) {
                if (n256.children[b]) |child| {
                    assert(slot < 48);

                    n48.children[slot] = child;
                    n48.index[b] = @intCast(slot);
                    n48.keys[b] = @intCast(slot + 1);
                    slot += 1;
                }
            }

            assert(slot == n48.num_children);

            // Replace node in place
            node_ptr.* = new_node;
            // allocator.destroy(new_node);
        }

        pub fn insert(self: *Self, allocator: std.mem.Allocator, key: []const u8, value: V) InsertError!void {
            // tree is empty, just create a leaf
            if (self.root == null) {
                const new_node = try allocator.create(Node);
                new_node.* = Node{ .leaf = .{ .key = key, .value = value } };

                self.root = new_node;
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
        ) InsertError!void {
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

                    const old_byte: u8 = if (i < old_leaf.key.len) old_leaf.key[i] else TERMINATOR;
                    const new_byte: u8 = if (i < key.len) key[i] else TERMINATOR;

                    // create a copy of the `old_leaf` to make sure we don't lose that information
                    const old_leaf_node = try allocator.create(Node);
                    old_leaf_node.* = Node{ .leaf = old_leaf.* };

                    // create a new leaf for the new key/value pair
                    const new_leaf = try allocator.create(Node);
                    new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                    // create a Node4 in place
                    node_ptr.* = Node{
                        .node_4 = .{
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
                            old_leaf_node.leaf.key[depth .. depth + node_ptr.node_4.prefix_len],
                        );
                    }

                    // insert the leaves in sorted order
                    if (old_byte < new_byte) {
                        node_ptr.node_4.keys[0] = old_byte;
                        node_ptr.node_4.children[0] = old_leaf_node;
                        node_ptr.node_4.keys[1] = new_byte;
                        node_ptr.node_4.children[1] = new_leaf;
                    } else {
                        node_ptr.node_4.keys[0] = new_byte;
                        node_ptr.node_4.children[0] = new_leaf;
                        node_ptr.node_4.keys[1] = old_byte;
                        node_ptr.node_4.children[1] = old_leaf_node;
                    }

                    self.size += 1;
                },
                .node_4 => |*n4| {
                    // check the prefix
                    const max_cmp = @min(n4.prefix_len, key.len - depth);
                    var i: usize = 0;
                    while (i < max_cmp and n4.prefix[i] == key[depth + i]) : (i += 1) {}

                    // ---------------- prefixes mismatch -> split node ----------------
                    if (i < n4.prefix_len) {
                        return self.splitNode4Prefix(
                            allocator,
                            node_ptr,
                            n4,
                            key,
                            value,
                            depth,
                            i,
                        );
                    }

                    // ---------------- prefixes match ----------------
                    const next_depth = depth + n4.prefix_len;
                    const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

                    // search for existing child, if found recursively `insertAt`
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
                        var insert_pos: usize = 0;
                        while (insert_pos < n4.num_children and n4.keys[insert_pos] < b) : (insert_pos += 1) {}

                        @memmove(
                            n4.keys[insert_pos + 1 .. n4.num_children + 1],
                            n4.keys[insert_pos..n4.num_children],
                        );
                        @memmove(
                            n4.children[insert_pos + 1 .. n4.num_children + 1],
                            n4.children[insert_pos..n4.num_children],
                        );

                        const new_leaf = try allocator.create(Node);
                        new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                        n4.keys[insert_pos] = b;
                        n4.children[insert_pos] = new_leaf;
                        n4.num_children += 1;

                        self.size += 1;

                        return;
                    }

                    // ---- Node4 full -> grow to Node16 ----
                    return self.growNode4ToNode16(allocator, node_ptr, n4, key, value, depth);
                },
                .node_16 => |*n16| {
                    // check the prefix
                    const max_cmp = @min(n16.prefix_len, key.len - depth);
                    var i: usize = 0;
                    while (i < max_cmp and n16.prefix[i] == key[depth + i]) : (i += 1) {}

                    // ---------------- prefixes mismatch -> split node ----------------
                    if (i < n16.prefix_len) {
                        return self.splitNode16Prefix(
                            allocator,
                            node_ptr,
                            n16,
                            key,
                            value,
                            depth,
                            i,
                        );
                    }

                    // ---------------- prefixes match ----------------
                    const next_depth = depth + n16.prefix_len;
                    const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

                    // search for existing child, if found recursively `insertAt`
                    var idx: usize = 0;
                    while (idx < n16.num_children) : (idx += 1) {
                        if (n16.keys[idx] == b) {
                            return self.insertAt(
                                allocator,
                                n16.children[idx].?,
                                key,
                                value,
                                next_depth + 1,
                            );
                        }
                    }

                    // ---------------- insert a new leaf (without growing) ----------------
                    if (n16.num_children < n16.children.len) {
                        // sort the insert
                        idx = 0;
                        while (idx < n16.num_children and n16.keys[idx] < b) : (idx += 1) {}

                        @memmove(
                            n16.keys[idx + 1 .. n16.num_children + 1],
                            n16.keys[idx..n16.num_children],
                        );
                        @memmove(
                            n16.children[idx + 1 .. n16.num_children + 1],
                            n16.children[idx..n16.num_children],
                        );

                        const new_leaf = try allocator.create(Node);
                        new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                        n16.keys[idx] = b;
                        n16.children[idx] = new_leaf;
                        n16.num_children += 1;
                        self.size += 1;
                        return;
                    }

                    // ---- Node16 full -> grow to Node48 ----
                    return self.growNode16ToNode48(allocator, node_ptr, n16, key, value, depth);
                },
                .node_48 => |*n48| {
                    // ---------------- prefix check ----------------
                    const max_cmp = @min(n48.prefix_len, key.len - depth);
                    var i: usize = 0;
                    while (i < max_cmp and n48.prefix[i] == key[depth + i]) : (i += 1) {}

                    // ---------------- prefix mismatch -> split ----------------
                    if (i < n48.prefix_len) {
                        // @panic("not implemented");
                        return self.splitNode48Prefix(
                            allocator,
                            node_ptr,
                            n48,
                            key,
                            value,
                            depth,
                            i,
                        );
                    }

                    // ---------------- prefix matches ----------------
                    const next_depth = depth + n48.prefix_len;

                    // if (next_depth == key.len) {
                    //     const idx = n48.index[TERMINATOR];
                    //     if (idx != 0xFF) {
                    //         n48.children[idx].?.leaf.value = value;
                    //         return;
                    //     }

                    //     const slot = findFreeSlot(&n48.children);
                    //     const leaf = try allocator.create(Node);
                    //     leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                    //     n48.children[idx] = leaf;
                    //     n48.index[TERMINATOR] = @intCast(slot);
                    //     n48.keys[TERMINATOR] = @intCast(slot + 1);
                    //     n48.num_children += 1;
                    //     self.size += 1;
                    //     return;
                    // }

                    const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;
                    const idx = n48.index[b];

                    // ---------------- existing child ----------------
                    if (idx != 0xFF) {
                        return self.insertAt(
                            allocator,
                            n48.children[idx].?,
                            key,
                            value,
                            next_depth + 1,
                        );
                    }

                    // ---------------- insert without growing ----------------
                    if (n48.num_children < 48) {
                        // find first free child slot
                        var slot: usize = 0;
                        while (slot < 48 and n48.children[slot] != null) : (slot += 1) {}

                        // slot must exist if num_children < 48
                        const new_leaf = try allocator.create(Node);
                        new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                        n48.children[slot] = new_leaf;
                        n48.index[b] = @intCast(slot);
                        n48.keys[b] = @intCast(slot + 1);
                        n48.num_children += 1;

                        self.size += 1;
                        return;
                    }

                    // ---------------- Node48 full -> grow to Node256 ----------------
                    return self.growNode48ToNode256(allocator, node_ptr, n48, key, value, depth);
                },
                // .node_256 => |*n256| {
                //     // ---------- prefix check ----------
                //     const max_cmp = @min(n256.prefix_len, key.len - depth);
                //     var i: usize = 0;
                //     while (i < max_cmp and n256.prefix[i] == key[depth + i]) : (i += 1) {}

                //     if (i < n256.prefix_len) {
                //         return self.splitNode256Prefix(
                //             allocator,
                //             node_ptr,
                //             n256,
                //             key,
                //             value,
                //             depth,
                //             i,
                //         );
                //     }

                //     const next_depth = depth + n256.prefix_len;

                //     // ---------- TERMINATOR INSERT ----------
                //     if (next_depth == key.len) {
                //         if (n256.children[TERMINATOR]) |child| {
                //             // overwrite existing leaf
                //             child.leaf.value = value;
                //             return;
                //         }

                //         const leaf = try allocator.create(Node);
                //         leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                //         n256.children[TERMINATOR] = leaf;
                //         n256.num_children += 1;
                //         self.size += 1;
                //         return;
                //     }

                //     // ---------- NORMAL BYTE ----------
                //     const b: u8 = key[next_depth];

                //     if (n256.children[b]) |child| {
                //         return self.insertAt(
                //             allocator,
                //             child,
                //             key,
                //             value,
                //             next_depth + 1,
                //         );
                //     }

                //     const leaf = try allocator.create(Node);
                //     leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                //     n256.children[b] = leaf;
                //     n256.num_children += 1;
                //     self.size += 1;
                // },

                .node_256 => |*n256| {
                    // ---------------- prefix check ----------------
                    const max_cmp = @min(n256.prefix_len, key.len - depth);
                    var i: usize = 0;
                    while (i < max_cmp and n256.prefix[i] == key[depth + i]) : (i += 1) {}

                    // -------- prefix mismatch -> split --------
                    if (i < n256.prefix_len) {
                        return self.splitNode256Prefix(
                            allocator,
                            node_ptr,
                            n256,
                            key,
                            value,
                            depth,
                            i,
                        );
                    }

                    // ---------------- prefix match ----------------
                    const next_depth = depth + n256.prefix_len;
                    const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

                    // child exists -> recurse
                    if (n256.children[b]) |child| {
                        return self.insertAt(
                            allocator,
                            child,
                            key,
                            value,
                            next_depth + 1,
                        );
                    }

                    // All children already exist -> this must be impossible
                    // unless the tree is corrupted or the prefix logic is wrong
                    assert(n256.num_children <= n256.children.len);

                    // ---------------- insert new leaf ----------------
                    const new_leaf = try allocator.create(Node);
                    new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

                    n256.children[b] = new_leaf;
                    n256.num_children += 1;
                    self.size += 1;
                },
            }
        }

        fn findFreeSlot(children: []const ?*Node) usize {
            var slot: usize = 0;
            while (slot < children.len) : (slot += 1) if (children[slot] == null) return slot;
            unreachable; // guaranteed by num_children < 48
        }

        fn splitNode4Prefix(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            n4: *Node4,
            key: []const u8,
            value: V,
            depth: usize,
            index: usize,
        ) !void {
            const old_byte = n4.prefix[index];
            const new_byte: u8 = if (depth + index < key.len) key[depth + index] else TERMINATOR;

            // new parent node
            const parent = try allocator.create(Node);
            parent.* = Node{
                .node_4 = .{
                    .prefix_len = @intCast(index),
                    .prefix = undefined,
                    .num_children = 0,
                    .keys = [_]u8{0} ** 4,
                    .children = [_]?*Node{null} ** 4,
                },
            };
            @memcpy(parent.node_4.prefix[0..index], n4.prefix[0..index]);

            // Clone old node
            const old_child = try allocator.create(Node);
            old_child.* = node_ptr.*;

            // fix old child's prefix
            const skip = index + 1;
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

        fn growNode4ToNode16(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            n4: *Node4,
            key: []const u8,
            value: V,
            depth: usize,
        ) !void {
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

            const next_depth = depth + n4.prefix_len;
            const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

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
        }

        fn splitNode16Prefix(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            n16: *Node16,
            key: []const u8,
            value: V,
            depth: usize,
            index: usize,
        ) !void {
            // Clone the old Node16 so we don't create cycles
            const old_node = try allocator.create(Node);
            old_node.* = node_ptr.*;

            const old_n16 = &old_node.node_16;

            // Create new parent Node4
            const parent = try allocator.create(Node);
            parent.* = .{
                .node_4 = .{
                    .prefix_len = @intCast(index),
                    .prefix = undefined,
                    .num_children = 0,
                    .keys = [_]u8{0} ** 4,
                    .children = [_]?*Node{null} ** 4,
                },
            };

            const n4 = &parent.node_4;

            // Copy shared prefix
            @memcpy(n4.prefix[0..index], n16.prefix[0..index]);

            // Trim prefix of old node
            const old_byte = n16.prefix[index];
            old_n16.prefix_len -= @intCast(index + 1);

            @memmove(
                old_n16.prefix[0..old_n16.prefix_len],
                old_n16.prefix[index + 1 .. index + 1 + old_n16.prefix_len],
            );

            // Attach old node as first child
            n4.keys[0] = old_byte;
            n4.children[0] = old_node;
            n4.num_children = 1;

            // Create new leaf for incoming key
            const new_leaf = try allocator.create(Node);
            new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

            const new_byte: u8 = if (depth + index < key.len) key[depth + index] else TERMINATOR;

            // Attach new leaf
            n4.keys[1] = new_byte;
            n4.children[1] = new_leaf;
            n4.num_children = 2;

            // Replace node_ptr with parent
            node_ptr.* = parent.*;
            allocator.destroy(parent);

            self.size += 1;
        }

        fn growNode16ToNode48(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            n16: *Node16,
            key: []const u8,
            value: V,
            depth: usize,
        ) !void {
            const new_node = try allocator.create(Node);
            new_node.* = .{
                .node_48 = .{
                    .prefix_len = n16.prefix_len,
                    .prefix = n16.prefix,
                    .num_children = n16.num_children,
                    .index = [_]u8{0xFF} ** 256,
                    .children = [_]?*Node{null} ** 48,
                    .keys = [_]u8{0} ** 256,
                },
            };

            var n48 = &new_node.node_48;

            // Copy Node16 children into Node48
            var i: usize = 0;
            while (i < n16.num_children) : (i += 1) {
                const byte = n16.keys[i];
                n48.children[i] = n16.children[i];
                n48.index[byte] = @intCast(i);
                n48.keys[byte] = @intCast(i + 1);
            }

            const next_depth = depth + n16.prefix_len;

            const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

            // Allocate new leaf
            const new_leaf = try allocator.create(Node);
            new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

            // Find first free child slot
            var slot: usize = 0;
            while (slot < n48.children.len) : (slot += 1) if (n48.children[slot] == null) break;

            assert(slot < n48.children.len);
            assert(n48.index[b] == 0xFF);

            // Insert
            n48.children[slot] = new_leaf;
            n48.index[b] = @intCast(slot);
            n48.keys[b] = @intCast(slot + 1);
            n48.num_children += 1;

            // Replace node in place
            node_ptr.* = new_node.*;
            allocator.destroy(new_node);

            self.size += 1;
        }

        fn splitNode48Prefix(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            n48: *Node48,
            key: []const u8,
            value: V,
            depth: usize,
            index: usize,
        ) InsertError!void {

            // create new parent Node4
            const parent = try allocator.create(Node);
            parent.* = Node{
                .node_4 = .{
                    .prefix_len = @intCast(index),
                    .prefix = undefined,
                    .num_children = 0,
                    .keys = [_]u8{0} ** 4,
                    .children = [_]?*Node{null} ** 4,
                },
            };

            const n4 = &parent.node_4;

            // Copy shared prefix
            if (index > 0) {
                @memcpy(n4.prefix[0..index], n48.prefix[0..index]);
            }

            // --- Trim prefix on old Node48 ---
            const old_byte = n48.prefix[index];

            n48.prefix_len -= @intCast(index + 1);
            if (n48.prefix_len > 0) {
                @memmove(
                    n48.prefix[0..n48.prefix_len],
                    n48.prefix[index + 1 .. index + 1 + n48.prefix_len],
                );
            }

            const old_node_copy = try allocator.create(Node);
            old_node_copy.* = node_ptr.*;

            // Attach old node under parent
            n4.keys[0] = old_byte;
            n4.children[0] = old_node_copy;
            n4.num_children = 1;

            // --- Create new leaf ---
            const new_leaf = try allocator.create(Node);
            new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

            const new_byte: u8 = if (depth + index < key.len) key[depth + index] else TERMINATOR;

            n4.keys[1] = new_byte;
            n4.children[1] = new_leaf;
            n4.num_children = 2;

            // Ensure sorted order (Node4 invariant)
            if (n4.keys[0] > n4.keys[1]) {
                std.mem.swap(u8, &n4.keys[0], &n4.keys[1]);
                std.mem.swap(?*Node, &n4.children[0], &n4.children[1]);
            }

            // Replace node_ptr with parent
            node_ptr.* = parent.*;
            allocator.destroy(parent);

            self.size += 1;
        }

        fn growNode48ToNode256(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            n48: *Node48,
            key: []const u8,
            value: V,
            depth: usize,
        ) !void {
            const new_node = try allocator.create(Node);
            new_node.* = Node{
                .node_256 = .{
                    .prefix_len = n48.prefix_len,
                    .prefix = n48.prefix,
                    .num_children = n48.num_children,
                    .children = [_]?*Node{null} ** 256,
                },
            };

            var n256 = &new_node.node_256;

            // copy children from Node48 to Node256
            // We iterate 0..256 because Node48 uses the 'index' array to map byte -> slot
            for (0..n48.index.len) |i| {
                const idx = n48.index[i];
                if (idx != 0xFF) {
                    // 'i' is the key byte, so it goes directly into children[i]
                    n256.children[i] = n48.children[idx].?;
                }
            }

            const next_depth = depth + n48.prefix_len;
            const b: u8 = if (next_depth < key.len) key[next_depth] else TERMINATOR;

            const new_leaf = try allocator.create(Node);
            new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

            n256.children[b] = new_leaf;
            n256.num_children += 1;

            node_ptr.* = new_node.*;
            allocator.destroy(new_node);

            self.size += 1;
        }

        // fn growNode48ToNode256(
        //     self: *Self,
        //     allocator: std.mem.Allocator,
        //     node_ptr: *Node,
        //     n48: *Node48,
        //     key: []const u8,
        //     value: V,
        //     _: usize,
        // ) !void {
        //     // allocate the new Node256
        //     const new_node = try allocator.create(Node);
        //     new_node.* = Node{
        //         .node_256 = .{
        //             .prefix_len = n48.prefix_len,
        //             .prefix = n48.prefix,
        //             .num_children = n48.num_children,
        //             .children = [_]?*Node{null} ** 256,
        //         },
        //     };

        //     var n256 = &new_node.node_256;

        //     // if there is node in the TERMINATOR slot, we should move it to the Node256 TERMINATOR slot
        //     const term_idx = n48.index[TERMINATOR];
        //     if (term_idx != 0xFF) {
        //         assert(n48.children[term_idx] != null);
        //         n256.children[TERMINATOR] = n48.children[term_idx].?;
        //         n256.num_children += 1;

        //         // remove this item from the node_48
        //         n48.index[TERMINATOR] = 0xFF;
        //         n48.keys[TERMINATOR] = 0;
        //         n48.children[term_idx] = null;
        //         n48.num_children -= 1;
        //     }

        //     // copy the keys and children from the Node4 to the Node256
        //     for (0..256) |b| {
        //         const idx = n48.index[b];
        //         if (idx != 0xFF) {
        //             n256.children[b] = n48.children[idx].?;
        //         }
        //     }

        //     // find the sorted position of where the new_leaf should be inserted
        //     const insert_pos = blk: {
        //         var k: usize = 0;
        //         while (k < n256.num_children) : (k += 1) if (n256.children[k] == null) break;
        //         break :blk k;
        //     };

        //     @memmove(
        //         n256.children[insert_pos + 1 .. n256.num_children + 1],
        //         n256.children[insert_pos..n256.num_children],
        //     );

        //     // create the new leaf
        //     const new_leaf = try allocator.create(Node);
        //     new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

        //     // insert the new leaf
        //     n256.children[insert_pos] = new_leaf;
        //     n256.num_children += 1;

        //     // replace node_ptr in-place
        //     node_ptr.* = new_node.*;
        //     allocator.destroy(new_node);

        //     self.size += 1;
        // }

        fn splitNode256Prefix(
            self: *Self,
            allocator: std.mem.Allocator,
            node_ptr: *Node,
            n256: *Node256,
            key: []const u8,
            value: V,
            depth: usize,
            index: usize,
        ) InsertError!void {
            // --- Create new parent Node4 ---
            const parent = try allocator.create(Node);
            parent.* = Node{
                .node_4 = .{
                    .prefix_len = @intCast(index),
                    .prefix = undefined,
                    .num_children = 0,
                    .keys = [_]u8{0} ** 4,
                    .children = [_]?*Node{null} ** 4,
                },
            };

            const n4 = &parent.node_4;

            // Copy shared prefix
            if (index > 0) {
                @memcpy(n4.prefix[0..index], n256.prefix[0..index]);
            }

            // --- Preserve old node before mutation ---
            const old_node = try allocator.create(Node);
            old_node.* = node_ptr.*;

            // --- Trim prefix on old Node256 ---
            const old_byte = n256.prefix[index];

            n256.prefix_len -= @intCast(index + 1);
            if (n256.prefix_len > 0) {
                @memmove(
                    n256.prefix[0..n256.prefix_len],
                    n256.prefix[index + 1 .. index + 1 + n256.prefix_len],
                );
            }

            // Attach old node under new parent
            n4.keys[0] = old_byte;
            n4.children[0] = old_node;
            n4.num_children = 1;

            // --- Create new leaf ---
            const new_leaf = try allocator.create(Node);
            new_leaf.* = .{ .leaf = .{ .key = key, .value = value } };

            const new_byte: u8 = if (depth + index < key.len) key[depth + index] else TERMINATOR;

            n4.keys[1] = new_byte;
            n4.children[1] = new_leaf;
            n4.num_children = 2;

            // Ensure sorted order (Node4 invariant)
            if (n4.keys[0] > n4.keys[1]) {
                std.mem.swap(u8, &n4.keys[0], &n4.keys[1]);
                std.mem.swap(?*Node, &n4.children[0], &n4.children[1]);
            }

            // Replace node_ptr with parent
            node_ptr.* = parent.*;
            allocator.destroy(parent);

            self.size += 1;
        }

        fn destroyNode(allocator: std.mem.Allocator, node_opt: ?*Node) void {
            if (node_opt == null) return;

            const node: *Node = node_opt.?;

            switch (node.*) {
                .leaf => allocator.destroy(node),
                inline else => |*n| {
                    for (n.children) |child| destroyNode(allocator, child);
                    allocator.destroy(node);
                },
            }
        }

        pub fn prettyPrint(self: *Self, allocator: std.mem.Allocator) !void {
            if (self.root) |r| {
                try printNodePretty(r, allocator, "", true);
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

test "grow root from leaf to node_4 on second insert" {
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

    // try art.prettyPrint(allocator);

    try testing.expectEqual(2, art.size);
    try testing.expectEqual(2, art.root.?.node_4.num_children);

    try testing.expectEqualStrings(k1, art.root.?.node_4.children[1].?.leaf.key);
    try testing.expectEqual(v1, art.root.?.node_4.children[1].?.leaf.value);

    try testing.expectEqualStrings(k2, art.root.?.node_4.children[0].?.leaf.key);
    try testing.expectEqual(v2, art.root.?.node_4.children[0].?.leaf.value);
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

    try testing.expectEqualStrings("abc", child_node_4.node_4.children[0].?.leaf.key);
    try testing.expectEqualStrings("ab", child_node_4.node_4.children[1].?.leaf.key);
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

test "node16 prefix mismatch split" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    // These two keys share "ab", then diverge at index 2
    // This guarantees a Node4 prefix mismatch split
    const k0 = "a0";
    const k1 = "a1";
    const k2 = "a2";
    const k3 = "a3";
    const k4 = "a4";
    const k5 = "b5";

    try art.insert(allocator, k0, 0);
    try art.insert(allocator, k1, 0); // upgrade to Node4
    try art.insert(allocator, k2, 0);
    try art.insert(allocator, k3, 0);
    try art.insert(allocator, k4, 0); // upgrade to Node16
    try art.insert(allocator, k5, 0); // split the Node16

    // try art.prettyPrint(allocator);

    try testing.expectEqual(6, art.size);

    // Root must be Node4 after split
    const root = art.root orelse return error.TestFailed;

    // there are 2 kiddos
    try testing.expectEqual(2, root.node_4.num_children);
    try testing.expectEqual(0, root.node_4.prefix_len);

    // expect the first child to be the Node16
    const child_node_16 = root.node_4.children[0] orelse return error.TestFailed;
    try testing.expectEqual(0, child_node_16.node_16.prefix_len);
    try testing.expectEqualStrings(k0, child_node_16.node_16.children[0].?.leaf.key);
    try testing.expectEqualStrings(k1, child_node_16.node_16.children[1].?.leaf.key);
    try testing.expectEqualStrings(k2, child_node_16.node_16.children[2].?.leaf.key);
    try testing.expectEqualStrings(k3, child_node_16.node_16.children[3].?.leaf.key);
    try testing.expectEqualStrings(k4, child_node_16.node_16.children[4].?.leaf.key);

    const child_leaf_node = root.node_4.children[1] orelse return error.TestFailed;
    try testing.expectEqualStrings(k5, child_leaf_node.leaf.key);
}

test "node16 grows to node48" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    const k0 = "a0";
    const k1 = "a1";
    const k2 = "a2";
    const k3 = "a3";
    const k4 = "a4";
    const k5 = "a5";
    const k6 = "a6";
    const k7 = "a7";
    const k8 = "a8";
    const k9 = "a9";
    const k10 = "aa";
    const k11 = "ab";
    const k12 = "ac";
    const k13 = "ad";
    const k14 = "ae";
    const k15 = "af";
    const k16 = "ag";

    try art.insert(allocator, k0, 0);
    try art.insert(allocator, k1, 0);
    try art.insert(allocator, k2, 0);
    try art.insert(allocator, k3, 0);
    try art.insert(allocator, k4, 0);
    try art.insert(allocator, k5, 0);
    try art.insert(allocator, k6, 0);
    try art.insert(allocator, k7, 0);
    try art.insert(allocator, k8, 0);
    try art.insert(allocator, k9, 0);
    try art.insert(allocator, k10, 0);
    try art.insert(allocator, k11, 0);
    try art.insert(allocator, k12, 0);
    try art.insert(allocator, k13, 0);
    try art.insert(allocator, k14, 0);
    try art.insert(allocator, k15, 0);
    try art.insert(allocator, k16, 0); // grow to Node48

    // try art.prettyPrint(allocator);

    const root = art.root orelse return error.TestFailed;
    try testing.expectEqual(17, art.size);
    try testing.expectEqual(17, root.node_48.num_children);
}

test "node48 prefix mismatch split" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    try art.insert(allocator, "a0", 0);
    try art.insert(allocator, "a1", 0);
    try art.insert(allocator, "a2", 0);
    try art.insert(allocator, "a3", 0);
    try art.insert(allocator, "a4", 0);
    try art.insert(allocator, "a5", 0);
    try art.insert(allocator, "a6", 0);
    try art.insert(allocator, "a7", 0);
    try art.insert(allocator, "a8", 0);
    try art.insert(allocator, "a9", 0); // 10

    try art.insert(allocator, "aa", 0);
    try art.insert(allocator, "ab", 0);
    try art.insert(allocator, "ac", 0);
    try art.insert(allocator, "ad", 0);
    try art.insert(allocator, "ae", 0);
    try art.insert(allocator, "af", 0);
    try art.insert(allocator, "ag", 0); // grow to Node48

    try art.insert(allocator, "ba", 0); // split the Node48

    // try art.prettyPrint(allocator);

    const root = art.root orelse return error.TestFailed;
    try testing.expectEqual(18, art.size);

    try testing.expectEqualStrings("ba", root.node_4.children[1].?.leaf.key);
}

test "node48 grows to node256" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    try art.insert(allocator, "a0", 0);
    try art.insert(allocator, "a1", 99);
    try art.insert(allocator, "a2", 0);
    try art.insert(allocator, "a3", 0);
    try art.insert(allocator, "a4", 0);
    try art.insert(allocator, "a5", 0);
    try art.insert(allocator, "a6", 0);
    try art.insert(allocator, "a7", 0);
    try art.insert(allocator, "a8", 0);
    try art.insert(allocator, "a9", 0); // 10

    // try art.prettyPrint(allocator);

    try art.insert(allocator, "aa", 0);
    try art.insert(allocator, "ab", 0);
    try art.insert(allocator, "ac", 0);
    try art.insert(allocator, "ad", 0);
    try art.insert(allocator, "ae", 0);
    try art.insert(allocator, "af", 0);
    try art.insert(allocator, "ag", 0);
    try art.insert(allocator, "ah", 0);
    try art.insert(allocator, "ai", 0);
    try art.insert(allocator, "aj", 0);
    try art.insert(allocator, "ak", 0);
    try art.insert(allocator, "al", 0);
    try art.insert(allocator, "am", 0);
    try art.insert(allocator, "an", 0);
    try art.insert(allocator, "ao", 0);
    try art.insert(allocator, "ap", 0);
    try art.insert(allocator, "aq", 0);
    try art.insert(allocator, "ar", 0);
    try art.insert(allocator, "as", 0);
    try art.insert(allocator, "at", 0);
    try art.insert(allocator, "au", 0);
    try art.insert(allocator, "av", 0);
    try art.insert(allocator, "aw", 0);
    try art.insert(allocator, "ax", 0);
    try art.insert(allocator, "ay", 0);
    try art.insert(allocator, "az", 0); // 26

    // try art.prettyPrint(allocator);

    try art.insert(allocator, "a~", 0);
    try art.insert(allocator, "a!", 0);
    try art.insert(allocator, "a@", 0);
    try art.insert(allocator, "a#", 0);
    try art.insert(allocator, "a%", 0);
    try art.insert(allocator, "a^", 0);
    try art.insert(allocator, "a&", 0);
    try art.insert(allocator, "a*", 0);
    try art.insert(allocator, "a(", 0);
    try art.insert(allocator, "a)", 0); // 10

    try art.insert(allocator, "a-", 0);
    try art.insert(allocator, "a_", 0);
    try art.insert(allocator, "a=", 0); // grow to Node256

    // try art.prettyPrint(allocator);

    const root = art.root orelse return error.TestFailed;
    try testing.expectEqual(49, art.size);
    try testing.expectEqual(49, root.node_256.num_children);
}

test "Node256 prefix mismatch triggers splitNode256Prefix" {
    const allocator = std.testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    for (0..100) |i| {
        const key = try allocator.alloc(u8, 3);
        key[0] = 'a';
        key[1] = 'a';
        key[2] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }

    defer {
        for (keys.items) |k| {
            allocator.free(k);
        }
    }

    // ensure that the tree is populated
    try testing.expectEqual(100, art.size);
    // ensure that the root node is a Node256
    try testing.expectEqual(100, art.root.?.node_256.num_children);

    const key = try allocator.alloc(u8, 3);
    key[0] = 'a';
    key[1] = 'b';
    key[2] = 0;

    // split the node
    try keys.append(allocator, key);
    try art.insert(allocator, key, 99);

    // ensure that the tree is populated
    try testing.expectEqual(101, art.size);

    const root = art.root orelse return error.TestFailed;

    try testing.expectEqual(2, root.node_4.num_children);

    // ensure the key matches the expected key
    try testing.expectEqual(keys.items[keys.items.len - 1], root.node_4.children[1].?.leaf.key);

    // try art.prettyPrint(allocator);
}

test "node256 does not grow" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    for (0..256) |i| {
        const key = try allocator.alloc(u8, 2);
        key[0] = 'a';
        key[1] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }

    defer {
        for (keys.items) |k| {
            allocator.free(k);
        }
    }

    // try art.prettyPrint(allocator);
}

test "lookup returns found value" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    for (0..256) |i| {
        const key = try allocator.alloc(u8, 2);
        key[0] = 'a';
        key[1] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }

    for (0..48) |i| {
        const key = try allocator.alloc(u8, 3);
        key[0] = 'a';
        key[1] = 'b';
        key[2] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }

    for (0..16) |i| {
        const key = try allocator.alloc(u8, 4);
        key[0] = 'a';
        key[1] = 'b';
        key[2] = 'c';
        key[3] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }

    for (0..4) |i| {
        const key = try allocator.alloc(u8, 5);
        key[0] = 'a';
        key[1] = 'b';
        key[2] = 'c';
        key[3] = 'd';
        key[4] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }

    for (0..1) |i| {
        const key = try allocator.alloc(u8, 6);
        key[0] = 'a';
        key[1] = 'b';
        key[2] = 'c';
        key[3] = 'd';
        key[4] = 'e';
        key[5] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }

    defer for (keys.items) |k| allocator.free(k);

    for (keys.items) |k| {
        try testing.expect(art.lookup(k) != null);
    }
}

test "lookup a value with differing key lengths" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    for (0..4) |i| {
        var key: []u8 = undefined;
        if (i == 1) {
            key = try allocator.alloc(u8, 2);
            key[0] = 'a';
            key[1] = 'b';
        } else {
            key = try allocator.alloc(u8, 3);
            key[0] = 'a';
            key[1] = 'b';
            key[2] = @intCast(i);
        }
        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }

    defer {
        for (keys.items) |k| {
            allocator.free(k);
        }
    }

    // try art.prettyPrint(allocator);

    for (keys.items) |k| {
        try testing.expect(art.lookup(k) != null);
    }
}

test "delete a leaf" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    const key = "asdf";
    const value = 10;

    try art.insert(allocator, key, value);

    // try art.prettyPrint(allocator);

    try testing.expect(art.root != null);
    try testing.expectEqual(1, art.size);
    try testing.expect(art.lookup(key) != null);

    try testing.expect(art.delete(allocator, key));

    try testing.expect(art.root == null);
    try testing.expectEqual(0, art.size);
}

test "handle deletes from a node4 in non-linear order" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    const key_0 = "aa";
    const value_0 = 0;

    const key_1 = "ab";
    const value_1 = 1;

    const key_2 = "ac";
    const value_2 = 2;

    const key_3 = "ad";
    const value_3 = 3;

    try art.insert(allocator, key_0, value_0);
    try art.insert(allocator, key_1, value_1);
    try art.insert(allocator, key_2, value_2);
    try art.insert(allocator, key_3, value_3);

    try testing.expect(art.root != null);
    try testing.expectEqual(4, art.size);
    try testing.expect(art.lookup(key_0) != null);
    try testing.expect(art.lookup(key_1) != null);
    try testing.expect(art.lookup(key_2) != null);
    try testing.expect(art.lookup(key_3) != null);

    switch (art.root.?.*) {
        .node_4 => |n4| {
            try testing.expectEqual(4, n4.num_children);
        },
        else => return error.TestFailed,
    }

    // std.debug.print("2 inserts\n", .{});
    // try art.prettyPrint(allocator);

    // std.debug.print("1 delete\n", .{});

    try testing.expect(art.delete(allocator, key_3));
    try testing.expect(art.root != null);
    try testing.expectEqual(3, art.size);

    // try art.prettyPrint(allocator);

    try testing.expect(art.delete(allocator, key_0));
    try testing.expect(art.root != null);
    try testing.expectEqual(2, art.size);

    // try art.prettyPrint(allocator);

    try testing.expect(art.delete(allocator, key_2));
    try testing.expect(art.root != null);
    try testing.expectEqual(1, art.size);

    // try art.prettyPrint(allocator);

    try testing.expect(art.delete(allocator, key_1));
    try testing.expect(art.root == null);
    try testing.expectEqual(0, art.size);

    // try art.prettyPrint(allocator);
}

test "handle deletes from a Node16 and shrinks correctly" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    for (0..16) |i| {
        const key = try allocator.alloc(u8, 2);
        key[0] = 'a';
        key[1] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }
    defer for (keys.items) |k| allocator.free(k);

    for (keys.items) |k| {
        // try art.prettyPrint(allocator);
        try testing.expect(art.delete(allocator, k));
    }
}

test "handle deletes from a Node48 and shrinks correctly" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    for (0..48) |i| {
        const key = try allocator.alloc(u8, 2);
        key[0] = 'a';
        key[1] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }
    defer for (keys.items) |k| allocator.free(k);

    for (keys.items) |k| {
        // try art.prettyPrint(allocator);
        try testing.expect(art.delete(allocator, k));
    }
}

test "handle deletes from a Node256 and shrinks correctly" {
    const allocator = testing.allocator;

    var art = AdaptiveRadixTree(u32).init(allocator);
    defer art.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    for (0..256) |i| {
        const key = try allocator.alloc(u8, 2);
        key[0] = 'a';
        key[1] = @intCast(i);

        try keys.append(allocator, key);
        try art.insert(allocator, key, @intCast(i));
    }
    defer for (keys.items) |k| allocator.free(k);

    for (keys.items) |k| {
        // try art.prettyPrint(allocator);
        try testing.expect(art.delete(allocator, k));
    }
}
