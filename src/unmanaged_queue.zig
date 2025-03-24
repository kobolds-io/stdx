const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const atomic = std.atomic;

pub fn Node(comptime T: type) type {
    return struct {
        const Self = @This();

        data: T,
        next: ?*Self = null,

        ref_count: atomic.Value(u32),

        pub fn new(data: T) Self {
            return Self{
                .data = data,
                .next = null,
                .ref_count = atomic.Value(u32).init(0),
            };
        }

        pub fn refs(self: *Self) u32 {
            return self.ref_count.load(.seq_cst);
        }

        pub fn ref(self: *Self) void {
            _ = self.ref_count.fetchAdd(1, .seq_cst);
        }

        pub fn deref(self: *Self) void {
            const v = self.ref_count.load(.seq_cst);
            if (v == 0) return;
            _ = self.ref_count.cmpxchgWeak(v, v - 1, .seq_cst, .seq_cst);
        }
    };
}

pub fn UnmanagedQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const NodeType = Node(T);

        head: ?*Node(T),
        tail: ?*Node(T),
        count: u32,

        pub fn new() Self {
            return Self{
                .head = null,
                .tail = null,
                .count = 0,
            };
        }

        fn isEmpty(self: *Self) bool {
            if (self.count == 0) {
                assert(self.head == null);
                assert(self.tail == null);
                return true;
            }

            // if one of these fail, that means that the count is borked and we have a
            // logic error somewhere in one of the operations so someone has modified
            // the count outside of the queue
            assert(self.head != null);
            assert(self.tail != null);

            return false;
        }

        pub fn enqueue(self: *Self, node: *Node(T)) void {

            // always increment the count after this block
            defer self.count += 1;

            // handle the case the list is empty;
            if (self.isEmpty()) {
                self.head = node;
                self.tail = node;
                return;
            }

            // we know that the tail is not null here;
            var temp_tail = self.tail.?;
            temp_tail.next = node;
            self.tail = node;
        }

        pub fn dequeue(self: *Self) ?*Node(T) {
            if (self.isEmpty()) return null;

            // we know that there is at least one item in the queue
            const node = self.head.?;

            // set the head of the queue to the next item
            self.head = node.next;

            // decrement the count
            self.count -= 1;

            // ensure that the head and tail are both nulled
            if (self.count == 0) {
                self.head = null;
                self.tail = null;
            }

            return node;
        }

        /// drop all references to all nodes and unwind the queue
        pub fn reset(self: *Self) void {
            if (self.isEmpty()) return;

            self.head = null;
            self.tail = null;
            self.count = 0;
        }

        /// This version of concatentate assumes that this and the other queue share the same allocator.
        pub fn concatenate(self: *Self, other: *Self) void {
            if (other.isEmpty()) return; // No need to do anything if the other queue is empty

            if (self.isEmpty()) {
                // If `self` is empty, just take `other`'s head and tail
                self.head = other.head;
                self.tail = other.tail;
            } else {
                // Link `self.tail` to `other.head`
                self.tail.?.next = other.head;
                self.tail = other.tail;
            }

            // Update the count
            self.count += other.count;

            // Reset the `other` queue
            other.head = null;
            other.tail = null;
            other.count = 0;
        }

        /// Enqueue many messages at a time. This is faster than calling enqueue one at a time
        pub fn enqueueMany(self: *Self, nodes: []const *Node(T)) void {

            // do nothing if the incoming messages is actually empty
            if (nodes.len == 0) return;

            // we are just going to loop over each message and assign next to the next message
            var current: *Node(T) = undefined;
            for (0..nodes.len) |i| {
                current = nodes[i];
                if (i + 1 < nodes.len) {
                    current.next = nodes[i + 1];
                }
            }

            // handle the case where the head is empty
            if (self.isEmpty()) {
                self.head = nodes[0];
            }

            // increase the count by the enqueue messages count
            self.count += @intCast(nodes.len);

            // set the tail to the last message
            self.tail = nodes[nodes.len - 1];
        }
    };
}

test "enqueue/dequeue" {
    var q = UnmanagedQueue(u8).new();

    var n1 = Node(u8).new(1);
    var n2 = Node(u8).new(2);
    var n3 = Node(u8).new(3);

    q.enqueue(&n1);
    q.enqueue(&n2);
    q.enqueue(&n3);

    try testing.expectEqual(3, q.count);

    while (q.dequeue()) |_| {}

    try testing.expectEqual(0, q.count);
}

test "concatenating two queues" {
    var q1 = UnmanagedQueue(u8).new();
    var q2 = UnmanagedQueue(u8).new();

    var n0 = Node(u8).new(0);
    var n1 = Node(u8).new(1);
    var n2 = Node(u8).new(2);

    var n3 = Node(u8).new(3);
    var n4 = Node(u8).new(4);
    var n5 = Node(u8).new(5);

    q1.enqueue(&n0);
    q1.enqueue(&n1);
    q1.enqueue(&n2);
    q2.enqueue(&n3);
    q2.enqueue(&n4);
    q2.enqueue(&n5);

    try testing.expectEqual(3, q1.count);
    try testing.expectEqual(3, q2.count);

    q1.concatenate(&q2);

    try testing.expectEqual(6, q1.count);
    try testing.expectEqual(0, q2.count);

    // loop over each item in the queue and verify that everything was added in order
    var i: u8 = 0;
    while (q1.dequeue()) |node| : (i += 1) {
        try testing.expectEqual(i, node.data);
    }

    try testing.expectEqual(6, i);
}
