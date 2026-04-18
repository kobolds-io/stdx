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

        not_full: std.Io.Condition = .init,
        not_empty: std.Io.Condition = .init,
        mutex: std.Io.Mutex = .init,
        value: ?T = null,
        io: std.Io,

        const poll_interval_ns: u64 = 100_000; // 100us

        pub fn new(io: std.Io) Self {
            return .{ .io = io };
        }

        /// Send a value to the receiver.
        /// `send` will block until `receive` is called and consumes the value.
        pub fn send(self: *Self, value: T) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            // wait until the previous value has been consumed
            while (self.value != null) {
                self.not_full.waitUncancelable(self.io, &self.mutex);
            }

            self.value = value;
            self.not_empty.signal(self.io);
        }

        /// Receive a value from the sender.
        pub fn receive(self: *Self) T {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            while (self.value == null) {
                self.not_empty.waitUncancelable(self.io, &self.mutex);
            }

            const result = self.value.?;
            self.value = null;
            self.not_full.signal(self.io); // notify sender that slot is free
            return result;
        }

        pub fn tryReceive(self: *Self, timeout: std.Io.Duration) !T {
            var now_ts = std.Io.Clock.now(.awake, self.io);
            const deadline = now_ts.nanoseconds + timeout.nanoseconds;

            while (true) {
                self.mutex.lockUncancelable(self.io);

                if (self.value != null) {
                    const result = self.value.?;
                    self.value = null;
                    self.not_full.signal(self.io);
                    self.mutex.unlock(self.io);
                    return result;
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
    };
}

test "good behavior" {
    const io = testing.io;

    const testerFn = struct {
        fn run(channel: *UnbufferedChannel(u32), value: u32) void {
            channel.send(value);
        }
    }.run;

    const want: u32 = 123;

    var channel = UnbufferedChannel(u32).new(io);
    const th = try std.Thread.spawn(.{}, testerFn, .{ &channel, want });
    defer th.join();

    const got = try channel.tryReceive(.fromSeconds(1));
    try testing.expectEqual(want, got);
}

test "bad behavior" {
    const io = testing.io;

    const testerFn = struct {
        fn run(channel: *UnbufferedChannel(u32), send_io: std.Io, value: u32) void {
            send_io.sleep(.fromMilliseconds(500), .awake) catch unreachable;
            channel.send(value);
        }
    }.run;

    var channel = UnbufferedChannel(u32).new(io);
    _ = try std.Thread.spawn(.{}, testerFn, .{ &channel, io, 9999 });

    try testing.expectError(error.Timeout, channel.tryReceive(.fromMicroseconds(1)));
}

test "receive multiple values" {
    const io = testing.io;

    const testerFn = struct {
        fn run(channel: *UnbufferedChannel(u32)) void {
            channel.send(1);
            channel.send(2);
            channel.send(3);
        }
    }.run;

    var channel = UnbufferedChannel(u32).new(io);
    const th = try std.Thread.spawn(.{}, testerFn, .{&channel});
    defer th.join();

    try testing.expectEqual(1, channel.receive());
    try testing.expectEqual(2, channel.receive());
    try testing.expectEqual(3, channel.receive());
}
