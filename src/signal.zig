const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const SignalError = error{
    Timeout,
};

pub fn Signal(comptime T: type) type {
    return struct {
        const Self = @This();

        cond: std.Io.Condition,
        mutex: std.Io.Mutex,
        ready: bool,
        value: ?T,
        io: std.Io,

        pub fn new(io: std.Io) Self {
            return Self{
                .cond = .init,
                .mutex = .init,
                .ready = false,
                .value = null,
                .io = io,
            };
        }

        pub fn receive(self: *Self) T {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            while (!self.ready) {
                self.cond.waitUncancelable(self.io, &self.mutex);
            }

            assert(self.value != null);

            return self.value.?;
        }

        pub fn send(self: *Self, value: T) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            // enforce that this is a oneshot operation
            assert(self.value == null);

            self.value = value;
            self.ready = true;

            self.cond.signal(self.io);
        }

        pub fn tryReceive(self: *Self, timeout_ns: u64) SignalError!T {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            var now_ts = std.Io.Clock.now(.awake, self.io);
            const start = now_ts.nanoseconds;
            const deadline = start + timeout_ns;

            while (!self.ready) {
                now_ts = std.Io.Clock.now(.awake, self.io);
                if (now_ts.nanoseconds >= deadline) return SignalError.Timeout;

                self.cond.wait(self.io, &self.mutex) catch {
                    return SignalError.Timeout;
                };
            }

            assert(self.value != null);
            return self.value.?;
        }

        pub fn trySend(self: *Self, value: T, timeout_ns: u64) SignalError!void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            // we enforce that this is a true one shot and can only be used between a single
            // sender and a single receiever
            assert(self.value == null);

            var now_ts = std.Io.Clock.now(.awake, self.io);
            const start = now_ts.nanoseconds;
            const deadline = start + timeout_ns;

            while (self.value != null) {
                now_ts = std.Io.Clock.now(.awake, self.io);
                if (now_ts.nanoseconds >= deadline) return SignalError.Timeout;

                self.cond.wait(self.io, &self.mutex) catch {
                    return SignalError.Timeout;
                };
            }

            self.value = value;
            self.ready = true;
            self.cond.signal(self.io);
        }
    };
}

test "basic operation" {
    const io = testing.io;
    const want: usize = 123;

    var signal = Signal(usize).new(io);
    signal.send(want);

    const got = signal.receive();

    try testing.expectEqual(want, got);
}

test "multithreaded support" {
    const io = testing.io;
    const want: usize = 123;

    var signal = Signal(usize).new(io);

    const sender = struct {
        fn send(sig: *Signal(usize), value: usize) void {
            sig.send(value);
        }

        fn trySend(sig: *Signal(usize), value: usize, timeout_ns: u64) void {
            sig.trySend(value, timeout_ns) catch unreachable;
        }
    };

    const receiever = struct {
        fn receieve(sig: *Signal(usize), res: *usize) void {
            const got = sig.receive();
            res.* = got;
        }

        fn tryReceive(sig: *Signal(usize), res: *usize, timeout_ns: u64) void {
            const got = sig.tryReceive(timeout_ns) catch unreachable;
            res.* = got;
        }
    };

    var result: usize = undefined;

    try testing.expect(want != result);

    const receieve_thread = try std.Thread.spawn(.{}, receiever.receieve, .{ &signal, &result });
    defer receieve_thread.join();

    const send_thread = try std.Thread.spawn(.{}, sender.send, .{ &signal, want });
    defer send_thread.join();

    const timeout_ns = 1 * std.time.ns_per_s;
    var now_ts = std.Io.Clock.now(.awake, io);
    var deadline = now_ts.nanoseconds + timeout_ns;

    while (now_ts.nanoseconds < deadline) {
        defer now_ts = std.Io.Clock.now(.awake, io);
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
    now_ts = std.Io.Clock.now(.awake, io);
    deadline = now_ts.nanoseconds + timeout_ns;

    try testing.expect(want != result);

    var timed_signal = Signal(usize).new(io);
    const try_receive_thread = try std.Thread.spawn(.{}, receiever.tryReceive, .{ &timed_signal, &result, timeout_ns });
    defer try_receive_thread.join();

    const try_send_thread = try std.Thread.spawn(.{}, sender.trySend, .{ &timed_signal, want, timeout_ns });
    defer try_send_thread.join();

    now_ts = std.Io.Clock.now(.awake, io);
    while (now_ts.nanoseconds < deadline) {
        if (want != result) continue;
        break;
    } else {
        return error.TestExceededDeadline;
    }

    // Have a kind of BS test here to evaluate the result
    try testing.expectEqual(want, result);
}
