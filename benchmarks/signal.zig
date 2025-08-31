const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const Signal = stdx.Signal;

// NOTE: don't know how much we can trust this kind of benchmark. Signals aren't supposed to
// be used this way. They are effectively oneshot structures and this doesn't feel right.
fn BenchmarkSignalSendReceive(_: std.mem.Allocator) void {
    const want: usize = 100;
    var signal = Signal(usize).new();

    for (0..constants.benchmark_max_queue_data_list) |_| {
        // this is a hard reset of the signal and shouldn't be performed by
        // end users as signals should only be used once.
        defer {
            signal.ready = false;
            signal.value = null;
        }
        signal.send(want);
        const got = signal.receive();

        assert(want == got);
    }
}

test "Signal benchmarks" {
    const allocator = std.testing.allocator;
    var bench = zbench.Benchmark.init(
        allocator,
        .{ .iterations = constants.benchmark_max_iterations },
    );
    defer bench.deinit();

    const signal_send_receive_title = try std.fmt.allocPrint(
        allocator,
        "send/receive {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(signal_send_receive_title);

    try bench.add(signal_send_receive_title, BenchmarkSignalSendReceive, .{});

    var stderr = std.fs.File.stderr().writerStreaming(&.{});
    const writer = &stderr.interface;

    try writer.writeAll("\n");
    try writer.writeAll("|-------------------|\n");
    try writer.writeAll("| Signal Benchmarks |\n");
    try writer.writeAll("|-------------------|\n");
    try bench.run(writer);
}
