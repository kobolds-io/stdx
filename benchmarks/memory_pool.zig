const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const MemoryPool = @import("stdx").MemoryPool;
const RingBuffer = @import("stdx").RingBuffer;

const BenchmarkMemoryPoolCreate = struct {
    const Self = @This();

    list: *std.array_list.Managed(usize),
    reclaim_queue: *RingBuffer(*usize),
    memory_pool: *MemoryPool(usize),

    fn new(
        list: *std.array_list.Managed(usize),
        memory_pool: *MemoryPool(usize),
        reclaim_queue: *RingBuffer(*usize),
    ) Self {
        return .{
            .list = list,
            .reclaim_queue = reclaim_queue,
            .memory_pool = memory_pool,
        };
    }

    pub fn run(self: *Self, _: std.mem.Allocator) void {
        for (self.list.items) |_| {
            const ptr = self.memory_pool.create() catch unreachable;
            self.reclaim_queue.enqueueAssumeCapacity(ptr);
        }
    }
};

const BenchmarkMemoryPoolUnsafeCreate = struct {
    const Self = @This();

    list: *std.array_list.Managed(usize),
    reclaim_queue: *RingBuffer(*usize),
    memory_pool: *MemoryPool(usize),

    fn new(
        list: *std.array_list.Managed(usize),
        memory_pool: *MemoryPool(usize),
        reclaim_queue: *RingBuffer(*usize),
    ) Self {
        return .{
            .list = list,
            .reclaim_queue = reclaim_queue,
            .memory_pool = memory_pool,
        };
    }

    pub fn run(self: *Self, _: std.mem.Allocator) void {
        for (self.list.items) |_| {
            const ptr = self.memory_pool.unsafeCreate() catch unreachable;
            self.reclaim_queue.enqueueAssumeCapacity(ptr);
        }
    }
};

var memory_pool_create: MemoryPool(usize) = undefined;
var memory_pool_unsafe_create: MemoryPool(usize) = undefined;

var data_list: std.array_list.Managed(usize) = undefined;
var reclaim_create_queue: RingBuffer(*usize) = undefined;
var reclaim_unsafe_create_queue: RingBuffer(*usize) = undefined;
const allocator = testing.allocator;

fn beforeEachCreate() void {
    while (reclaim_create_queue.dequeue()) |ptr| memory_pool_create.destroy(ptr);
}

fn afterAllCreate() void {
    while (reclaim_create_queue.dequeue()) |ptr| memory_pool_create.destroy(ptr);
}

fn beforeEachUnsafeCreate() void {
    while (reclaim_unsafe_create_queue.dequeue()) |ptr| memory_pool_unsafe_create.destroy(ptr);
}

fn afterAllUnsafeCreate() void {
    while (reclaim_unsafe_create_queue.dequeue()) |ptr| memory_pool_unsafe_create.destroy(ptr);
}

test "MemoryPool benchmarks" {
    const io = testing.io;
    var bench = zbench.Benchmark.init(
        std.testing.allocator,
        .{ .iterations = constants.benchmark_max_iterations },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    data_list = try std.array_list.Managed(usize).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    );
    defer data_list.deinit();

    // fill the data list with items
    for (0..data_list.capacity) |i| {
        data_list.appendAssumeCapacity(i);
    }

    memory_pool_create = try MemoryPool(usize).init(allocator, io, data_list.capacity);
    defer memory_pool_create.deinit();

    reclaim_create_queue = try RingBuffer(*usize).initCapacity(allocator, data_list.capacity);
    defer reclaim_create_queue.deinit(allocator);

    memory_pool_unsafe_create = try MemoryPool(usize).init(allocator, io, data_list.capacity);
    defer memory_pool_unsafe_create.deinit();

    reclaim_unsafe_create_queue = try RingBuffer(*usize).initCapacity(allocator, data_list.capacity);
    defer reclaim_unsafe_create_queue.deinit(allocator);

    const memory_pool_create_title = try std.fmt.allocPrint(
        allocator,
        "create {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(memory_pool_create_title);

    const memory_pool_unsafe_create_title = try std.fmt.allocPrint(
        allocator,
        "unsafeCreate {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(memory_pool_unsafe_create_title);

    try bench.addParam(
        memory_pool_create_title,
        &BenchmarkMemoryPoolCreate.new(&data_list, &memory_pool_create, &reclaim_create_queue),
        .{
            .hooks = .{
                .before_each = beforeEachCreate,
                .after_all = afterAllCreate,
            },
        },
    );
    try bench.addParam(
        memory_pool_unsafe_create_title,
        &BenchmarkMemoryPoolUnsafeCreate.new(&data_list, &memory_pool_unsafe_create, &reclaim_unsafe_create_queue),
        .{
            .hooks = .{
                .before_each = beforeEachUnsafeCreate,
                .after_all = afterAllUnsafeCreate,
            },
        },
    );

    const stderr = std.Io.File.stderr();
    var stderr_writer = stderr.writerStreaming(io, &.{});
    const writer = &stderr_writer.interface;

    try writer.writeAll("\n");
    try writer.writeAll("|-----------------------|\n");
    try writer.writeAll("| MemoryPool Benchmarks |\n");
    try writer.writeAll("|-----------------------|\n");
    try bench.run(io, stderr);
}
