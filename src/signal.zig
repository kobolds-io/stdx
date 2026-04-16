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
            return .{
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

            const value = self.value orelse unreachable;
            return value;
        }

        pub fn send(self: *Self, value: T) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            assert(!self.ready);
            assert(self.value == null);

            self.value = value;
            self.ready = true;
            self.cond.signal(self.io);
        }

        pub fn tryReceive(self: *Self, timeout_ns: u64) SignalError!T {
            const poll_ns = 100_000; // 100us

            var now_ts = std.Io.Clock.now(.awake, self.io);
            const deadline = now_ts.nanoseconds + timeout_ns;

            while (true) {
                self.mutex.lockUncancelable(self.io);
                if (self.ready) {
                    const value = self.value orelse unreachable;
                    self.mutex.unlock(self.io);
                    return value;
                }
                self.mutex.unlock(self.io);

                now_ts = std.Io.Clock.now(.awake, self.io);
                if (now_ts.nanoseconds >= deadline) {
                    return SignalError.Timeout;
                }

                const remaining = deadline - now_ts.nanoseconds;
                self.io.sleep(.fromNanoseconds(@min(poll_ns, remaining)), .awake) catch {
                    return SignalError.Timeout;
                };
            }
        }

        pub fn trySend(self: *Self, value: T, timeout_ns: u64) SignalError!void {
            _ = timeout_ns;

            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            assert(!self.ready);
            assert(self.value == null);

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

    const Sender = struct {
        fn send(sig: *Signal(usize), value: usize) void {
            sig.send(value);
        }

        fn trySend(sig: *Signal(usize), value: usize, timeout_ns: u64) void {
            sig.trySend(value, timeout_ns) catch unreachable;
        }
    };

    const Receiver = struct {
        fn receive(sig: *Signal(usize), res: *usize) void {
            res.* = sig.receive();
        }

        fn tryReceive(sig: *Signal(usize), res: *usize, timeout_ns: u64) void {
            res.* = sig.tryReceive(timeout_ns) catch unreachable;
        }
    };

    var result: usize = 0;
    try testing.expect(want != result);

    const receive_thread = try std.Thread.spawn(.{}, Receiver.receive, .{ &signal, &result });
    defer receive_thread.join();

    const send_thread = try std.Thread.spawn(.{}, Sender.send, .{ &signal, want });
    defer send_thread.join();

    const timeout_ns = 1 * std.time.ns_per_s;
    var now_ts = std.Io.Clock.now(.awake, io);
    const deadline = now_ts.nanoseconds + timeout_ns;

    while (true) {
        if (result == want) break;
        now_ts = std.Io.Clock.now(.awake, io);
        if (now_ts.nanoseconds >= deadline) return error.TestExceededDeadline;
        io.sleep(.fromNanoseconds(100_000), .awake) catch {};
    }

    try testing.expectEqual(want, result);

    result = 0;
    var timed_signal = Signal(usize).new(io);

    const try_receive_thread = try std.Thread.spawn(.{}, Receiver.tryReceive, .{ &timed_signal, &result, timeout_ns });
    defer try_receive_thread.join();

    const try_send_thread = try std.Thread.spawn(.{}, Sender.trySend, .{ &timed_signal, want, timeout_ns });
    defer try_send_thread.join();

    now_ts = std.Io.Clock.now(.awake, io);
    const deadline2 = now_ts.nanoseconds + timeout_ns;

    while (true) {
        if (result == want) break;
        now_ts = std.Io.Clock.now(.awake, io);
        if (now_ts.nanoseconds >= deadline2) return error.TestExceededDeadline;
        io.sleep(.fromNanoseconds(100_000), .awake) catch {};
    }

    try testing.expectEqual(want, result);
}
