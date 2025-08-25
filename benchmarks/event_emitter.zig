const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const EventEmitter = stdx.EventEmitter;

const TestEvent = enum {
    add,
    sub,
};

const TestContext = struct {
    const Self = @This();
    data: i128 = 0,

    pub fn onAdd(self: *Self, event: TestEvent, event_data: i128) void {
        assert(event == .add);

        self.data += event_data;
    }

    pub fn onSub(self: *Self, event: TestEvent, event_data: i128) void {
        assert(event == .sub);

        self.data -= event_data;
    }
};

const BenchmarkEventEmitterEmit = struct {
    const Self = @This();

    list: *std.array_list.Managed(usize),
    ee: *EventEmitter(TestEvent, *TestContext, i128),

    fn new(list: *std.array_list.Managed(usize), ee: *EventEmitter(TestEvent, *TestContext, i128)) Self {
        return .{
            .list = list,
            .ee = ee,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        for (self.list.items) |data| {
            self.ee.emit(.add, data);
        }
    }
};

var event_emitter_emit_1: EventEmitter(TestEvent, *TestContext, i128) = undefined;
var test_context_emit_1 = TestContext{};

var event_emitter_emit_10: EventEmitter(TestEvent, *TestContext, i128) = undefined;
var test_contexts_emit_10_list: std.array_list.Managed(*TestContext) = undefined;

var event_emitter_emit_100: EventEmitter(TestEvent, *TestContext, i128) = undefined;
var test_contexts_emit_100_list: std.array_list.Managed(*TestContext) = undefined;

var data_list: std.array_list.Managed(usize) = undefined;
const allocator = testing.allocator;

fn afterEachEmit1() void {
    test_context_emit_1.data = 0;
}

fn afterEachEmit10() void {
    for (test_contexts_emit_10_list.items) |test_context| {
        test_context.data = 0;
    }
}

fn afterEachEmit100() void {
    for (test_contexts_emit_100_list.items) |test_context| {
        test_context.data = 0;
    }
}

test "EventEmitter benchmarks" {
    var bench = zbench.Benchmark.init(
        std.testing.allocator,
        // .{ .iterations = 1 },
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
        data_list.appendAssumeCapacity(@intCast(i));
    }

    // setup event emitter emit to 1 listener test
    const event_emitter_emit_1_title = try std.fmt.allocPrint(
        allocator,
        "emit 1 listeners {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(event_emitter_emit_1_title);

    event_emitter_emit_1 = EventEmitter(TestEvent, *TestContext, i128).init(allocator);
    defer event_emitter_emit_1.deinit();

    try event_emitter_emit_1.addEventListener(&test_context_emit_1, .add, TestContext.onAdd);
    defer _ = event_emitter_emit_1.removeEventListener(&test_context_emit_1, .add, TestContext.onAdd);

    // setup event emitter emit to 10 listeners test
    const event_emitter_emit_10_title = try std.fmt.allocPrint(
        allocator,
        "emit 10 listeners {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(event_emitter_emit_10_title);

    event_emitter_emit_10 = EventEmitter(TestEvent, *TestContext, i128).init(allocator);
    defer event_emitter_emit_10.deinit();

    test_contexts_emit_10_list = std.array_list.Managed(*TestContext).init(allocator);
    defer test_contexts_emit_10_list.deinit();

    for (0..10) |_| {
        const test_context = try allocator.create(TestContext);
        errdefer allocator.destroy(test_context);

        test_context.* = TestContext{};

        try test_contexts_emit_10_list.append(test_context);

        try event_emitter_emit_10.addEventListener(test_context, .add, TestContext.onAdd);
        errdefer _ = event_emitter_emit_10.removeEventListener(test_context, .add, TestContext.onAdd);
    }

    defer {
        for (test_contexts_emit_10_list.items) |test_context| {
            _ = event_emitter_emit_10.removeEventListener(test_context, .add, TestContext.onAdd);
            allocator.destroy(test_context);
        }
    }

    // setup event emitter emit to 100 listeners test
    const event_emitter_emit_100_title = try std.fmt.allocPrint(
        allocator,
        "emit 100 listeners {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(event_emitter_emit_100_title);

    event_emitter_emit_100 = EventEmitter(TestEvent, *TestContext, i128).init(allocator);
    defer event_emitter_emit_100.deinit();

    test_contexts_emit_100_list = std.array_list.Managed(*TestContext).init(allocator);
    defer test_contexts_emit_100_list.deinit();

    for (0..100) |_| {
        const test_context = try allocator.create(TestContext);
        errdefer allocator.destroy(test_context);

        test_context.* = TestContext{};

        try test_contexts_emit_100_list.append(test_context);

        try event_emitter_emit_100.addEventListener(test_context, .add, TestContext.onAdd);
        errdefer _ = event_emitter_emit_100.removeEventListener(test_context, .add, TestContext.onAdd);
    }

    defer {
        for (test_contexts_emit_100_list.items) |test_context| {
            _ = event_emitter_emit_100.removeEventListener(test_context, .add, TestContext.onAdd);
            allocator.destroy(test_context);
        }
    }

    // register all the benchmark tests
    try bench.addParam(
        event_emitter_emit_1_title,
        &BenchmarkEventEmitterEmit.new(&data_list, &event_emitter_emit_1),
        .{
            .hooks = .{
                .after_each = afterEachEmit1,
            },
        },
    );
    try bench.addParam(
        event_emitter_emit_10_title,
        &BenchmarkEventEmitterEmit.new(&data_list, &event_emitter_emit_10),
        .{
            .hooks = .{
                .after_each = afterEachEmit10,
            },
        },
    );
    try bench.addParam(
        event_emitter_emit_100_title,
        &BenchmarkEventEmitterEmit.new(&data_list, &event_emitter_emit_100),
        .{
            .hooks = .{
                .after_each = afterEachEmit100,
            },
        },
    );

    var stderr = std.fs.File.stderr().writerStreaming(&.{});
    const writer = &stderr.interface;

    try writer.writeAll("\n");
    try writer.writeAll("|-------------------------|\n");
    try writer.writeAll("| EventEmitter Benchmarks |\n");
    try writer.writeAll("|-------------------------|\n");
    try bench.run(writer);
}
