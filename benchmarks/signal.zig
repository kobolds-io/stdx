const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const Signal = stdx.Signal;

// NOTE: don't know how much we can trust this kind of benchmark. Signals aren't supposed to
// be used this way. They are effectively oneshot structures and this doesn't feel right.
const BenchmarkSignalSendReceive = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    signal: *Signal(usize),

    fn comparator(_: void, left: usize, right: usize) bool {
        return left < right;
    }

    fn new(list: *std.ArrayList(usize), signal: *Signal(usize)) Self {
        return .{
            .list = list,
            .signal = signal,
        };
    }

    pub fn run(self: *Self, _: std.mem.Allocator) void {
        for (self.list.items) |i| {
            // this is a hard reset of the signal and shouldn't be performed by
            // end users as signals should only be used once.
            defer {
                self.signal.ready = false;
                self.signal.value = null;
            }
            self.signal.send(i);
            const got = self.signal.receive();

            assert(i == got);
        }
    }
};

test "Signal benchmarks" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var bench = zbench.Benchmark.init(
        allocator,
        .{ .iterations = constants.benchmark_max_iterations },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    var data_list = try std.ArrayList(usize).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    );
    defer data_list.deinit(allocator);

    // fill the data list with items
    for (0..data_list.capacity) |i| {
        data_list.appendAssumeCapacity(i);
    }

    var signal = Signal(usize).new(io);

    const signal_send_receive_title = try std.fmt.allocPrint(
        allocator,
        "send/receive {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(signal_send_receive_title);

    try bench.addParam(
        signal_send_receive_title,
        &BenchmarkSignalSendReceive.new(&data_list, &signal),
        .{},
    );

    const stderr = std.Io.File.stderr();
    var stderr_writer = stderr.writerStreaming(io, &.{});
    const writer = &stderr_writer.interface;

    try writer.writeAll("\n");
    try writer.writeAll("|-------------------|\n");
    try writer.writeAll("| Signal Benchmarks |\n");
    try writer.writeAll("|-------------------|\n");
    try bench.run(io, stderr);
}
