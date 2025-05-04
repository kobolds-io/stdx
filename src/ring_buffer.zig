const std = @import("std");
const testing = std.testing;

pub const Error = error{
    BufferFull,
};

/// A simple ring buffer implementation that uses a backing buffer to efficiently
/// store and retrieve items in queue order. This version of the RingBuffer is
/// ideally suited for fixed size queues.
pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        /// allocator used to `alloc` the `buffer`. This allocator should have a
        /// lifetime longer than the ring buffer.
        allocator: std.mem.Allocator,
        /// total number of slots created during creation. The size of the `buffer`
        /// allocated during `init` is equal to the `capacity`.
        capacity: usize,
        /// backing buffer used to store the values of the ring buffer.
        buffer: []T,
        /// track the start of the ring buffer slots.
        head: usize,
        /// track the end of the ring buffer slots.
        tail: usize,
        /// current number of items occupying slots
        count: usize,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            const buffer = try allocator.alloc(T, capacity);
            errdefer allocator.free(buffer);

            return Self{
                .allocator = allocator,
                .capacity = capacity,
                .buffer = buffer,
                .head = 0,
                .tail = 0,
                .count = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
        }

        /// return the number of available slots remaining in the ring buffer. An
        /// available slot is a slot in which no tracked value is assigned.
        pub fn available(self: *Self) usize {
            return self.capacity - self.count;
        }

        /// Enqueue a single item at the `tail` position of the ring buffer. If there
        /// is no available slot in the ring buffer `enqueue` returns an error. Every
        /// enqueued item increments the ring buffer `count`.
        pub fn enqueue(self: *Self, value: T) Error!void {
            if (self.isFull()) {
                return Error.BufferFull;
            }

            self.buffer[self.tail] = value;
            self.tail = (self.tail + 1) % self.capacity;
            self.count += 1;
        }

        /// Dequeue a single item from the `head` position of the ring buffer. If the
        /// ring buffer is empty `dequeue` returns null. Every dequeued item decrements
        /// the ring buffer `count`.
        pub fn dequeue(self: *Self) ?T {
            if (self.isEmpty()) return null;

            const value = self.buffer[self.head];
            self.head = (self.head + 1) % self.capacity;
            self.count -= 1;
            return value;
        }

        /// Enqueue multiple items into the ring buffer. If the length of the `values`
        /// slice exeeds the available slots in the ring buffer, then only the maximum
        /// items will be added without exceeding the capacity of the ring buffer.
        /// `enqueueMany` returns the number of items inserted into the ring buffer.
        pub fn enqueueMany(self: *Self, values: []const T) usize {
            var added_count: usize = 0;
            for (values) |value| {
                if (self.isFull()) break;

                self.buffer[self.tail] = value;
                self.tail = (self.tail + 1) % self.capacity;
                self.count += 1;
                added_count += 1;
            }

            return added_count;
        }

        /// Dequeue multiple items from the ring buffer. Take every dequeued
        /// item and append it to the `out` slice. `dequeueMany` returns the number of items
        /// appended to the `out` slice.
        ///
        /// **Note** As a maximum, `dequeueMany` will only dequeue as many items
        /// can fit within the capacity of the `out` slice.
        pub fn dequeueMany(self: *Self, out: []T) usize {
            var removed_count: usize = 0;
            for (out) |*slot| {
                if (self.isEmpty()) break;

                slot.* = self.buffer[self.head];
                self.head = (self.head + 1) % self.capacity;
                self.count -= 1;
                removed_count += 1;
            }

            return removed_count;
        }

        /// Concatenate the contents of another ring buffer into this one.
        ///
        /// This method appends all elements from the `other` ring buffer into `self`,
        /// preserving the order of items as they appeared in `other`.
        /// The operation is destructive to `other`
        pub fn concatenate(self: *Self, other: *Self) !void {
            if (self.available() < other.count) return Error.BufferFull;

            const capacity = self.capacity;

            var i: usize = 0;
            while (i < other.count) : (i += 1) {
                const index = (other.head + i) % capacity;
                const value = other.buffer[index];
                self.buffer[self.tail] = value;
                self.tail = (self.tail + 1) % capacity;
            }

            self.count += other.count;
            other.reset();
        }

        /// Concatenate as many items as possible from another ring buffer into this one.
        ///
        /// This method appends up to `self.available()` elements from the `other` ring buffer
        /// into `self`, preserving the order of items as they appeared in `other`.
        /// Only the number of items that can fit in `self` will be copied.
        /// The operation is destructive to `other`—copied items are removed from it.
        pub fn concatenateAvailable(self: *Self, other: *Self) void {
            const num_to_copy = @min(self.available(), other.count);

            var i: usize = 0;
            while (i < num_to_copy) : (i += 1) {
                const index = (other.head + i) % other.capacity;
                const value = other.buffer[index];
                self.buffer[self.tail] = value;
                self.tail = (self.tail + 1) % self.capacity;
            }

            self.count += num_to_copy;
            other.head = (other.head + num_to_copy) % other.capacity;
            other.count -= num_to_copy;
        }

        /// Copy the contents of another ring buffer into this one while preserving
        /// the contents in the `other` ring buffer.
        ///
        /// This method appends all the elements from `other` ring buffer into `self`,
        /// preserving both the order of the items as they appeared in `other` as well
        /// and the contents of `other`.
        /// This operation is not destructive to `other`
        pub fn copy(self: *Self, other: *Self) !void {
            if (self.available() < other.count) return Error.BufferFull;

            var i: usize = 0;
            while (i < other.count) : (i += 1) {
                const index = (other.head + i) % other.capacity;
                self.buffer[self.tail] = other.buffer[index];
                self.tail = (self.tail + 1) % self.capacity;
            }

            self.count += other.count;
        }

        /// Return true if the all slots are available
        /// Return false if the ring buffer has at least 1 item within.
        pub fn isEmpty(self: *Self) bool {
            return self.available() == self.capacity;
        }

        /// Return true if the ring buffer has no slots available.
        /// Return false if the ring buffer has at least 1 slot available.
        pub fn isFull(self: *Self) bool {
            return self.available() == 0;
        }

        /// unsafely reset the ring buffer to simply drop all items within
        pub fn reset(self: *Self) void {
            self.head = 0;
            self.tail = 0;
            self.count = 0;
        }

        /// fill the ring buffer's remaining available slots with `value`.
        pub fn fill(self: *Self, value: T) void {
            for (0..self.available()) |_| {
                self.enqueue(value) catch unreachable;
            }
        }
    };
}

test "init/deinit" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 100);
    defer ring_buffer.deinit();
}

test "fill" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 100);
    defer ring_buffer.deinit();

    // Assert that the ring buffer is completely empty with no items in any slots.
    try testing.expectEqual(true, ring_buffer.isEmpty());

    const test_value: u8 = 231;

    ring_buffer.fill(test_value);

    // Assert that the ring buffer is completely full with no free slots
    try testing.expectEqual(true, ring_buffer.isFull());

    // dequeue every value and ensure that they are each equal to the test_value
    while (ring_buffer.dequeue()) |v| {
        try testing.expectEqual(test_value, v);
    }

    // Assert that the ring buffer is completely empty with no items in any slots.
    try testing.expectEqual(true, ring_buffer.isEmpty());
}

test "reset" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 100);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;

    ring_buffer.fill(test_value);

    // Assert that the ring buffer is completely full with no free slots
    try testing.expectEqual(true, ring_buffer.isFull());

    // ensure that every value in the backing buffer is equal to the test_value
    for (ring_buffer.buffer) |value| {
        try testing.expectEqual(test_value, value);
    }

    // fully reset the ring buffer. Since this is an unsafe operation we
    // should expect that all values in the buffer still are equal to the
    // test value used during the fill op
    ring_buffer.reset();

    // Assert that the ring buffer is completely empty with no items in any slots.
    try testing.expectEqual(true, ring_buffer.isEmpty());

    for (ring_buffer.buffer) |value| {
        try testing.expectEqual(test_value, value);
    }
}

test "enqueue" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;

    try testing.expectEqual(0, ring_buffer.count);

    try ring_buffer.enqueue(test_value);

    try testing.expectEqual(1, ring_buffer.count);

    // fill the remaining capacity of the ring buffer with this value
    ring_buffer.fill(33);

    try testing.expectEqual(true, ring_buffer.isFull());
    try testing.expectError(Error.BufferFull, ring_buffer.enqueue(test_value));
}

test "dequeue" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;

    // fill the entire ring buffer with this value
    ring_buffer.fill(test_value);

    try testing.expectEqual(true, ring_buffer.isFull());

    var removed: usize = ring_buffer.capacity;
    while (ring_buffer.dequeue()) |v| : (removed -= 1) {
        try testing.expectEqual(test_value, v);
    }

    try testing.expectEqual(true, ring_buffer.isEmpty());
}

test "enqueueMany" {
    const allocator = testing.allocator;

    const test_value: u8 = 231;
    const values: [13]u8 = [_]u8{test_value} ** 13;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    try testing.expectEqual(true, ring_buffer.isEmpty());

    const enqueued_items_count = ring_buffer.enqueueMany(&values);

    try testing.expectEqual(ring_buffer.capacity, enqueued_items_count);
    try testing.expectEqual(true, ring_buffer.isFull());
}

test "dequeueMany" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;
    ring_buffer.fill(test_value);

    try testing.expectEqual(true, ring_buffer.isFull());

    var out: [100]u8 = [_]u8{0} ** 100;
    const dequeued_items_count = ring_buffer.dequeueMany(&out);

    try testing.expectEqual(true, ring_buffer.isEmpty());

    try testing.expect(dequeued_items_count > 0);

    for (out[0..dequeued_items_count]) |v| {
        try testing.expectEqual(test_value, v);
    }
}

test "concatenate" {
    const allocator = std.testing.allocator;
    var a = try RingBuffer(usize).init(allocator, 10);
    defer a.deinit();

    var b = try RingBuffer(usize).init(allocator, 5);
    defer b.deinit();

    _ = a.enqueueMany(&.{ 1, 2, 3 });
    _ = b.enqueueMany(&.{ 4, 5 });

    try a.concatenate(&b);

    try testing.expectEqual(@as(usize, 5), a.count);
    try testing.expectEqual(@as(usize, 0), b.count);

    var buf: [5]usize = undefined;
    const n = a.dequeueMany(&buf);
    try testing.expectEqualSlices(usize, &.{ 1, 2, 3, 4, 5 }, buf[0..n]);
}

test "copy preserves other and copies all values in order" {
    const allocator = testing.allocator;

    var src = try RingBuffer(u8).init(allocator, 10);
    defer src.deinit();

    var dest = try RingBuffer(u8).init(allocator, 10);
    defer dest.deinit();

    // Fill the source buffer with predictable values
    const values: [5]u8 = .{ 10, 20, 30, 40, 50 };
    try testing.expectEqual(@as(usize, values.len), src.enqueueMany(&values));

    // Ensure destination is empty before copy
    try testing.expectEqual(true, dest.isEmpty());

    // Perform the copy
    try dest.copy(&src);

    // Ensure source is unchanged after copy
    try testing.expectEqual(@as(usize, values.len), src.count);

    for (values) |expected| {
        const actual = src.dequeue().?;
        try testing.expectEqual(expected, actual);
    }

    // Re-enqueue the values into source for the next check
    _ = src.enqueueMany(&values);

    // Now check that dest has the same values, in same order
    for (values) |expected| {
        const actual = dest.dequeue().?;
        try testing.expectEqual(expected, actual);
    }

    try testing.expectEqual(true, dest.isEmpty());
    try testing.expectEqual(@as(usize, values.len), src.count);
}

test "copy fails when not enough space in destination" {
    const allocator = testing.allocator;

    var src = try RingBuffer(u8).init(allocator, 5);
    defer src.deinit();

    var dest = try RingBuffer(u8).init(allocator, 3);
    defer dest.deinit();

    // Fill source with 5 values
    src.fill(7);

    // Try copying into a smaller destination
    const result = dest.copy(&src);
    try testing.expectError(Error.BufferFull, result);

    // Destination should still be empty
    try testing.expectEqual(true, dest.isEmpty());
}
