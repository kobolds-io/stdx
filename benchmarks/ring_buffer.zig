const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const RingBuffer = stdx.RingBuffer;

const BenchmarkRingBufferEnqueue = struct {
    const Self = @This();

    data_list: *std.ArrayList(usize),
    ring_buffer: *RingBuffer(usize),

    fn new(data_list: *std.ArrayList(usize), ring_buffer: *RingBuffer(usize)) Self {
        return .{
            .data_list = data_list,
            .ring_buffer = ring_buffer,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        // enqueue every data point in the data_list into the ring buffer
        for (self.data_list.items) |data| {
            self.ring_buffer.enqueue(data) catch unreachable;
        }

        // drop ALL references immediately
        self.ring_buffer.reset();
    }
};

const BenchmarkRingBufferEnqueueMany = struct {
    const Self = @This();

    data_list: *std.ArrayList(usize),
    ring_buffer: *RingBuffer(usize),

    fn new(data_list: *std.ArrayList(usize), ring_buffer: *RingBuffer(usize)) Self {
        return .{
            .data_list = data_list,
            .ring_buffer = ring_buffer,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        // enqueue every data point in the data_list into the ring buffer
        const n = self.ring_buffer.enqueueMany(self.data_list.items);

        assert(n == self.data_list.items.len);

        // drop ALL references immediately
        self.ring_buffer.reset();
    }
};

const BenchmarkRingBufferDequeueMany = struct {
    const Self = @This();

    data_list: *std.ArrayList(usize),
    ring_buffer: *RingBuffer(usize),

    fn new(data_list: *std.ArrayList(usize), ring_buffer: *RingBuffer(usize)) Self {
        return .{
            .data_list = data_list,
            .ring_buffer = ring_buffer,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        // NOTE: we are gonna do some hacking here. This is simulating that the ring buffer has some
        // data inside of it but it simply does not. This operation should be almost instantaneos
        self.ring_buffer.head = 0;
        self.ring_buffer.tail = self.data_list.items.len;
        self.ring_buffer.count = @intCast(self.data_list.items.len);
        // this is a sanity check
        assert(self.ring_buffer.count <= self.ring_buffer.capacity);

        // actual testk
        while (self.ring_buffer.dequeue()) |_| {}
        assert(self.ring_buffer.isEmpty());
    }
};

const BenchmarkRingBufferDequeue = struct {
    const Self = @This();

    data_list: *std.ArrayList(usize),
    ring_buffer: *RingBuffer(usize),

    fn new(data_list: *std.ArrayList(usize), ring_buffer: *RingBuffer(usize)) Self {
        return .{
            .data_list = data_list,
            .ring_buffer = ring_buffer,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        // NOTE: we are gonna do some hacking here. This is simulating that the ring buffer has some
        // data inside of it but it simply does not. This operation should be almost instantaneos
        self.ring_buffer.head = 0;
        self.ring_buffer.tail = self.data_list.items.len;
        self.ring_buffer.count = @intCast(self.data_list.items.len);
        // this is a sanity check
        assert(self.ring_buffer.count <= self.ring_buffer.capacity);

        // actual test
        const n = self.ring_buffer.dequeueMany(self.data_list.items);

        assert(self.ring_buffer.isEmpty());
        assert(n == self.data_list.items.len);
    }
};

test "RingBuffer benchmarks" {
    const allocator = testing.allocator;

    var bench = zbench.Benchmark.init(
        std.testing.allocator,
        .{ .iterations = constants.benchmark_max_iterations },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    var data_list = std.ArrayList(usize).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    ) catch unreachable;
    defer data_list.deinit();

    // fill the data list with items
    for (0..data_list.capacity) |i| {
        data_list.appendAssumeCapacity(@intCast(i));
    }

    var ring_buffer_enqueue = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_enqueue.deinit();

    var ring_buffer_enqueueMany = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_enqueueMany.deinit();

    var ring_buffer_dequeue = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_dequeue.deinit();

    var ring_buffer_dequeueMany = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_dequeueMany.deinit();

    const ring_buffer_enqueue_title = try std.fmt.allocPrint(
        allocator,
        "enqueue {} items",
        .{constants.benchmark_max_queue_data_list},
    );

    const ring_buffer_enqueueMany_title = try std.fmt.allocPrint(
        allocator,
        "enqueueMany {} items",
        .{constants.benchmark_max_queue_data_list},
    );

    const ring_buffer_dequeue_title = try std.fmt.allocPrint(
        allocator,
        "dequeue {} items",
        .{constants.benchmark_max_queue_data_list},
    );

    const ring_buffer_dequeueMany_title = try std.fmt.allocPrint(
        allocator,
        "dequeueMany {} items",
        .{constants.benchmark_max_queue_data_list},
    );

    // register all the benchmark tests
    try bench.addParam(ring_buffer_enqueue_title, &BenchmarkRingBufferEnqueue.new(&data_list, &ring_buffer_enqueue), .{});
    try bench.addParam(ring_buffer_enqueueMany_title, &BenchmarkRingBufferEnqueueMany.new(&data_list, &ring_buffer_enqueueMany), .{});
    try bench.addParam(ring_buffer_dequeue_title, &BenchmarkRingBufferDequeue.new(&data_list, &ring_buffer_dequeue), .{});
    try bench.addParam(ring_buffer_dequeueMany_title, &BenchmarkRingBufferDequeueMany.new(&data_list, &ring_buffer_dequeueMany), .{});

    // Write the results to stderr
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("\n");
    try stderr.writeAll("|-----------------------|\n");
    try stderr.writeAll("| RingBuffer Benchmarks |\n");
    try stderr.writeAll("|-----------------------|\n");
    try bench.run(stderr);
}
