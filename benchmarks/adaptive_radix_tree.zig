const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const AdaptiveRadixTree = stdx.AdaptiveRadixTree;

const BenchmarkAdaptiveRadixTreeInsert = struct {
    const Self = @This();

    list: *std.ArrayList([]const u8),
    art: *AdaptiveRadixTree(usize),

    fn new(list: *std.ArrayList([]const u8), art: *AdaptiveRadixTree(usize)) Self {
        return .{
            .list = list,
            .art = art,
        };
    }

    pub fn run(self: Self, alloc: std.mem.Allocator) void {
        for (self.list.items) |k| {
            self.art.insert(alloc, k, 0) catch unreachable;
        }
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var insert_art: AdaptiveRadixTree(usize) = undefined;
var data_list: std.ArrayList([]const u8) = .empty;

fn beforeEachInsert() void {
    // insert_art.deinit(allocator);
    // insert_art = AdaptiveRadixTree(usize).init(allocator);
    std.debug.print("pre art size: {}\n", .{insert_art.size});
    for (data_list.items) |k| {
        _ = insert_art.delete(allocator, k);
    }

    // std.debug.print("post art size: {}\n", .{insert_art.size});
    insert_art.prettyPrint(allocator) catch unreachable;
    // std.debug.assert(insert_art.size == 0);
}

test "AdaptiveRadixTree benchmarks" {
    var bench = zbench.Benchmark.init(
        allocator,
        .{ .iterations = 3 },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    data_list = try std.ArrayList([]const u8).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    );
    defer data_list.deinit(allocator);

    // fill the data list with items
    for (0..data_list.capacity) |i| {
        const key = try std.fmt.allocPrint(allocator, "{d}", .{i});
        data_list.appendAssumeCapacity(key);
    }
    defer for (data_list.items) |i| allocator.free(i);

    // initialize the insert_art
    insert_art = AdaptiveRadixTree(usize).init(allocator);
    defer insert_art.deinit(allocator);

    const insert_title = try std.fmt.allocPrint(
        allocator,
        "insert {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(insert_title);

    try bench.addParam(
        insert_title,
        &BenchmarkAdaptiveRadixTreeInsert.new(&data_list, &insert_art),
        .{
            .hooks = .{
                .before_each = beforeEachInsert,
            },
        },
    );

    var stderr = std.fs.File.stderr().writerStreaming(&.{});
    const writer = &stderr.interface;

    try writer.writeAll("\n");
    try writer.writeAll("|------------------------------|\n");
    try writer.writeAll("| AdaptiveRadixTree Benchmarks |\n");
    try writer.writeAll("|------------------------------|\n");
    try bench.run(writer);
}
