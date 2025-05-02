const std = @import("std");
const testing = std.testing;
const atomic = std.atomic;

const assert = std.debug.assert;

const RingBuffer = @import("./ring_buffer.zig").RingBuffer;

pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        // TODO: convert buffer to a RingBuffer
        buffer: RingBuffer(T),

        mutex: std.Thread.Mutex = .{},
        not_empty: std.Thread.Condition = .{},
        not_full: std.Thread.Condition = .{},

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            return Self{
                .buffer = try RingBuffer(T).init(allocator, capacity),
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }

        pub fn send(self: *Self, value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.buffer.isFull()) {
                self.not_full.wait(&self.mutex);
            }

            self.buffer.enqueue(value) catch unreachable;
            self.not_empty.signal();
        }

        pub fn receive(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.buffer.isEmpty()) {
                self.not_empty.wait(&self.mutex);
            }

            const value = self.buffer.dequeue().?;

            self.not_full.signal();
            return value;
        }

        pub fn trySend(self: *Self, value: T, delay_us: i64, cancel: ?*CancellationToken) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const deadline = std.time.microTimestamp() + delay_us;

            while (self.buffer.isFull()) {
                if (cancel) |token| {
                    if (token.isCancelled()) return error.Cancelled;
                }

                const now: i64 = std.time.microTimestamp();
                if (now >= deadline) return error.Timeout;

                self.not_empty.timedWait(&self.mutex, @intCast(deadline - now)) catch {
                    continue;
                };
            }

            self.buffer.enqueue(value) catch unreachable;
            self.not_empty.signal();
        }

        pub fn tryReceive(self: *Self, delay_us: i64, cancel: ?*CancellationToken) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            const deadline = std.time.microTimestamp() + delay_us;

            while (self.buffer.isEmpty()) {
                if (cancel) |token| {
                    if (token.isCancelled()) return error.Cancelled;
                }

                const now: i64 = std.time.microTimestamp();
                if (now >= deadline) return error.Timeout;

                self.not_empty.timedWait(&self.mutex, @intCast(deadline - now)) catch {
                    continue;
                };
            }

            const value = self.buffer.dequeue().?;
            self.not_full.signal();
            return value;
        }
    };
}

pub const CancellationToken = struct {
    const Self = @This();
    cancelled: atomic.Value(bool) = atomic.Value(bool).init(false),

    pub fn cancel(self: *Self) void {
        self.cancelled.store(true, .seq_cst);
    }

    pub fn isCancelled(self: *Self) bool {
        return self.cancelled.load(.seq_cst);
    }
};

test "multi item channel" {
    const allocator = testing.allocator;

    var channel = try Channel(usize).init(allocator, 10);
    defer channel.deinit();

    // multiple items can be buffered
    for (0..channel.buffer.capacity) |i| {
        channel.send(i);
    }

    try testing.expect(channel.buffer.isFull());

    // values are received in the same order that they are sent
    for (0..channel.buffer.capacity) |i| {
        const v = channel.receive();
        try testing.expectEqual(v, i);
    }
}

test "channel full behavior" {
    const allocator = testing.allocator;

    var channel = try Channel(usize).init(allocator, 100);
    defer channel.deinit();

    // start a fast sender
    const fastSend = struct {
        pub fn fastSend(chan: *Channel(usize), value: usize) void {
            // send 20 items, which is more than the capacity of the channel
            // we are relying on the slow receiver to pull items out of the channel
            // thus opening available slots for the new items
            for (0..chan.buffer.capacity * 2) |_| {
                std.time.sleep(1 * std.time.ns_per_ms);
                chan.send(value);
            }
        }
    }.fastSend;

    // start a slow thread
    const slowReceive = struct {
        pub fn slowReceive(chan: *Channel(usize)) void {
            var iters: usize = 0;
            while (!chan.buffer.isEmpty()) {
                std.time.sleep(10 * std.time.ns_per_ms);
                _ = chan.receive();
                iters += 1;
            }

            // ensure that we are pull ALL of the items out of the channel
            testing.expectEqual(chan.buffer.capacity * 2, iters) catch unreachable;
        }
    }.slowReceive;

    const send_th = try std.Thread.spawn(.{}, fastSend, .{ &channel, 42069 });
    defer send_th.join();

    // give time to the send_th to spin up
    std.time.sleep(10 * std.time.ns_per_ms);

    const receive_th = try std.Thread.spawn(.{}, slowReceive, .{&channel});
    defer receive_th.join();
}

test "receive timeouts and cancellation" {
    const allocator = testing.allocator;

    var channel = try Channel(usize).init(allocator, 100);
    defer channel.deinit();

    const receiver = struct {
        pub fn do(running: *bool, chan: *Channel(usize), delay: i64, cancel_token: *CancellationToken) void {
            running.* = true;
            // ensure that the token is not cancelled before starting to wait
            assert(!cancel_token.isCancelled());

            testing.expectError(error.Cancelled, chan.tryReceive(delay, cancel_token)) catch unreachable;
        }
    }.do;

    try testing.expectError(error.Timeout, channel.tryReceive(1, null));

    var cancel_token = CancellationToken{};
    // 100 milliseconds
    const delay = 100_000;
    var running = false;
    const cancel_th = try std.Thread.spawn(.{}, receiver, .{ &running, &channel, delay, &cancel_token });
    defer cancel_th.join();

    // give time to the cancel_th to spin up
    std.time.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(true, running);

    cancel_token.cancel();
}

test "send timeouts and cancellation" {
    const allocator = testing.allocator;

    var channel = try Channel(usize).init(allocator, 10);
    defer channel.deinit();

    // fill the channel up
    for (0..channel.buffer.capacity) |i| {
        channel.send(i);
    }

    const sender = struct {
        pub fn do(running: *bool, chan: *Channel(usize), delay: i64, cancel_token: *CancellationToken) void {
            running.* = true;
            // ensure that the token is not cancelled before starting to wait
            assert(!cancel_token.isCancelled());

            testing.expectError(error.Cancelled, chan.trySend(42069, delay, cancel_token)) catch unreachable;
        }
    }.do;

    try testing.expectError(error.Timeout, channel.trySend(42069, 1, null));

    var cancel_token = CancellationToken{};

    // 100 milliseconds
    const delay = 100_000;
    var running = false;
    const cancel_th = try std.Thread.spawn(.{}, sender, .{ &running, &channel, delay, &cancel_token });
    defer cancel_th.join();

    // give time to the cancel_th to spin up
    std.time.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(true, running);

    cancel_token.cancel();
}
