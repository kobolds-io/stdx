const std = @import("std");
const testing = std.testing;
const atomic = std.atomic;

const assert = std.debug.assert;

const CancellationToken = @import("./cancellation_token.zig").CancellationToken;
const RingBuffer = @import("./ring_buffer.zig").RingBuffer;

const poll_interval_ns: u64 = 100_000; // 100us polling interval for timed waits

pub fn BufferedChannel(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: RingBuffer(T),
        mutex: std.Io.Mutex = .init,
        not_empty: std.Io.Condition = .init,
        not_full: std.Io.Condition = .init,
        io: std.Io,

        pub fn init(allocator: std.mem.Allocator, io: std.Io, buffer_capacity: usize) !Self {
            return Self{
                .buffer = try RingBuffer(T).initCapacity(allocator, buffer_capacity),
                .io = io,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.buffer.deinit(allocator);
        }

        pub fn send(self: *Self, value: T) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            while (self.buffer.isFull()) {
                self.not_full.waitUncancelable(self.io, &self.mutex);
            }

            self.buffer.enqueueAssumeCapacity(value);
            self.not_empty.signal(self.io);
        }

        pub fn receive(self: *Self) T {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            while (self.buffer.isEmpty()) {
                self.not_empty.waitUncancelable(self.io, &self.mutex);
            }

            const value = self.buffer.dequeue().?;
            self.not_full.signal(self.io);
            return value;
        }

        pub fn trySend(self: *Self, value: T, timeout_ns: u64, cancel: ?*CancellationToken) !void {
            var now_ts = std.Io.Clock.now(.awake, self.io);
            const deadline = now_ts.nanoseconds + timeout_ns;

            while (true) {
                // Check cancellation before acquiring lock
                if (cancel) |token| {
                    if (token.isCancelled()) return error.Cancelled;
                }

                self.mutex.lockUncancelable(self.io);

                if (!self.buffer.isFull()) {
                    self.buffer.enqueueAssumeCapacity(value);
                    self.not_empty.signal(self.io);
                    self.mutex.unlock(self.io);
                    return;
                }

                self.mutex.unlock(self.io);

                now_ts = std.Io.Clock.now(.awake, self.io);
                if (now_ts.nanoseconds >= deadline) return error.Timeout;

                const remaining = deadline - now_ts.nanoseconds;
                self.io.sleep(.fromNanoseconds(@min(poll_interval_ns, remaining)), .awake) catch {
                    return error.Timeout;
                };
            }
        }

        pub fn tryReceive(self: *Self, timeout_ns: u64, cancel: ?*CancellationToken) !T {
            var now_ts = std.Io.Clock.now(.awake, self.io);
            const deadline = now_ts.nanoseconds + timeout_ns;

            while (true) {
                // Check cancellation before acquiring lock
                if (cancel) |token| {
                    if (token.isCancelled()) return error.Cancelled;
                }

                self.mutex.lockUncancelable(self.io);

                if (!self.buffer.isEmpty()) {
                    const value = self.buffer.dequeue().?;
                    self.not_full.signal(self.io);
                    self.mutex.unlock(self.io);
                    return value;
                }

                self.mutex.unlock(self.io);

                now_ts = std.Io.Clock.now(.awake, self.io);
                if (now_ts.nanoseconds >= deadline) return error.Timeout;

                const remaining = deadline - now_ts.nanoseconds;
                self.io.sleep(.fromNanoseconds(@min(poll_interval_ns, remaining)), .awake) catch {
                    return error.Timeout;
                };
            }
        }

        pub fn count(self: Self) usize {
            return self.buffer.count;
        }

        pub fn capacity(self: Self) usize {
            return self.buffer.capacity;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.buffer.isEmpty();
        }

        pub fn isFull(self: *Self) bool {
            return self.buffer.isFull();
        }

        /// Unsafely Reset the channel and drop ALL items held within.
        ///
        /// `reset` does not deallocate any memory, it only removes all the items from
        /// the channel `buffer`.
        pub fn reset(self: *Self) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            self.buffer.reset();
        }
    };
}

test "multi items" {
    const allocator = testing.allocator;
    const io = testing.io;

    var channel = try BufferedChannel(usize).init(allocator, io, 10);
    defer channel.deinit(allocator);

    for (0..channel.capacity()) |i| {
        channel.send(i);
    }

    try testing.expect(channel.buffer.isFull());

    for (0..channel.capacity()) |i| {
        const v = channel.receive();
        try testing.expectEqual(v, i);
    }
}

test "full behavior" {
    const allocator = testing.allocator;
    const io = testing.io;

    var channel = try BufferedChannel(usize).init(allocator, io, 100);
    defer channel.deinit(allocator);

    const total_items = channel.capacity() * 2;

    const fastSend = struct {
        pub fn fastSend(chan: *BufferedChannel(usize), send_io: std.Io, value: usize, n: usize) void {
            for (0..n) |_| {
                send_io.sleep(.fromMilliseconds(1), .awake) catch unreachable;
                chan.send(value);
            }
        }
    }.fastSend;

    const slowReceive = struct {
        pub fn slowReceive(chan: *BufferedChannel(usize), recv_io: std.Io, n: usize) void {
            for (0..n) |_| {
                recv_io.sleep(.fromMilliseconds(10), .awake) catch unreachable;
                _ = chan.receive();
            }
        }
    }.slowReceive;

    const send_th = try std.Thread.spawn(.{}, fastSend, .{ &channel, io, 42069, total_items });
    defer send_th.join();

    // give time to the send_th to spin up
    try io.sleep(.fromMilliseconds(10), .awake);

    const receive_th = try std.Thread.spawn(.{}, slowReceive, .{ &channel, io, total_items });
    defer receive_th.join();
}

test "receive timeouts and cancellation" {
    const allocator = testing.allocator;
    const io = testing.io;

    var channel = try BufferedChannel(usize).init(allocator, io, 100);
    defer channel.deinit(allocator);

    const receiver = struct {
        pub fn do(running: *bool, chan: *BufferedChannel(usize), delay: u64, cancel_token: *CancellationToken) void {
            running.* = true;
            assert(!cancel_token.isCancelled());
            testing.expectError(error.Cancelled, chan.tryReceive(delay, cancel_token)) catch unreachable;
        }
    }.do;

    try testing.expectError(error.Timeout, channel.tryReceive(1, null));

    var cancel_token = CancellationToken{};
    const delay = 100 * std.time.ns_per_ms;
    var running = false;
    const cancel_th = try std.Thread.spawn(.{}, receiver, .{ &running, &channel, delay, &cancel_token });
    defer cancel_th.join();

    try io.sleep(.fromMilliseconds(10), .awake);
    try testing.expectEqual(true, running);

    cancel_token.cancel();
}

test "send timeouts and cancellation" {
    const allocator = testing.allocator;
    const io = testing.io;

    var channel = try BufferedChannel(usize).init(allocator, io, 10);
    defer channel.deinit(allocator);

    for (0..channel.buffer.capacity) |i| {
        channel.send(i);
    }

    const sender = struct {
        pub fn do(running: *bool, chan: *BufferedChannel(usize), delay: u64, cancel_token: *CancellationToken) void {
            running.* = true;
            assert(!cancel_token.isCancelled());
            testing.expectError(error.Cancelled, chan.trySend(42069, delay, cancel_token)) catch unreachable;
        }
    }.do;

    try testing.expectError(error.Timeout, channel.trySend(42069, 1, null));

    var cancel_token = CancellationToken{};
    const delay = 100 * std.time.ns_per_ms;
    var running = false;
    const cancel_th = try std.Thread.spawn(.{}, sender, .{ &running, &channel, delay, &cancel_token });
    defer cancel_th.join();

    try io.sleep(.fromMilliseconds(10), .awake);
    try testing.expectEqual(true, running);

    cancel_token.cancel();
}
