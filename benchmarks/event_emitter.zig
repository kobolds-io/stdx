const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const EventEmitter = stdx.EventEmitter;

const TestEvent = enum {
    data_received,
    data_reset,
};

// const TestContext = struct {
// total_data_received: u128,
// };

const dataResetCallback = struct {
    fn callback(_: u128) void {
        // context.total_data_received = 0;
    }
}.callback;

const dataReceivedCallback = struct {
    fn callback(_: u128) void {
        // context.total_data_received += @intCast(data);
    }
}.callback;

const BenchmarkEventEmitterEmit = struct {
    const Self = @This();

    list: *std.ArrayList(usize),
    ee: *EventEmitter(TestEvent, u128),

    fn new(list: *std.ArrayList(usize), ee: *EventEmitter(TestEvent, u128)) Self {
        return .{
            .list = list,
            .ee = ee,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        // defer self.ee.emit(.data_reset, 0);

        for (self.list.items) |data| {
            self.ee.emit(.data_received, data);
        }
    }
};

var event_emitter_emit: EventEmitter(TestEvent, u128) = undefined;

var data_list: std.ArrayList(usize) = undefined;
const allocator = testing.allocator;

fn afterEach() void {}

test "EventEmitter benchmarks" {
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
    defer data_list.deinit();

    // fill the data list with items
    for (0..data_list.capacity) |i| {
        data_list.appendAssumeCapacity(@intCast(i));
    }

    const event_emitter_emit_title = try std.fmt.allocPrint(
        allocator,
        "emit {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(event_emitter_emit_title);

    event_emitter_emit = EventEmitter(TestEvent, u128).init(allocator);
    defer event_emitter_emit.deinit();

    try event_emitter_emit.addEventListener(.data_received, dataReceivedCallback);
    defer _ = event_emitter_emit.removeEventListener(.data_received, dataReceivedCallback);

    // register all the benchmark tests
    try bench.addParam(
        event_emitter_emit_title,
        &BenchmarkEventEmitterEmit.new(&data_list, &event_emitter_emit),
        .{
            .hooks = .{
                .after_each = afterEach,
            },
        },
    );

    // Write the results to stderr
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("\n");
    try stderr.writeAll("|-------------------------|\n");
    try stderr.writeAll("| EventEmitter Benchmarks |\n");
    try stderr.writeAll("|-------------------------|\n");
    try bench.run(stderr);
}
