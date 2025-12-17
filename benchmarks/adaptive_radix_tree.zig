const std = @import("std");
const stdx = @import("stdx");
const zbench = @import("zbench");

const assert = std.debug.assert;
const constants = @import("./constants.zig");
const testing = std.testing;

const uuid = @import("uuid");

const BENCH_ITERATIONS_OVERRIDE: u16 = 1;

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
            // std.debug.print("k: {s}\n", .{k});
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
var delete_int_art: AdaptiveRadixTree(usize) = undefined;
var delete_uuid_art: AdaptiveRadixTree(usize) = undefined;
var delete_word_art: AdaptiveRadixTree(usize) = undefined;
var lookup_int_art: AdaptiveRadixTree(usize) = undefined;
var lookup_uuid_art: AdaptiveRadixTree(usize) = undefined;
var lookup_word_art: AdaptiveRadixTree(usize) = undefined;
var art_int_data_list: std.ArrayList([]const u8) = .empty;
var art_uuid_data_list: std.ArrayList([]const u8) = undefined;
var art_word_data_list: std.ArrayList([]const u8) = undefined;

fn beforeEachARTInsert() void {
    // just nuke the tree completely
    insert_art.deinit(allocator);
    insert_art = AdaptiveRadixTree(usize).init(allocator);
}

fn beforeEachARTDeleteInt() void {
    for (art_int_data_list.items) |i| delete_int_art.insert(allocator, i, 0) catch unreachable;
}

fn beforeEachARTDeleteUUID() void {
    for (art_uuid_data_list.items) |i| delete_uuid_art.insert(allocator, i, 0) catch unreachable;
}

fn beforeEachARTDeleteWord() void {
    for (art_word_data_list.items) |i| delete_word_art.insert(allocator, i, 0) catch unreachable;
}

test "AdaptiveRadixTree benchmarks" {
    var bench = zbench.Benchmark.init(
        allocator,
        .{ .iterations = BENCH_ITERATIONS_OVERRIDE },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    art_int_data_list = try std.ArrayList([]const u8).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    );
    defer art_int_data_list.deinit(allocator);

    // fill the data list with items
    for (0..art_int_data_list.capacity) |i| {
        const key = try std.fmt.allocPrint(allocator, "{d}", .{i});
        art_int_data_list.appendAssumeCapacity(key);
    }
    defer for (art_int_data_list.items) |i| allocator.free(i);

    // Create a list of `n` length that will be used/reused by each benchmarking test
    art_uuid_data_list = .empty;
    defer art_uuid_data_list.deinit(allocator);

    // read a uuid file
    {
        // read the uuids from the file and insert them into the art_uuid_data_list
        const file = try std.fs.cwd().openFile("./uuid.txt", .{});
        defer file.close();

        const reader_buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(reader_buffer);

        var file_reader: std.fs.File.Reader = file.reader(reader_buffer);
        const reader = &file_reader.interface;

        var idx: usize = 0;
        const upper_limit: usize = 300_000;
        while (idx < upper_limit) : (idx += 1) {
            const bytes = reader.takeDelimiterExclusive('\n') catch break;
            const uid = try std.fmt.allocPrint(allocator, "{s}", .{bytes});

            try art_uuid_data_list.append(allocator, uid);
        }

        const uuids_read_from_file_count = art_uuid_data_list.items.len;
        assert(uuids_read_from_file_count > 0);
    }

    // read a word file
    {
        // read the words from the file and insert them into the art_word_data_list
        const file = try std.fs.cwd().openFile("./words.txt", .{});
        defer file.close();

        const reader_buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(reader_buffer);

        var file_reader: std.fs.File.Reader = file.reader(reader_buffer);
        const reader = &file_reader.interface;

        var idx: usize = 0;
        const upper_limit: usize = 300_000;
        while (idx < upper_limit) : (idx += 1) {
            const bytes = reader.takeDelimiterExclusive('\n') catch break;
            const word = try std.fmt.allocPrint(allocator, "{s}", .{bytes});

            try art_word_data_list.append(allocator, word);
        }

        const words_read_from_file_count = art_word_data_list.items.len;
        assert(words_read_from_file_count > 0);
    }

    // initialize the insert_art
    insert_art = AdaptiveRadixTree(usize).init(allocator);
    defer insert_art.deinit(allocator);

    const insert_title = try std.fmt.allocPrint(
        allocator,
        "insert {} items",
        .{art_int_data_list.items.len},
    );
    defer allocator.free(insert_title);

    try bench.addParam(
        insert_title,
        &BenchmarkAdaptiveRadixTreeInsert.new(&art_int_data_list, &insert_art),
        .{
            .hooks = .{
                .before_each = beforeEachARTInsert,
            },
        },
    );

    const insert_uuid_title = try std.fmt.allocPrint(
        allocator,
        "insert {} uuids",
        .{art_uuid_data_list.items.len},
    );
    defer allocator.free(insert_uuid_title);

    try bench.addParam(
        insert_uuid_title,
        &BenchmarkAdaptiveRadixTreeInsert.new(&art_uuid_data_list, &insert_art),
        .{
            .hooks = .{
                .before_each = beforeEachARTInsert,
            },
        },
    );

    const insert_word_title = try std.fmt.allocPrint(
        allocator,
        "insert {} words",
        .{art_word_data_list.items.len},
    );
    defer allocator.free(insert_word_title);

    try bench.addParam(
        insert_word_title,
        &BenchmarkAdaptiveRadixTreeInsert.new(&art_word_data_list, &insert_art),
        .{
            .hooks = .{
                .before_each = beforeEachARTInsert,
            },
        },
    );

    delete_int_art = AdaptiveRadixTree(usize).init(allocator);
    defer delete_int_art.deinit(allocator);

    delete_uuid_art = AdaptiveRadixTree(usize).init(allocator);
    defer delete_uuid_art.deinit(allocator);

    delete_word_art = AdaptiveRadixTree(usize).init(allocator);
    defer delete_word_art.deinit(allocator);

    const delete_int_title = try std.fmt.allocPrint(
        allocator,
        "delete {} items",
        .{art_int_data_list.items.len},
    );
    defer allocator.free(delete_int_title);

    try bench.addParam(
        delete_int_title,
        &BenchmarkAdaptiveRadixTreeDelete.new(&art_int_data_list, &delete_int_art),
        .{
            .hooks = .{
                .before_each = beforeEachARTDeleteInt,
            },
        },
    );

    const delete_uuid_title = try std.fmt.allocPrint(
        allocator,
        "delete {} uuids",
        .{art_uuid_data_list.items.len},
    );
    defer allocator.free(delete_uuid_title);

    try bench.addParam(
        delete_uuid_title,
        &BenchmarkAdaptiveRadixTreeDelete.new(&art_uuid_data_list, &delete_uuid_art),
        .{
            .hooks = .{
                .before_each = beforeEachARTDeleteUUID,
            },
        },
    );

    const delete_word_title = try std.fmt.allocPrint(
        allocator,
        "delete {} words",
        .{art_word_data_list.items.len},
    );
    defer allocator.free(delete_word_title);

    try bench.addParam(
        delete_word_title,
        &BenchmarkAdaptiveRadixTreeDelete.new(&art_word_data_list, &delete_word_art),
        .{
            .hooks = .{
                .before_each = beforeEachARTDeleteWord,
            },
        },
    );

    // initialize the lookup_int_art
    lookup_int_art = AdaptiveRadixTree(usize).init(allocator);
    defer lookup_int_art.deinit(allocator);

    // initialize the lookup_uuid_art
    lookup_uuid_art = AdaptiveRadixTree(usize).init(allocator);
    defer lookup_uuid_art.deinit(allocator);

    // initialize the lookup_word_art
    lookup_word_art = AdaptiveRadixTree(usize).init(allocator);
    defer lookup_word_art.deinit(allocator);

    // populate the lookup_art
    for (art_int_data_list.items) |int| try lookup_int_art.insert(allocator, int, 0);
    for (art_uuid_data_list.items) |uid| try lookup_uuid_art.insert(allocator, uid, 0);
    for (art_word_data_list.items) |word| {
        std.debug.print("word: {s}\n", .{word});

        try lookup_word_art.insert(allocator, word, 0);
    }

    const lookup_title = try std.fmt.allocPrint(
        allocator,
        "lookup {} items",
        .{art_int_data_list.items.len},
    );
    defer allocator.free(lookup_title);

    try bench.addParam(
        lookup_title,
        &BenchmarkAdaptiveRadixTreeLookup.new(&art_int_data_list, &lookup_int_art),
        .{},
    );

    const lookup_uuid_title = try std.fmt.allocPrint(
        allocator,
        "lookup {} uuids",
        .{art_uuid_data_list.items.len},
    );
    defer allocator.free(lookup_uuid_title);

    try bench.addParam(
        lookup_uuid_title,
        &BenchmarkAdaptiveRadixTreeLookup.new(&art_uuid_data_list, &lookup_uuid_art),
        .{},
    );

    const lookup_word_title = try std.fmt.allocPrint(
        allocator,
        "lookup {} words",
        .{art_word_data_list.items.len},
    );
    defer allocator.free(lookup_word_title);

    try bench.addParam(
        lookup_word_title,
        &BenchmarkAdaptiveRadixTreeLookup.new(&art_word_data_list, &lookup_word_art),
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
var hash_map_int_data_list: std.ArrayList([]const u8) = .empty;
var hash_map_uuid_data_list: std.ArrayList([]const u8) = .empty;
var hash_map_word_data_list: std.ArrayList([]const u8) = .empty;

fn beforeEachHashMapPut() void {
    // just nuke the hashmap completely
    put_hash_map.deinit(allocator);
    put_hash_map = .empty;
}

fn beforeEachHashMapRemove() void {
    // populate the get_hash_map
    for (hash_map_int_data_list.items) |i| remove_hash_map.put(allocator, i, 0) catch unreachable;
}

test "std.StringHashMapUnmanaged benchmarks" {
    var bench = zbench.Benchmark.init(
        allocator,
        .{ .iterations = BENCH_ITERATIONS_OVERRIDE },
    );
    defer bench.deinit();

    // Create a list of `n` length that will be used/reused by each benchmarking test
    hash_map_int_data_list = try std.ArrayList([]const u8).initCapacity(
        allocator,
        constants.benchmark_max_queue_data_list,
    );
    defer hash_map_int_data_list.deinit(allocator);

    // fill the data list with items
    for (0..hash_map_int_data_list.capacity) |i| {
        const key = try std.fmt.allocPrint(allocator, "{d}", .{i});
        hash_map_int_data_list.appendAssumeCapacity(key);
    }
    defer for (hash_map_int_data_list.items) |item| allocator.free(item);

    // Create a list of `n` length that will be used/reused by each benchmarking test
    hash_map_uuid_data_list = .empty;
    defer hash_map_uuid_data_list.deinit(allocator);

    // read from uuid file
    {
        // read the uuids from the file and insert them into the hash_map_uuid_data_list
        const file = try std.fs.cwd().openFile("./uuid.txt", .{});
        defer file.close();

        const reader_buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(reader_buffer);

        var file_reader: std.fs.File.Reader = file.reader(reader_buffer);
        const reader = &file_reader.interface;

        var idx: usize = 0;
        const upper_limit: usize = 300_000;
        while (idx < upper_limit) : (idx += 1) {
            const bytes = reader.takeDelimiterExclusive('\n') catch break;
            const uid = try std.fmt.allocPrint(allocator, "{s}", .{bytes});

            try hash_map_uuid_data_list.append(allocator, uid);
        }

        const uuids_read_from_file_count = hash_map_uuid_data_list.items.len;
        assert(uuids_read_from_file_count > 0);
    }

    // read from word file
    {
        // read the words from the file and insert them into the hash_map_word_data_list
        const file = try std.fs.cwd().openFile("./words.txt", .{});
        defer file.close();

        const reader_buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(reader_buffer);

        var file_reader: std.fs.File.Reader = file.reader(reader_buffer);
        const reader = &file_reader.interface;

        var idx: usize = 0;
        const upper_limit: usize = 300_000;
        while (idx < upper_limit) : (idx += 1) {
            const bytes = reader.takeDelimiterExclusive('\n') catch break;
            const word = try std.fmt.allocPrint(allocator, "{s}", .{bytes});

            try hash_map_word_data_list.append(allocator, word);
        }

        const words_read_from_file_count = hash_map_word_data_list.items.len;
        assert(words_read_from_file_count > 0);
    }

    // initialize the put_hash_map
    put_hash_map = .empty;
    defer put_hash_map.deinit(allocator);

    const put_title = try std.fmt.allocPrint(
        allocator,
        "put {} items",
        .{hash_map_int_data_list.items.len},
    );
    defer allocator.free(put_title);

    try bench.addParam(
        put_title,
        &BenchmarkStdStringHashMapUnamanagedPut.new(&hash_map_int_data_list, &put_hash_map),
        .{
            .hooks = .{
                .before_each = beforeEachHashMapPut,
            },
        },
    );

    const put_uuid_title = try std.fmt.allocPrint(
        allocator,
        "put {} uuids",
        .{hash_map_uuid_data_list.items.len},
    );
    defer allocator.free(put_uuid_title);

    try bench.addParam(
        put_uuid_title,
        &BenchmarkStdStringHashMapUnamanagedPut.new(&hash_map_uuid_data_list, &put_hash_map),
        .{
            .hooks = .{
                .before_each = beforeEachHashMapPut,
            },
        },
    );

    const put_word_title = try std.fmt.allocPrint(
        allocator,
        "put {} words",
        .{hash_map_word_data_list.items.len},
    );
    defer allocator.free(put_word_title);

    try bench.addParam(
        put_word_title,
        &BenchmarkStdStringHashMapUnamanagedPut.new(&hash_map_word_data_list, &put_hash_map),
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
        .{hash_map_int_data_list.items.len},
    );
    defer allocator.free(remove_title);

    try bench.addParam(
        remove_title,
        &BenchmarkStdStringHashMapUnamanagedRemove.new(&hash_map_int_data_list, &remove_hash_map),
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
    for (hash_map_int_data_list.items) |i| try get_hash_map.put(allocator, i, 0);

    const get_title = try std.fmt.allocPrint(
        allocator,
        "get {} items",
        .{hash_map_int_data_list.items.len},
    );
    defer allocator.free(get_title);

    try bench.addParam(
        get_title,
        &BenchmarkStdStringHashMapUnamanagedGet.new(&hash_map_int_data_list, &put_hash_map),
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
