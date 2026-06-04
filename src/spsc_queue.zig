const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

pub fn SPSCQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        head: usize align(64) = 0,
        tail: usize align(64) = 0,
        buffer: []T,
        capacity: usize,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            // ensure that capacity is non-zero and a power of 2
            // NOTE: this is kind of a cool programmer formula to just plug into a calculator and see work ;)
            if ((capacity == 0) or (capacity & (capacity - 1)) != 0) {
                return error.CapacityMustBeNonZeroPowerOfTwo;
            }

            const buf = try allocator.alloc(T, capacity);
            errdefer allocator.free(buf);

            return Self{
                .buffer = buf,
                .head = 0,
                .tail = 0,
                .capacity = capacity,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.buffer);
        }

        pub fn push(self: *Self, item: T) bool {
            const tail = @atomicLoad(usize, &self.tail, .monotonic);
            const next = tail + 1;

            if (next - @atomicLoad(usize, &self.head, .acquire) > self.capacity) {
                // queue is full
                return false;
            }

            // item is stored in the buffer
            self.buffer[tail & (self.capacity - 1)] = item;
            @atomicStore(usize, &self.tail, next, .release);
            return true;
        }

        pub fn pop(self: *Self) ?T {
            const head = @atomicLoad(usize, &self.head, .monotonic);
            if (head == @atomicLoad(usize, &self.tail, .acquire)) {
                // the queue is empty
                return null;
            }

            // item is found
            const item = self.buffer[head & (self.capacity - 1)];
            @atomicStore(usize, &self.head, head + 1, .release);
            return item;
        }
    };
}

test "single threaded push/pop" {
    const allocator = testing.allocator;
    var q = try SPSCQueue(i32).init(allocator, 16);
    defer q.deinit(allocator);

    const ok = q.push(123);
    try testing.expectEqual(true, ok);
    try testing.expectEqual(123, q.pop());
    try testing.expectEqual(null, q.pop());
}

test "single threaded full" {
    const allocator = testing.allocator;

    const capacity = 8;

    var q = try SPSCQueue(i32).init(allocator, capacity);
    defer q.deinit(allocator);

    // fill up the buffer
    for (0..capacity) |_| try testing.expectEqual(true, q.push(123));

    try testing.expectEqual(false, q.push(123));
}

test "single threaded empty" {
    const allocator = testing.allocator;

    const capacity = 8;
    const val: i32 = 123;

    var q = try SPSCQueue(i32).init(allocator, capacity);
    defer q.deinit(allocator);

    // fill up the buffer
    for (0..capacity) |_| try testing.expectEqual(true, q.push(val));
    // empty the buffer
    for (0..capacity) |_| try testing.expectEqual(val, q.pop());

    try testing.expectEqual(null, q.pop());
}

test "spsc threaded producer consumer" {
    const allocator = testing.allocator;
    const capacity = 1024;
    const total_items = 1_000_000;

    var q = try SPSCQueue(u64).init(allocator, capacity);
    defer q.deinit(allocator);

    const Producer = struct {
        fn run(queue: *SPSCQueue(u64)) void {
            var i: u64 = 0;
            while (i < total_items) {
                if (queue.push(i)) {
                    i += 1;
                }
                // spin until push succeeds
            }
        }
    };

    const Consumer = struct {
        fn run(queue: *SPSCQueue(u64), result: *u64) void {
            var count: u64 = 0;
            var expected: u64 = 0;
            while (count < total_items) {
                if (queue.pop()) |item| {
                    assert(item == expected);
                    expected += 1;
                    count += 1;
                }
            }
            result.* = count;
        }
    };

    var received: u64 = 0;

    const producer = try std.Thread.spawn(.{}, Producer.run, .{&q});
    const consumer = try std.Thread.spawn(.{}, Consumer.run, .{ &q, &received });

    producer.join();
    consumer.join();

    try testing.expectEqual(@as(u64, total_items), received);
}
