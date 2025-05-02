const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

/// A very simple implementation of a channel. Very useful for sending signals across
/// threads for syncing operations or to ensure that a thread has completed a task.
/// This channel is able to send multiple values to the receiver but can only hold a
/// single value.
pub fn SimpleChannel(comptime T: type) type {
    return struct {
        const Self = @This();

        condition: std.Thread.Condition = .{},
        mutex: std.Thread.Mutex = .{},
        value: T = undefined,
        has_value: bool = false,

        pub fn init() Self {
            return .{};
        }

        /// Send a value to the receiver.
        ///
        /// `send` will block until the `receive` is called.
        pub fn send(self: *Self, value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Wait until the previous value has been received
            while (self.has_value) {
                self.condition.wait(&self.mutex);
            }

            self.value = value;
            self.has_value = true;
            self.condition.signal();
        }

        /// Receive a value from a sender.
        pub fn receive(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Wait until a value is available
            while (!self.has_value) {
                self.condition.wait(&self.mutex);
            }

            const result = self.value;
            self.has_value = false;
            self.condition.signal(); // allow sender to send again
            return result;
        }

        pub fn timedReceive(self: *Self, timeout_ns: u64) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            const fn_now: u64 = @intCast(std.time.nanoTimestamp());
            const deadline: u64 = fn_now + timeout_ns;

            while (!self.has_value) {
                const loop_now: u64 = @intCast(std.time.nanoTimestamp());
                if (loop_now >= deadline) return error.TimedOut;
                try self.condition.timedWait(&self.mutex, deadline - loop_now);
            }

            const result = self.value;
            self.has_value = false;
            self.condition.signal();
            return result;
        }
    };
}

test "good behavior" {
    const testerFn = struct {
        fn run(channel: *SimpleChannel(u32), value: u32) void {
            channel.send(value);
        }
    }.run;

    const want: u32 = 123;

    var channel = SimpleChannel(u32).init();
    const th = try std.Thread.spawn(.{}, testerFn, .{ &channel, want });
    defer th.join();

    const got = try channel.timedReceive(1 * std.time.ns_per_ms);

    try testing.expectEqual(want, got);
}

test "bad behavior" {
    const testerFn = struct {
        fn run(channel: *SimpleChannel(u32), value: u32) void {
            // exceeds the allowed timeout value for channel receive
            std.time.sleep(5 * std.time.ns_per_ms);
            channel.send(value);
        }
    }.run;

    var channel = SimpleChannel(u32).init();
    const th = try std.Thread.spawn(.{}, testerFn, .{ &channel, 9999 });
    defer th.join();

    try testing.expectError(error.Timeout, channel.timedReceive(1 * std.time.ns_per_us));
}

test "receive multiple values" {
    const testerFn = struct {
        fn run(channel: *SimpleChannel(u32)) void {
            channel.send(1);
            channel.send(2);
            channel.send(3);
        }
    }.run;

    var channel = SimpleChannel(u32).init();
    const th = try std.Thread.spawn(.{}, testerFn, .{&channel});
    defer th.join();

    const v1 = channel.receive();
    try testing.expectEqual(1, v1);

    const v2 = channel.receive();
    try testing.expectEqual(2, v2);

    const v3 = channel.receive();
    try testing.expectEqual(3, v3);
}
