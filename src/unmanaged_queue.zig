const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const atomic = std.atomic;

/// A generic node used within the `UnmanagedQueue` to store data of type `T`.
///
/// This struct represents a single node in the queue. Each node contains data of type `T` and a
/// pointer to the next node in the queue (forming a linked list). The `next` pointer is nullable,
/// allowing nodes to be at the end of the list (in which case `next` will be `null`).
///
/// The `Node` struct is designed to be used with the `UnmanagedQueue` and is responsible for storing
/// individual elements and linking them together in the queue.
pub fn Node(comptime T: type) type {
    return struct {
        const Self = @This();

        data: T,
        next: ?*Self = null,

        pub fn new(data: T) Self {
            return Self{
                .data = data,
                .next = null,
            };
        }
    };
}

/// A generic queue implementation that stores nodes of type `Node(T)`.
///
/// This struct represents a queue that uses nodes to store data of type `T`. The queue is unmanaged,
/// meaning it does not perform automatic memory management (such as garbage collection) or allocator
/// handling for the nodes. It allows direct manipulation of the queue's internal state, including
/// the head, tail, and count.
///
/// The queue supports typical queue operations such as enqueue, dequeue, checking if it’s empty, and
/// resetting the queue. Nodes in the queue are linked through their `next` pointer, forming a chain of elements.
pub fn UnmanagedQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const NodeType = Node(T);

        /// Node at the front of the queue
        head: ?*Node(T),
        /// Node at the back of the queue
        tail: ?*Node(T),
        /// Property that tracks how many nodes are in the queue. This value is incremented/decremented as
        /// nodes are added or removed. Users should not directly modify this parameter.
        count: usize,

        pub fn new() Self {
            return Self{
                .head = null,
                .tail = null,
                .count = 0,
            };
        }

        /// Checks if the queue is empty.
        /// A queue is considered empty if the count of elements is zero, and both the head and tail are null.
        ///
        /// This function performs sanity checks to ensure that the count is consistent with the state
        /// of the queue (i.e., if the count is zero, both head and tail must be null, and if the count is
        /// greater than zero, neither head nor tail can be null). If the count is inconsistent with the
        /// actual state of the queue, an assertion will fail.
        pub fn isEmpty(self: *Self) bool {
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

        /// Enqueues a single node at the end of the queue.
        ///
        /// This function adds the specified `node` to the end (tail) of the queue. If the queue is empty,
        /// the node becomes both the head and the tail of the queue. Otherwise, the node is linked as the
        /// next node of the current tail, and the tail pointer is updated to point to the new node.
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

        /// Dequeues and returns the node at the front of the queue.
        ///
        /// This function removes the node from the front (head) of the queue and returns a pointer to it.
        /// The head pointer is updated to the next node in the queue, and the count is decremented.
        /// If the queue becomes empty after the dequeue, both the head and tail are set to null.
        ///
        /// If the queue is empty, the function returns `null`.
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

        /// Resets the queue by dropping all references to the nodes and clearing the state.
        ///
        /// This function removes all elements from the queue, effectively "emptying" it. Both the head
        /// and tail pointers are set to null, and the count is reset to zero. The queue is in an empty state
        /// after calling this function.
        ///
        /// **Note** this function does not unlink the nodes from each other.
        pub fn reset(self: *Self) void {
            if (self.isEmpty()) return;

            self.head = null;
            self.tail = null;
            self.count = 0;
        }

        /// Concatenates the given `other` queue to this queue (`self`).
        /// Assumes that `self` and `other` share the same allocator. This means no memory reallocation
        /// is performed; instead, the head and tail pointers are updated accordingly.
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

        /// Enqueues multiple nodes at once by linking them together in the queue.
        /// This function is used to enqueue a slice of nodes (`[]const *Node(T)`), where each node points to the next one.
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

        pub fn N(self: Self) type {
            _ = self;
            return Node(T);
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
