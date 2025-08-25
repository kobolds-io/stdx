const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const MemoryPool = @import("stdx").MemoryPool;

const BenchmarkMemoryPoolCreate = struct {
    const Self = @This();

    list: *std.array_list.Managed(usize),
    memory_pool: *MemoryPool(usize),

    fn new(list: *std.array_list.Managed(usize), memory_pool: *MemoryPool(usize)) Self {
        return .{
            .list = list,
            .memory_pool = memory_pool,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        for (self.list.items) |_| {
            _ = self.memory_pool.create() catch unreachable;
        }
    }
};

const BenchmarkMemoryPoolUnsafeCreate = struct {
    const Self = @This();

    list: *std.array_list.Managed(usize),
    memory_pool: *MemoryPool(usize),

    fn new(list: *std.array_list.Managed(usize), memory_pool: *MemoryPool(usize)) Self {
        return .{
            .list = list,
            .memory_pool = memory_pool,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        for (self.list.items) |_| {
            _ = self.memory_pool.unsafeCreate() catch unreachable;
        }
    }
};

var memory_pool_create: MemoryPool(usize) = undefined;
var memory_pool_unsafe_create: MemoryPool(usize) = undefined;

var data_list: std.array_list.Managed(usize) = undefined;
const allocator = testing.allocator;

fn beforeEachCreate() void {
    var assigned_iter = memory_pool_create.assigned_map.keyIterator();
    while (assigned_iter.next()) |entry| {
        const key = entry.*;

        memory_pool_create.unsafeDestroy(key);
    }
}

fn beforeEachUnsafeCreate() void {
    var assigned_key_iter = memory_pool_unsafe_create.assigned_map.keyIterator();
    while (assigned_key_iter.next()) |key_entry| {
        const key = key_entry.*;

        memory_pool_unsafe_create.unsafeDestroy(key);
    }
}

test "MemoryPool benchmarks" {
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

    memory_pool_create = try MemoryPool(usize).init(allocator, data_list.capacity);
    defer memory_pool_create.deinit();

    memory_pool_unsafe_create = try MemoryPool(usize).init(allocator, data_list.capacity);
    defer memory_pool_unsafe_create.deinit();

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
        &BenchmarkMemoryPoolCreate.new(&data_list, &memory_pool_create),
        .{
            .hooks = .{
                .before_each = beforeEachCreate,
            },
        },
    );
    try bench.addParam(
        memory_pool_unsafe_create_title,
        &BenchmarkMemoryPoolUnsafeCreate.new(&data_list, &memory_pool_unsafe_create),
        .{
            .hooks = .{
                .before_each = beforeEachUnsafeCreate,
            },
        },
    );

    // Write the results to stderr
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("\n");
    try stderr.writeAll("|-----------------------|\n");
    try stderr.writeAll("| MemoryPool Benchmarks |\n");
    try stderr.writeAll("|-----------------------|\n");
    try bench.run(stderr);
}
