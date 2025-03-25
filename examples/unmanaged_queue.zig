const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const UnmanagedQueue = stdx.UnmanagedQueue;
const Node = stdx.UnmanagedQueueNode;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // initialize an unmanaged queue of i32s
    var unmanaged_queue = UnmanagedQueue(i32).new();

    for (0..100) |i| {
        // allocate the node outside of the control of the unmanaged queue
        const n = try allocator.create(Node(i32));
        errdefer allocator.destroy(n);

        // set the value of this pointer
        n.* = Node(i32).new(@intCast(i));

        // add this node to the queue
        unmanaged_queue.enqueue(n);
    }

    assert(unmanaged_queue.count == 100);

    // remove all the items from the queue
    while (unmanaged_queue.dequeue()) |node| {
        allocator.destroy(node);
    }

    // ensure that the queue is completely empty
    assert(unmanaged_queue.isEmpty());

    // trying to dequeue another item from the queue results in null
    assert(unmanaged_queue.dequeue() == null);
}
