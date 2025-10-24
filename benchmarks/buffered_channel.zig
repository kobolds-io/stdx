const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const BufferedChannel = stdx.BufferedChannel;

const BenchmarkBufferedChannelSend = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    channel: *BufferedChannel(usize),

    fn new(list: *std.ArrayList(usize), channel: *BufferedChannel(usize)) Self {
        return .{
            .list = list,
            .channel = channel,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        for (self.list.items) |data| {
            self.channel.send(data);
        }
    }
};

const BenchmarkBufferedChannelReceive = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    channel: *BufferedChannel(usize),

    fn new(list: *std.ArrayList(usize), channel: *BufferedChannel(usize)) Self {
        return .{
            .list = list,
            .channel = channel,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        for (self.list.items) |_| {
            _ = self.channel.receive();
        }
    }
};

var send_channel: BufferedChannel(usize) = undefined;
var receive_channel: BufferedChannel(usize) = undefined;

var data_list: std.ArrayList(usize) = .empty;
const allocator = testing.allocator;

fn beforeEachSend() void {
    send_channel.buffer.reset();
}

fn beforeEachReceive() void {
    receive_channel.buffer.fill(42069);
    assert(receive_channel.buffer.available() == 0);
}

test "BufferedChannel benchmarks" {
    var bench = zbench.Benchmark.init(
        std.testing.allocator,
        // .{ .iterations = 1 },
        .{ .iterations = constants.benchmark_max_iterations },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    data_list = try std.ArrayList(usize).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    );
    defer data_list.deinit(allocator);

    // fill the data list with items
    for (0..data_list.capacity) |i| {
        data_list.appendAssumeCapacity(i);
    }

    send_channel = try BufferedChannel(usize).init(allocator, data_list.capacity);
    defer send_channel.deinit(allocator);

    receive_channel = try BufferedChannel(usize).init(allocator, data_list.capacity);
    defer receive_channel.deinit(allocator);

    const channel_send_title = try std.fmt.allocPrint(
        allocator,
        "send {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(channel_send_title);

    const channel_receive_title = try std.fmt.allocPrint(
        allocator,
        "receive {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(channel_receive_title);

    try bench.addParam(
        channel_send_title,
        &BenchmarkBufferedChannelSend.new(&data_list, &send_channel),
        .{
            .hooks = .{
                .before_each = beforeEachSend,
            },
        },
    );

    try bench.addParam(
        channel_receive_title,
        &BenchmarkBufferedChannelReceive.new(&data_list, &receive_channel),
        .{
            .hooks = .{
                .before_each = beforeEachReceive,
            },
        },
    );

    var stderr = std.fs.File.stderr().writerStreaming(&.{});
    const writer = &stderr.interface;

    try writer.writeAll("\n");
    try writer.writeAll("|----------------------------|\n");
    try writer.writeAll("| BufferedChannel Benchmarks |\n");
    try writer.writeAll("|----------------------------|\n");
    try bench.run(writer);
}
