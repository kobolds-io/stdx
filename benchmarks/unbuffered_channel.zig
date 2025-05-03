const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const UnbufferedChannel = stdx.UnbufferedChannel;

const BenchmarkUnbufferedChannelSendReceive = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    channel: *UnbufferedChannel(usize),

    fn new(list: *std.ArrayList(usize), channel: *UnbufferedChannel(usize)) Self {
        return .{
            .list = list,
            .channel = channel,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        for (self.list.items) |data| {
            self.channel.send(data);
            const v = self.channel.timedReceive(1 * std.time.ns_per_ms) catch unreachable;
            assert(v == data);
        }
    }
};

var simple_channel: UnbufferedChannel(usize) = undefined;

var data_list: std.ArrayList(usize) = undefined;
const allocator = testing.allocator;

test "SimpleChannel benchmarks" {
    var bench = zbench.Benchmark.init(
        std.testing.allocator,
        .{ .iterations = constants.benchmark_max_iterations },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    data_list = try std.ArrayList(usize).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    );
    defer data_list.deinit();

    // fill the data list with items
    for (0..data_list.capacity) |i| {
        data_list.appendAssumeCapacity(@intCast(i));
    }

    const simple_channel_send_receive_title = try std.fmt.allocPrint(
        allocator,
        "send/receive {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(simple_channel_send_receive_title);

    // register all the benchmark tests
    try bench.addParam(
        simple_channel_send_receive_title,
        &BenchmarkUnbufferedChannelSendReceive.new(&data_list, &simple_channel),
        .{},
    );

    // Write the results to stderr
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("\n");
    try stderr.writeAll("|------------------------------|\n");
    try stderr.writeAll("| UnbufferedChannel Benchmarks |\n");
    try stderr.writeAll("|------------------------------|\n");
    try bench.run(stderr);
}
