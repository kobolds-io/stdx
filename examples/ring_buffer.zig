const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const RingBuffer = stdx.RingBuffer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a basic ring buffer
    var ring_buffer = try RingBuffer(u64).init(allocator, 100);
    defer ring_buffer.deinit();

    // Enqueue a single item
    const first_value: u64 = 10;
    try ring_buffer.enqueue(first_value);

    assert(ring_buffer.count == 1);

    // Enqueue many items
    const values: [3]u64 = [_]u64{9999} ** 3;
    const enqueued_count = ring_buffer.enqueueMany(&values);

    assert(enqueued_count == values.len);

    // fill the remaining capacity of the ring buffer
    ring_buffer.fill(4321);

    assert(ring_buffer.available() == 0);

    // dequeue a single item from the ring buffer
    const v = ring_buffer.dequeue();
    assert(first_value == v);

    // dequeue many items from the queue
    var out: [2]u64 = [_]u64{0} ** 2;
    const dequeued_items_count = ring_buffer.dequeueMany(&out);

    assert(dequeued_items_count == out.len);

    const new_head_value: u64 = 8601;
    assert(ring_buffer.count > 0);

    // prepend an item
    try ring_buffer.prepend(new_head_value);

    // dequeue the head item
    assert(new_head_value == ring_buffer.dequeue().?);

    // reset the ring buffer
    ring_buffer.reset();

    assert(ring_buffer.isEmpty());
}
