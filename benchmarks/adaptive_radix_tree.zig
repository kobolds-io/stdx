const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const BENCH_ITERATIONS_OVERRIDE: u16 = 1_000;

const AdaptiveRadixTree = stdx.AdaptiveRadixTree;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

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

const BenchmarkAdaptiveRadixTreeDelete = struct {
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
            assert(self.art.delete(alloc, k));
        }
    }
};

const BenchmarkAdaptiveRadixTreeLookup = struct {
    const Self = @This();

    list: *std.ArrayList([]const u8),
    art: *AdaptiveRadixTree(usize),

    fn new(list: *std.ArrayList([]const u8), art: *AdaptiveRadixTree(usize)) Self {
        return .{
            .list = list,
            .art = art,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        for (self.list.items) |k| {
            assert(self.art.lookup(k) != null);
        }
    }
};

var insert_art: AdaptiveRadixTree(usize) = undefined;
var delete_art: AdaptiveRadixTree(usize) = undefined;
var lookup_art: AdaptiveRadixTree(usize) = undefined;
var art_data_list: std.ArrayList([]const u8) = .empty;

fn beforeEachARTInsert() void {
    // just nuke the tree completely
    insert_art.deinit(allocator);
    insert_art = AdaptiveRadixTree(usize).init(allocator);
}

fn beforeEachARTDelete() void {
    // populate the delete_art
    for (art_data_list.items) |i| delete_art.insert(allocator, i, 0) catch unreachable;
}

test "AdaptiveRadixTree benchmarks" {
    var bench = zbench.Benchmark.init(
        allocator,
        .{ .iterations = BENCH_ITERATIONS_OVERRIDE },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    art_data_list = try std.ArrayList([]const u8).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    );
    defer art_data_list.deinit(allocator);

    // fill the data list with items
    for (0..art_data_list.capacity) |i| {
        const key = try std.fmt.allocPrint(allocator, "{d}", .{i});
        art_data_list.appendAssumeCapacity(key);
    }
    defer for (art_data_list.items) |i| allocator.free(i);

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
        &BenchmarkAdaptiveRadixTreeInsert.new(&art_data_list, &insert_art),
        .{
            .hooks = .{
                .before_each = beforeEachARTInsert,
            },
        },
    );

    const delete_title = try std.fmt.allocPrint(
        allocator,
        "delete {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(delete_title);

    try bench.addParam(
        insert_title,
        &BenchmarkAdaptiveRadixTreeDelete.new(&art_data_list, &delete_art),
        .{
            .hooks = .{
                .before_each = beforeEachARTDelete,
            },
        },
    );

    // initialize the lookup_art
    lookup_art = AdaptiveRadixTree(usize).init(allocator);
    defer lookup_art.deinit(allocator);

    // populate the lookup_art
    for (art_data_list.items) |i| try lookup_art.insert(allocator, i, 0);

    const lookup_title = try std.fmt.allocPrint(
        allocator,
        "lookup {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(lookup_title);

    try bench.addParam(
        insert_title,
        &BenchmarkAdaptiveRadixTreeLookup.new(&art_data_list, &insert_art),
        .{},
    );

    var stderr = std.fs.File.stderr().writerStreaming(&.{});
    const writer = &stderr.interface;

    try writer.writeAll("\n");
    try writer.writeAll("|------------------------------|\n");
    try writer.writeAll("| AdaptiveRadixTree Benchmarks |\n");
    try writer.writeAll("|------------------------------|\n");
    try bench.run(writer);
}

const BenchmarkStdStringHashMapUnamanagedPut = struct {
    const Self = @This();

    list: *std.ArrayList([]const u8),
    hash_map: *std.StringHashMapUnmanaged(usize),

    fn new(list: *std.ArrayList([]const u8), hash_map: *std.StringHashMapUnmanaged(usize)) Self {
        return .{
            .list = list,
            .hash_map = hash_map,
        };
    }

    pub fn run(self: Self, alloc: std.mem.Allocator) void {
        for (self.list.items) |k| {
            self.hash_map.put(alloc, k, 0) catch |e| {
                std.debug.print("e: {any}\n", .{e});
                unreachable;
            };
        }
    }
};

const BenchmarkStdStringHashMapUnamanagedRemove = struct {
    const Self = @This();

    list: *std.ArrayList([]const u8),
    hash_map: *std.StringHashMapUnmanaged(usize),

    fn new(list: *std.ArrayList([]const u8), hash_map: *std.StringHashMapUnmanaged(usize)) Self {
        return .{
            .list = list,
            .hash_map = hash_map,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        for (self.list.items) |k| {
            assert(self.hash_map.remove(k));
        }
    }
};

const BenchmarkStdStringHashMapUnamanagedGet = struct {
    const Self = @This();

    list: *std.ArrayList([]const u8),
    hash_map: *std.StringHashMapUnmanaged(usize),

    fn new(list: *std.ArrayList([]const u8), hash_map: *std.StringHashMapUnmanaged(usize)) Self {
        return .{
            .list = list,
            .hash_map = hash_map,
        };
    }

    pub fn run(self: Self, _: std.mem.Allocator) void {
        for (self.list.items) |k| {
            assert(self.hash_map.get(k) != null);
        }
    }
};

var put_hash_map: std.StringHashMapUnmanaged(usize) = undefined;
var remove_hash_map: std.StringHashMapUnmanaged(usize) = undefined;
var get_hash_map: std.StringHashMapUnmanaged(usize) = undefined;
var hash_map_data_list: std.ArrayList([]const u8) = .empty;

fn beforeEachHashMapPut() void {
    // just nuke the hashmap completely
    put_hash_map.deinit(allocator);
    put_hash_map = .empty;
}

fn beforeEachHashMapRemove() void {
    // populate the get_hash_map
    for (hash_map_data_list.items) |i| remove_hash_map.put(allocator, i, 0) catch unreachable;
}

test "std.StringHashMapUnmanaged benchmarks" {
    var bench = zbench.Benchmark.init(
        allocator,
        .{ .iterations = BENCH_ITERATIONS_OVERRIDE },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    hash_map_data_list = try std.ArrayList([]const u8).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    );
    defer hash_map_data_list.deinit(allocator);

    // fill the data list with items
    for (0..hash_map_data_list.capacity) |i| {
        const key = try std.fmt.allocPrint(allocator, "{d}", .{i});
        hash_map_data_list.appendAssumeCapacity(key);
    }
    defer for (hash_map_data_list.items) |item| allocator.free(item);

    // initialize the put_hash_map
    put_hash_map = .empty;
    defer put_hash_map.deinit(allocator);

    const put_title = try std.fmt.allocPrint(
        allocator,
        "put {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(put_title);

    try bench.addParam(
        put_title,
        &BenchmarkStdStringHashMapUnamanagedPut.new(&hash_map_data_list, &put_hash_map),
        .{
            .hooks = .{
                .before_each = beforeEachHashMapPut,
            },
        },
    );

    // initialize the remove_hash_map
    remove_hash_map = .empty;
    defer remove_hash_map.deinit(allocator);

    const remove_title = try std.fmt.allocPrint(
        allocator,
        "remove {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(remove_title);

    try bench.addParam(
        remove_title,
        &BenchmarkStdStringHashMapUnamanagedRemove.new(&hash_map_data_list, &remove_hash_map),
        .{
            .hooks = .{
                .before_each = beforeEachHashMapRemove,
            },
        },
    );

    // initialize the put_hash_map
    get_hash_map = .empty;
    defer get_hash_map.deinit(allocator);

    // populate the get_hash_map
    for (hash_map_data_list.items) |i| try get_hash_map.put(allocator, i, 0);

    const get_title = try std.fmt.allocPrint(
        allocator,
        "get {} items",
        .{constants.benchmark_max_queue_data_list},
    );
    defer allocator.free(get_title);

    try bench.addParam(
        put_title,
        &BenchmarkStdStringHashMapUnamanagedGet.new(&hash_map_data_list, &put_hash_map),
        .{},
    );

    var stderr = std.fs.File.stderr().writerStreaming(&.{});
    const writer = &stderr.interface;

    try writer.writeAll("\n");
    try writer.writeAll("|--------------------------------------|\n");
    try writer.writeAll("| std.StringHashMapUmanaged Benchmarks |\n");
    try writer.writeAll("|--------------------------------------|\n");
    try bench.run(writer);
}
