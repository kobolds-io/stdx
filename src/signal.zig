const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const SignalError = error{
    Timeout,
};

pub fn Signal(comptime T: type) type {
    return struct {
        const Self = @This();

        cond: std.Thread.Condition,
        mutex: std.Thread.Mutex,
        ready: bool,
        value: ?T,

        pub fn new() Self {
            return Self{
                .cond = .{},
                .mutex = .{},
                .ready = false,
                .value = null,
            };
        }

        pub fn recieve(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (!self.ready) {
                self.cond.wait(&self.mutex);
            }

            assert(self.value != null);

            return self.value.?;
        }

        pub fn send(self: *Self, value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // enforce that this is a oneshot operation
            assert(self.value == null);

            self.value = value;
            self.ready = true;

            self.cond.signal();
        }

        pub fn tryReceive(self: *Self, timeout_ns: u64) SignalError!T {
            self.mutex.lock();
            defer self.mutex.unlock();

            const start = std.time.nanoTimestamp();
            const deadline = start + timeout_ns;

            while (!self.ready) {
                const now = std.time.nanoTimestamp();
                if (now >= deadline) return SignalError.Timeout;

                self.cond.timedWait(&self.mutex, @intCast(deadline - now)) catch {
                    return SignalError.Timeout;
                };
            }

            assert(self.value != null);
            return self.value.?;
        }

        pub fn trySend(self: *Self, value: T, timeout_ns: u64) SignalError!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // we enforce that this is a true one shot and can only be used between a single
            // sender and a single reciever
            assert(self.value == null);

            const start = std.time.nanoTimestamp();
            const deadline = start + timeout_ns;

            while (self.value != null) {
                const now = std.time.nanoTimestamp();
                if (now >= deadline) return SignalError.Timeout;

                self.cond.timedWait(&self.mutex, @intCast(deadline - now)) catch {
                    return SignalError.Timeout;
                };
            }

            self.value = value;
            self.ready = true;
            self.cond.signal();
        }
    };
}

test "basic operation" {
    const want: usize = 123;

    var signal = Signal(usize).new();
    signal.send(want);

    const got = signal.recieve();

    try testing.expectEqual(want, got);
}

test "multithreaded support" {
    const want: usize = 123;

    var signal = Signal(usize).new();

    const sender = struct {
        fn send(sig: *Signal(usize), value: usize) void {
            sig.send(value);
        }

        fn trySend(sig: *Signal(usize), value: usize, timeout_ns: u64) void {
            sig.trySend(value, timeout_ns) catch unreachable;
        }
    };

    const reciever = struct {
        fn recieve(sig: *Signal(usize), res: *usize) void {
            const got = sig.recieve();
            res.* = got;
        }

        fn tryReceive(sig: *Signal(usize), res: *usize, timeout_ns: u64) void {
            const got = sig.tryReceive(timeout_ns) catch unreachable;
            res.* = got;
        }
    };

    var result: usize = undefined;

    try testing.expect(want != result);

    const recieve_thread = try std.Thread.spawn(.{}, reciever.recieve, .{ &signal, &result });
    defer recieve_thread.join();

    const send_thread = try std.Thread.spawn(.{}, sender.send, .{ &signal, want });
    defer send_thread.join();

    const timeout_ns = 1 * std.time.ns_per_s;
    var deadline = std.time.nanoTimestamp() + timeout_ns;

    while (std.time.nanoTimestamp() < deadline) {
        if (want != result) continue;
        break;
    } else {
        return error.TestExceededDeadline;
    }

    // Have a kind of BS test here to evaluate the result
    try testing.expectEqual(want, result);

    // ----

    // reset the world
    result = 0;
    deadline = std.time.nanoTimestamp() + timeout_ns;

    try testing.expect(want != result);

    var timed_signal = Signal(usize).new();
    const try_receive_thread = try std.Thread.spawn(.{}, reciever.tryReceive, .{ &timed_signal, &result, timeout_ns });
    defer try_receive_thread.join();

    const try_send_thread = try std.Thread.spawn(.{}, sender.trySend, .{ &timed_signal, want, timeout_ns });
    defer try_send_thread.join();

    while (std.time.nanoTimestamp() < deadline) {
        if (want != result) continue;
        break;
    } else {
        return error.TestExceededDeadline;
    }

    // Have a kind of BS test here to evaluate the result
    try testing.expectEqual(want, result);
}
