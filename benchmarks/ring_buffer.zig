const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const RingBuffer = stdx.RingBuffer;

const BenchmarkRingBufferEnqueue = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    ring_buffer: *RingBuffer(usize),

    fn new(list: *std.ArrayList(usize), ring_buffer: *RingBuffer(usize)) Self {
        return .{
            .list = list,
            .ring_buffer = ring_buffer,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        // enqueue every data point in the list into the ring buffer
        for (self.list.items) |data| {
            self.ring_buffer.enqueue(data) catch unreachable;
        }

        // drop ALL references immediately
        self.ring_buffer.reset();
    }
};

const BenchmarkRingBufferEnqueueMany = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    ring_buffer: *RingBuffer(usize),

    fn new(list: *std.ArrayList(usize), ring_buffer: *RingBuffer(usize)) Self {
        return .{
            .list = list,
            .ring_buffer = ring_buffer,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        // enqueue every data point in the list into the ring buffer
        const n = self.ring_buffer.enqueueMany(self.list.items);

        assert(n == self.list.items.len);

        // drop ALL references immediately
        self.ring_buffer.reset();
    }
};

const BenchmarkRingBufferDequeue = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    ring_buffer: *RingBuffer(usize),

    fn new(list: *std.ArrayList(usize), ring_buffer: *RingBuffer(usize)) Self {
        return .{
            .list = list,
            .ring_buffer = ring_buffer,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        while (self.ring_buffer.dequeue()) |_| {}
        assert(self.ring_buffer.isEmpty());
    }
};

const BenchmarkRingBufferDequeueMany = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    ring_buffer: *RingBuffer(usize),

    fn new(list: *std.ArrayList(usize), ring_buffer: *RingBuffer(usize)) Self {
        return .{
            .list = list,
            .ring_buffer = ring_buffer,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        const n = self.ring_buffer.dequeueMany(self.list.items);

        assert(self.ring_buffer.isEmpty());
        assert(n == self.list.items.len);
    }
};

const BenchmarkRingBufferConcatenate = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    ring_buffer: *RingBuffer(usize),
    ring_buffer_other: *RingBuffer(usize),

    fn new(list: *std.ArrayList(usize), ring_buffer: *RingBuffer(usize), ring_buffer_other: *RingBuffer(usize)) Self {
        return .{
            .list = list,
            .ring_buffer = ring_buffer,
            .ring_buffer_other = ring_buffer_other,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        const other_count = self.ring_buffer_other.count;
        self.ring_buffer.concatenate(self.ring_buffer_other) catch @panic("could not execute benchmark");
        assert(ring_buffer_concatenate.count == other_count);
    }
};

var ring_buffer_enqueue: RingBuffer(usize) = undefined;
var ring_buffer_enqueueMany: RingBuffer(usize) = undefined;
var ring_buffer_dequeue: RingBuffer(usize) = undefined;
var ring_buffer_dequeueMany: RingBuffer(usize) = undefined;
var ring_buffer_concatenate: RingBuffer(usize) = undefined;
var ring_buffer_concatenate_other: RingBuffer(usize) = undefined;

var data_list: std.ArrayList(usize) = undefined;
const allocator = testing.allocator;

fn beforeEachDequeue() void {
    // NOTE: we are gonna do some hacking here. This is simulating that the ring buffer has some
    // data inside of it but it simply does not. This operation should be almost instantaneos
    ring_buffer_dequeue.head = 0;
    ring_buffer_dequeue.tail = data_list.items.len;
    ring_buffer_dequeue.count = @intCast(data_list.items.len);

    // this is a sanity check
    assert(ring_buffer_dequeue.count <= ring_buffer_dequeue.capacity);
}

fn beforeEachDequeueMany() void {
    // NOTE: we are gonna do some hacking here. This is simulating that the ring buffer has some
    // data inside of it but it simply does not. This operation should be almost instantaneos
    ring_buffer_dequeueMany.head = 0;
    ring_buffer_dequeueMany.tail = data_list.items.len;
    ring_buffer_dequeueMany.count = @intCast(data_list.items.len);

    // this is a sanity check
    assert(ring_buffer_dequeueMany.count <= ring_buffer_dequeueMany.capacity);
}

fn beforeEachConcatenate() void {
    // NOTE: we are gonna do some hacking here. This is simulating that the ring buffer has some
    // data inside of it but it simply does not. This operation should be almost instantaneos
    ring_buffer_concatenate_other.head = 0;
    ring_buffer_concatenate_other.tail = data_list.items.len;
    ring_buffer_concatenate_other.count = @intCast(data_list.items.len);

    ring_buffer_concatenate.reset();

    // this is a sanity check
    assert(ring_buffer_concatenate.capacity <= ring_buffer_concatenate_other.count);
}

test "RingBuffer benchmarks" {
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

    // Initialize all ring buffers used in benchmarks
    ring_buffer_enqueue = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_enqueue.deinit();

    ring_buffer_enqueueMany = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_enqueueMany.deinit();

    ring_buffer_dequeue = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_dequeue.deinit();

    ring_buffer_dequeueMany = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_dequeueMany.deinit();

    ring_buffer_concatenate = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_concatenate.deinit();

    ring_buffer_concatenate_other = try RingBuffer(usize).init(allocator, @intCast(data_list.items.len));
    defer ring_buffer_concatenate_other.deinit();

    const ring_buffer_enqueue_title = try std.fmt.allocPrint(
        allocator,
        "enqueue {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(ring_buffer_enqueue_title);

    const ring_buffer_enqueueMany_title = try std.fmt.allocPrint(
        allocator,
        "enqueueMany {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(ring_buffer_enqueueMany_title);

    const ring_buffer_dequeue_title = try std.fmt.allocPrint(
        allocator,
        "dequeue {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(ring_buffer_dequeue_title);

    const ring_buffer_dequeueMany_title = try std.fmt.allocPrint(
        allocator,
        "dequeueMany {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(ring_buffer_dequeueMany_title);

    const ring_buffer_concatenate_title = try std.fmt.allocPrint(
        allocator,
        "concatenate {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(ring_buffer_concatenate_title);

    // register all the benchmark tests
    try bench.addParam(
        ring_buffer_enqueue_title,
        &BenchmarkRingBufferEnqueue.new(&data_list, &ring_buffer_enqueue),
        .{},
    );
    try bench.addParam(
        ring_buffer_enqueueMany_title,
        &BenchmarkRingBufferEnqueueMany.new(&data_list, &ring_buffer_enqueueMany),
        .{},
    );
    try bench.addParam(
        ring_buffer_dequeue_title,
        &BenchmarkRingBufferDequeue.new(&data_list, &ring_buffer_dequeue),
        .{
            .hooks = .{
                .before_each = beforeEachDequeue,
            },
        },
    );
    try bench.addParam(
        ring_buffer_dequeueMany_title,
        &BenchmarkRingBufferDequeueMany.new(&data_list, &ring_buffer_dequeueMany),
        .{
            .hooks = .{
                .before_each = beforeEachDequeueMany,
            },
        },
    );
    try bench.addParam(
        ring_buffer_concatenate_title,
        &BenchmarkRingBufferConcatenate.new(
            &data_list,
            &ring_buffer_concatenate,
            &ring_buffer_concatenate_other,
        ),
        .{
            .hooks = .{
                .before_each = beforeEachConcatenate,
            },
        },
    );

    // Write the results to stderr
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("\n");
    try stderr.writeAll("|-----------------------|\n");
    try stderr.writeAll("| RingBuffer Benchmarks |\n");
    try stderr.writeAll("|-----------------------|\n");
    try bench.run(stderr);
}
