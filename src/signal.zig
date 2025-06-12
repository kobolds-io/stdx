const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

// const SignalError = error{
//     Timeout,
// };

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
    };

    const reciever = struct {
        fn recieve(sig: *Signal(usize), res: *usize) void {
            const got = sig.recieve();
            res.* = got;
        }
    };

    var result: usize = undefined;
    const recieve_thread = try std.Thread.spawn(.{}, reciever.recieve, .{ &signal, &result });
    defer recieve_thread.join();

    const send_thread = try std.Thread.spawn(.{}, sender.send, .{ &signal, want });
    defer send_thread.join();

    const deadline = std.time.nanoTimestamp() + (1 * std.time.ns_per_s);

    while (std.time.nanoTimestamp() < deadline) {
        if (want != result) continue;
        break;
    } else {
        return error.TestExceededDeadline;
    }

    // Have a kind of BS test here to evaluate the result
    try testing.expectEqual(want, result);
}
