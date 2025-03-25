const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const ManagedQueue = stdx.ManagedQueue;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // initialize a managed queue of i32s
    var managed_queue = ManagedQueue(i32).init(allocator);

    defer managed_queue.deinit();

    // enqueue an item into the queue
    try managed_queue.enqueue(123);

    // ensure that there is only 1 item in the queue
    assert(managed_queue.count == 1);

    // dequeue an item from the queue
    const dequeued_item = managed_queue.dequeue().?;

    // ensure that the dequeued item was actually the same item enqueued
    assert(dequeued_item == 123);

    assert(managed_queue.isEmpty());

    // trying to dequeue another item from the queue results in null
    assert(managed_queue.dequeue() == null);
}
