const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const SPSCQueue = stdx.SPSCQueue;

const BenchmarkSPSCQueueEnqueueDequeue = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    queue: *SPSCQueue(usize),

    fn new(list: *std.ArrayList(usize), queue: *SPSCQueue(usize)) Self {
        return .{
            .list = list,
            .queue = queue,
        };
    }

    pub fn run(self: *Self, _: std.mem.Allocator) void {
        for (self.list.items) |item| assert(self.queue.enqueue(item));
        var i: usize = 0;
        while (self.queue.dequeue()) |_| : (i += 1) {}
        assert(i == self.list.items.len);
    }
};

test "SPSCQueue benchmarks" {
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
        std.math.pow(u16, 2, 15),
    );
    defer data_list.deinit(allocator);

    // fill the data list with items
    for (0..data_list.capacity) |i| data_list.appendAssumeCapacity(i);

    var queue = try SPSCQueue(usize).init(allocator, data_list.items.len);
    defer queue.deinit(allocator);

    const spsc_queue_enqueue_dequeue_title = try std.fmt.allocPrint(
        allocator,
        "enqueue {} items",
        .{data_list.items.len},
    );
    defer allocator.free(spsc_queue_enqueue_dequeue_title);

    try bench.addParam(
        spsc_queue_enqueue_dequeue_title,
        &BenchmarkSPSCQueueEnqueueDequeue.new(&data_list, &queue),
        .{},
    );

    const stderr = std.Io.File.stderr();
    var stderr_writer = stderr.writerStreaming(io, &.{});
    const writer = &stderr_writer.interface;

    try writer.writeAll("\n");
    try writer.writeAll("|----------------------|\n");
    try writer.writeAll("| SPSCQueue Benchmarks |\n");
    try writer.writeAll("|----------------------|\n");
    try bench.run(io, stderr);
}
