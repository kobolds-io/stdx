const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

/// A very simple implementation of a channel. Very useful for sending signals across
/// threads for syncing operations or to ensure that a thread has completed a task.
/// This channel is able to send multiple values to the receiver but can only hold a
/// single value at a time.
pub fn UnbufferedChannel(comptime T: type) type {
    return struct {
        const Self = @This();

        condition: std.Thread.Condition = .{},
        mutex: std.Thread.Mutex = .{},
        value: T = undefined,
        has_value: bool = false,

        pub fn new() Self {
            return .{};
        }

        /// Send a value to the receiver.
        /// `send` will block until the `receive` is called and consumes the value.
        pub fn send(self: *Self, value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.has_value) {
                self.condition.wait(&self.mutex);
            }

            self.value = value;
            self.has_value = true;
            self.condition.signal();
        }

        /// Receive a value from the sender.
        pub fn receive(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (!self.has_value) {
                self.condition.wait(&self.mutex);
            }

            const result = self.value;
            self.has_value = false;
            self.condition.signal(); // notify sender
            return result;
        }

        pub fn tryReceive(self: *Self, timeout_ns: u64) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            const start = std.time.nanoTimestamp();
            const deadline = start + timeout_ns;

            while (!self.has_value) {
                const now = std.time.nanoTimestamp();
                if (now >= deadline) {
                    self.condition.signal(); // signal sender in case it’s waiting
                    return error.TimedOut;
                }

                const remaining: u64 = @intCast(deadline - now);
                assert(remaining > 0);
                try self.condition.timedWait(&self.mutex, remaining);
            }

            const result = self.value;
            self.has_value = false;
            self.condition.signal(); // notify sender
            return result;
        }
    };
}

test "good behavior" {
    const testerFn = struct {
        fn run(channel: *UnbufferedChannel(u32), value: u32) void {
            channel.send(value);
        }
    }.run;

    const want: u32 = 123;

    var channel = UnbufferedChannel(u32).new();
    const th = try std.Thread.spawn(.{}, testerFn, .{ &channel, want });
    defer th.join();

    const got = try channel.tryReceive(1 * std.time.ns_per_ms);

    try testing.expectEqual(want, got);
}

test "bad behavior" {
    const testerFn = struct {
        fn run(channel: *UnbufferedChannel(u32), value: u32) void {
            std.time.sleep(500 * std.time.ns_per_ms); // wait too long
            channel.send(value);
        }
    }.run;

    var channel = UnbufferedChannel(u32).new();
    _ = try std.Thread.spawn(.{}, testerFn, .{ &channel, 9999 });

    try testing.expectError(error.Timeout, channel.tryReceive(1 * std.time.ns_per_us));
}

test "receive multiple values" {
    const testerFn = struct {
        fn run(channel: *UnbufferedChannel(u32)) void {
            channel.send(1);
            channel.send(2);
            channel.send(3);
        }
    }.run;

    var channel = UnbufferedChannel(u32).new();
    const th = try std.Thread.spawn(.{}, testerFn, .{&channel});
    defer th.join();

    const v1 = channel.receive();
    try testing.expectEqual(1, v1);

    const v2 = channel.receive();
    try testing.expectEqual(2, v2);

    const v3 = channel.receive();
    try testing.expectEqual(3, v3);
}
