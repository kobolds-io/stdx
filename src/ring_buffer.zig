const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

pub const RingBufferError = error{
    BufferFull,
};

/// A simple ring buffer implementation that uses a backing buffer to efficiently
/// store and retrieve items in queue order. This version of the RingBuffer is
/// ideally suited for fixed size queues.
pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        const Iterator = struct {
            rb: *Self,
            index: usize = 0,

            /// Returns the next item in the ring buffer, or null when iteration is complete.
            pub fn next(it: *Iterator) ?*T {
                if (it.index >= it.rb.count) return null;

                const real_index = (it.rb.head + it.index) % it.rb.capacity;
                it.index += 1;
                return &it.rb.buffer[real_index];
            }
        };

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

        /// Prepend a single item at the `head` position of the ring buffer. If there
        /// is no available slot in the ring buffer `prepend` returns an error. Every
        /// prepended item increments the ring buffer `count`
        pub fn prepend(self: *Self, value: T) RingBufferError!void {
            if (self.isFull()) return RingBufferError.BufferFull;

            self.head = (self.head + self.capacity - 1) % self.capacity;
            self.buffer[self.head] = value;
            self.count += 1;
        }

        /// Enqueue a single item at the `tail` position of the ring buffer. If there
        /// is no available slot in the ring buffer `enqueue` returns an error. Every
        /// enqueued item increments the ring buffer `count`.
        pub fn enqueue(self: *Self, value: T) RingBufferError!void {
            if (self.isFull()) return RingBufferError.BufferFull;

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
        pub fn concatenate(self: *Self, other: *Self) !usize {
            if (self.available() < other.count) return RingBufferError.BufferFull;

            const capacity = self.capacity;

            var count: usize = 0;
            while (count < other.count) : (count += 1) {
                const index = (other.head + count) % capacity;
                const value = other.buffer[index];
                self.buffer[self.tail] = value;
                self.tail = (self.tail + 1) % capacity;
            }

            self.count += other.count;
            other.reset();

            return count;
        }

        /// Concatenate as many items as possible from another ring buffer into this one.
        ///
        /// This method appends up to `self.available()` elements from the `other` ring buffer
        /// into `self`, preserving the order of items as they appeared in `other`.
        /// Only the number of items that can fit in `self` will be copied.
        /// The operation is destructive to `other`—copied items are removed from it.
        pub fn concatenateAvailable(self: *Self, other: *Self) usize {
            const num_to_copy = @min(self.available(), other.count);

            var count: usize = 0;
            while (count < num_to_copy) : (count += 1) {
                const index = (other.head + count) % other.capacity;
                const value = other.buffer[index];
                self.buffer[self.tail] = value;
                self.tail = (self.tail + 1) % self.capacity;
            }

            self.count += num_to_copy;
            other.head = (other.head + num_to_copy) % other.capacity;
            other.count -= num_to_copy;

            return count;
        }

        /// Copy the contents of another ring buffer into this one while preserving
        /// the contents in the `other` ring buffer.
        ///
        /// This method appends all the elements from `other` ring buffer into `self`,
        /// preserving both the order of the items as they appeared in `other` as well
        /// and the contents of `other`.
        /// This operation is not destructive to `other`
        pub fn copy(self: *Self, other: *Self) !usize {
            if (self.available() < other.count) return RingBufferError.BufferFull;

            var count: usize = 0;
            while (count < other.count) : (count += 1) {
                const index = (other.head + count) % other.capacity;
                self.buffer[self.tail] = other.buffer[index];
                self.tail = (self.tail + 1) % self.capacity;
            }

            self.count += other.count;

            return count;
        }

        /// Copies the minimum number of available items from `self` to all `others`.
        ///
        /// The number of items copied is the minimum of:
        /// - the number of items currently in `self`
        /// - the available space in each target buffer (smallest available among them)
        ///
        /// All target buffers receive the same copied items. The copied items are removed from `self`.
        /// Returns the number of items successfully copied.
        pub fn copyMinToOthers(self: *Self, others: []*Self) usize {
            if (others.len == 0 or self.count == 0) return 0;

            // Find the smallest available space among all receivers
            var min_available = std.math.maxInt(usize);
            for (others) |other| {
                const other_available = other.available();
                if (other_available < min_available) {
                    min_available = other_available;
                }
            }

            const num_to_copy = @min(self.count, min_available);
            if (num_to_copy == 0) return 0;

            // Copy items from self to each other
            var i: usize = 0;
            while (i < num_to_copy) : (i += 1) {
                const index = (self.head + i) % self.capacity;
                const value = self.buffer[index];

                for (others) |other| {
                    other.buffer[other.tail] = value;
                    other.tail = (other.tail + 1) % other.capacity;
                    other.count += 1;
                }
            }

            // Advance self
            self.head = (self.head + num_to_copy) % self.capacity;
            self.count -= num_to_copy;

            return num_to_copy;
        }

        /// Copies as many items as possible from `self` to all `others`.
        ///
        /// The number of items copied is the maximum number such that:
        /// - each target buffer can accommodate that many items
        /// - self has at least that many items
        ///
        /// All target buffers receive the same copied items.
        /// The copied items are removed from `self`.
        /// Returns the number of items copied to each target.
        pub fn copyMaxToOthers(self: *Self, others: []*Self) usize {
            if (others.len == 0 or self.count == 0) return 0;

            // Determine how many items each other buffer can accept
            var max_copy = self.count;

            for (others) |other| {
                const other_available = other.available();
                if (other_available < max_copy) {
                    max_copy = other_available;
                }
            }

            if (max_copy == 0) return 0;

            // Copy items from self to each other
            var i: usize = 0;
            while (i < max_copy) : (i += 1) {
                const index = (self.head + i) % self.capacity;
                const value = self.buffer[index];

                for (others) |other| {
                    other.buffer[other.tail] = value;
                    other.tail = (other.tail + 1) % other.capacity;
                    other.count += 1;
                }
            }

            // Advance self
            self.head = (self.head + max_copy) % self.capacity;
            self.count -= max_copy;

            return max_copy;
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

        /// Return an iterator for the ring buffer. Handles the wrap around
        /// nature of the ring buffer.
        pub fn iterator(self: *Self) Iterator {
            return Iterator{ .rb = self };
        }

        /// View an item at a specific index in the ring buffer. Handles the
        /// wrap around nature of the ring buffer.
        pub fn peek(self: *Self, index: usize) ?T {
            if (index > self.count) return null;

            const real_index = (self.head + index) % self.capacity;
            return self.buffer[real_index];
        }

        /// Reorder the items in the ring buffer where the head is now at index 0 and the tail is moved to the last
        /// index in the current list
        pub fn linearize(self: *Self) void {
            if (self.count <= 1) return;

            if (self.head > 0) {
                var tmp: T = undefined;
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    const src_index = (self.head + i) % self.capacity;
                    const dst_index = i;
                    if (src_index != dst_index) {
                        tmp = self.buffer[src_index];
                        self.buffer[dst_index] = tmp;
                    }
                }
                self.head = 0;
                self.tail = self.count;
            }
        }

        /// Sort the contents of the ring buffer. The items are first linearized, see RingBuffer.linearize(), and then
        /// sorted using the block function. Takes a custom comparator to allow for custom item sorting.
        pub fn sort(self: *Self, comptime comparator: fn (_: void, left: T, right: T) bool) void {
            if (self.count <= 1) return;

            self.linearize();

            std.sort.block(T, self.buffer[0..self.count], {}, comparator);
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

test "prepend" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;

    // fill the remaining capacity of the ring buffer with this value
    ring_buffer.fill(33);
    try testing.expectEqual(0, ring_buffer.available());

    // Make room in the ring_buffer
    try testing.expectEqual(33, ring_buffer.dequeue().?);
    try testing.expectEqual(1, ring_buffer.available());

    try ring_buffer.prepend(test_value);

    try testing.expectEqual(0, ring_buffer.available());

    try testing.expectEqual(true, ring_buffer.isFull());
    try testing.expectError(RingBufferError.BufferFull, ring_buffer.prepend(test_value));

    // dequeue the item at the had of the queue
    try testing.expectEqual(test_value, ring_buffer.dequeue().?);
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
    try testing.expectError(RingBufferError.BufferFull, ring_buffer.enqueue(test_value));
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

    const expected_items_concatenated = b.count;
    const items_concatenated = try a.concatenate(&b);
    try testing.expectEqual(expected_items_concatenated, items_concatenated);

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
    const n = try dest.copy(&src);

    // ensure that the dest.count increased by n
    try testing.expectEqual(n, dest.count);

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
    try testing.expectError(RingBufferError.BufferFull, result);

    // Destination should still be empty
    try testing.expectEqual(true, dest.isEmpty());
}

test "iterator functionality" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 5);
    defer ring_buffer.deinit();

    try ring_buffer.enqueue(1);
    try ring_buffer.enqueue(2);
    try ring_buffer.enqueue(3);
    try ring_buffer.enqueue(4);
    try ring_buffer.enqueue(5);

    _ = ring_buffer.dequeue();
    try ring_buffer.enqueue(1);

    const expected = [_]u8{ 2, 3, 4, 5, 1 };

    var iter = ring_buffer.iterator();
    var index: usize = 0;

    while (iter.next()) |v| {
        try testing.expect(index < expected.len);
        try testing.expectEqual(expected[index], v.*);
        index += 1;
    }

    try testing.expectEqual(expected.len, index);
}

test "peeking" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 3);
    defer ring_buffer.deinit();

    try ring_buffer.enqueue(1);
    try ring_buffer.enqueue(2);
    try ring_buffer.enqueue(3);

    try testing.expectEqual(1, ring_buffer.peek(0).?);
    try testing.expectEqual(2, ring_buffer.peek(1).?);
    try testing.expectEqual(3, ring_buffer.peek(ring_buffer.count - 1).?);
}

test "sorting" {
    const run_test = struct {
        fn testIntComparator(_: void, left: u8, right: u8) bool {
            return left < right;
        }

        const TestStruct = struct {
            data: u32 = 0,
        };

        fn testStructComparator(_: void, left: TestStruct, right: TestStruct) bool {
            return left.data < right.data;
        }

        pub fn runner() !void {
            const allocator = testing.allocator;

            var ring_buffer_1 = try RingBuffer(u8).init(allocator, 3);
            defer ring_buffer_1.deinit();

            try ring_buffer_1.enqueue(3);
            try ring_buffer_1.enqueue(2);
            try ring_buffer_1.enqueue(1);

            try testing.expectEqual(3, ring_buffer_1.count);
            try testing.expectEqual(3, ring_buffer_1.peek(0).?);
            try testing.expectEqual(2, ring_buffer_1.peek(1).?);
            try testing.expectEqual(1, ring_buffer_1.peek(2).?);

            ring_buffer_1.sort(testIntComparator);

            try testing.expectEqual(3, ring_buffer_1.count);
            try testing.expectEqual(1, ring_buffer_1.peek(0).?);
            try testing.expectEqual(2, ring_buffer_1.peek(1).?);
            try testing.expectEqual(3, ring_buffer_1.peek(2).?);

            // try sorting a more complex data type
            var ring_buffer_2 = try RingBuffer(TestStruct).init(allocator, 3);
            defer ring_buffer_2.deinit();

            try ring_buffer_2.enqueue(.{ .data = 10 });
            try ring_buffer_2.enqueue(.{ .data = 29 });
            try ring_buffer_2.enqueue(.{ .data = 2 });

            try testing.expectEqual(3, ring_buffer_2.count);
            try testing.expectEqual(10, ring_buffer_2.peek(0).?.data);
            try testing.expectEqual(29, ring_buffer_2.peek(1).?.data);
            try testing.expectEqual(2, ring_buffer_2.peek(2).?.data);

            ring_buffer_2.sort(testStructComparator);

            try testing.expectEqual(3, ring_buffer_2.count);
            try testing.expectEqual(2, ring_buffer_2.peek(0).?.data);
            try testing.expectEqual(10, ring_buffer_2.peek(1).?.data);
            try testing.expectEqual(29, ring_buffer_2.peek(2).?.data);
        }
    }.runner;

    try run_test();
}
