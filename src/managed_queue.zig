const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

/// The ManagedQueue is a generic queue implementation in Zig that uses a
/// singly linked list. It allows for the management of a queue with operations
/// like enqueueing, dequeueing, checking if the queue is empty, concatenating
/// two queues, and deallocating memory used by the queue. The queue is managed
/// by an allocator, which is used for creating and destroying nodes.
pub fn ManagedQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            const Self = @This();

            data: T,
            next: ?*Node = null,

            pub fn new(data: T) Node {
                return Node{
                    .data = data,
                    .next = null,
                };
            }
        };

        allocator: std.mem.Allocator,
        head: ?*Node,
        tail: ?*Node,
        count: u32,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .head = null,
                .tail = null,
                .count = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            // deallocate all items in the queue
            while (self.dequeueNode()) |node| {
                self.allocator.destroy(node);
            }

            assert(self.head == null);
            assert(self.tail == null);
            assert(self.count == 0);
        }

        /// Return true if the managed queue `count` is 0
        /// Return false if the managed queue > 0 has at least 1 item within.
        ///
        /// Additionally, this validates that the queue is truely empty
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

        /// Adds a new element to the end of the queue. A new Node is created with the
        /// provided data and added to the end of the queue. The count is incremented
        /// after adding the element.
        pub fn enqueue(self: *Self, data: T) !void {
            // create a new node
            const node = try self.allocator.create(Node);
            errdefer self.allocator.destroy(node);

            node.* = Node{
                .data = data,
                .next = null,
            };

            // append the new node to the end of the queue
            {
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
        }

        /// Dequeue a single item from the `head` position of the managed queue. If the
        /// managed queue is empty `dequeue` returns null. Every dequeued item decrements
        /// the managed queue `count`.
        pub fn dequeue(self: *Self) ?T {
            if (self.isEmpty()) return null;

            // we know that there is at least one item in the queue
            const n = self.head.?;

            // capture the data
            const data = n.data;

            // set the head of the queue to the next item
            self.head = n.next;

            // if there are no more items in the queue, zero out the queue
            if (self.head == null) {
                self.tail = null;
            }

            // decrement the count
            self.count -= 1;

            // deallocate the node
            self.allocator.destroy(n);

            return data;
        }

        /// internal function used to deliberately dequeue and return the node explicitly
        fn dequeueNode(self: *Self) ?*Node {
            if (self.isEmpty()) return null;

            // we know that there is at least one item in the queue
            const n = self.head.?;

            // set the head of the queue to the next item
            self.head = n.next;

            // if there are no more items in the queue, zero out the queue
            if (self.head == null) {
                self.tail = null;
            }

            // decrement the count
            self.count -= 1;

            return n;
        }

        /// Concatenates another queue (other) to the current queue (self). This operation appends
        /// all elements from the other queue to the self queue.
        ///
        /// **Note** This version of concatentate assumes that this and the other queue share the
        /// same allocator.
        pub fn concatenate(self: *Self, other: *Self) void {
            // we should just panic if this isn't the case
            if (self.allocator.ptr != other.allocator.ptr) {
                @panic("Cannot concatenate queues with different allocators");
            }

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
    };
}

test "enqueue/dequeue" {
    const allocator = testing.allocator;

    var q = ManagedQueue(u8).init(allocator);
    defer q.deinit();

    try q.enqueue(1);
    try q.enqueue(2);
    try q.enqueue(3);

    try testing.expectEqual(3, q.count);

    while (q.dequeue()) |_| {}

    try testing.expectEqual(0, q.count);
}

test "concatenating two queues" {
    const allocator = testing.allocator;

    var q1 = ManagedQueue(u8).init(allocator);
    defer q1.deinit();

    var q2 = ManagedQueue(u8).init(allocator);
    defer q2.deinit();

    try q1.enqueue(1);
    try q1.enqueue(2);
    try q1.enqueue(3);
    try q1.enqueue(4);
    try q1.enqueue(5);

    try q2.enqueue(6);
    try q2.enqueue(7);
    try q2.enqueue(8);
    try q2.enqueue(9);
    try q2.enqueue(10);

    try testing.expectEqual(5, q1.count);
    try testing.expectEqual(5, q2.count);

    q1.concatenate(&q2);

    try testing.expectEqual(10, q1.count);
    try testing.expectEqual(0, q2.count);

    // loop over each item in the queue and verify that everything was added in order
    var i: u8 = 1;
    while (q1.dequeue()) |d| : (i += 1) {
        try testing.expectEqual(i, d);
    }

    try testing.expectEqual(10, i - 1);
}
