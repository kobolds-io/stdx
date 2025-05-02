const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

/// A very simple implementation of a channel. Very useful for sending signals across
/// threads for syncing operations or to ensure that a thread has completed a task.
pub fn SimpleChannel(comptime T: type) type {
    return struct {
        const Self = @This();

        condition: std.Thread.Condition,
        mutex: std.Thread.Mutex,
        value: T,

        pub fn init() Self {
            return Self{
                .condition = std.Thread.Condition{},
                .mutex = std.Thread.Mutex{},
                .value = undefined,
            };
        }

        pub fn send(self: *Self, value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.value = value;

            self.condition.signal();
        }

        pub fn timedReceive(self: *Self, timeout_ns: u64) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.condition.timedWait(&self.mutex, timeout_ns);

            return self.value;
        }

        pub fn receive(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.condition.wait(&self.mutex);

            return self.value;
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
