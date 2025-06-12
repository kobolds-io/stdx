const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const Signal = stdx.Signal;

fn BenchmarkSignalSendReceive(_: std.mem.Allocator) void {
    const want: usize = 100;
    var signal = Signal(usize).new();

    signal.send(want);
    const got = signal.recieve();

    assert(want == got);
}

test "Signal benchmarks" {
    var bench = zbench.Benchmark.init(
        std.testing.allocator,
        .{ .iterations = constants.benchmark_max_iterations },
    );
    defer bench.deinit();

    try bench.add("send/recieve", BenchmarkSignalSendReceive, .{});

    // Write the results to stderr
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("\n");
    try stderr.writeAll("|-------------------|\n");
    try stderr.writeAll("| Signal Benchmarks |\n");
    try stderr.writeAll("|-------------------|\n");
    try bench.run(stderr);
}
