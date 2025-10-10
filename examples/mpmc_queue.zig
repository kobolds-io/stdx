const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const BufferedChannel = stdx.BufferedChannel;
const UnbufferedChannel = stdx.UnbufferedChannel;
const CancellationToken = stdx.CancellationToken;
const RingBuffer = stdx.RingBuffer;
const log = std.log.scoped(.MPSCQueueExample);

const Dog = struct {
    name: []const u8,
    age: u8,
};

const sardine = Dog{
    .name = "sardine",
    .age = 4,
};

// This is the type that will be processed
const VALUE_TYPE: type = *const Dog;
const TOPIC_QUEUE_SIZE = 10_000;
const PRODUCER_QUEUE_SIZE = 5_0000;
const WORKER_QUEUE_SIZE = 5_000;
const ITERATIONS = 100_000;
const WORKER_COUNT = 100;
const PRODUCER_COUNT = 100;
const PRODUCER_BACKPRESSURE_MAX_CAPACITY = PRODUCER_QUEUE_SIZE * 10;

pub fn Topic(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex,
        queue: *RingBuffer(T),

        pub fn init(allocator: std.mem.Allocator) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, TOPIC_QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .allocator = allocator,
                .mutex = std.Thread.Mutex{},
                .queue = queue,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();

            self.allocator.destroy(self.queue);
        }
    };
}

pub fn Producer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        backpressure: std.array_list.Managed(VALUE_TYPE),
        close_channel: UnbufferedChannel(bool),
        id: usize,
        mutex: std.Thread.Mutex,
        produced_count: u128,
        queue: *RingBuffer(T),
        topic: *Topic(T),

        pub fn init(allocator: std.mem.Allocator, id: usize, topic: *Topic(T)) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, PRODUCER_QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .allocator = allocator,
                .backpressure = std.array_list.Managed(VALUE_TYPE).init(allocator),
                .close_channel = UnbufferedChannel(bool).new(),
                .id = id,
                .mutex = .{},
                .produced_count = 0,
                .queue = queue,
                .topic = topic,
            };
        }

        pub fn deinit(self: *Self) void {
            self.backpressure.deinit();
            self.queue.deinit();
            self.allocator.destroy(self.queue);
        }

        pub fn produce(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.queue.enqueue(value) catch {
                if (self.backpressure.items.len + 1 == PRODUCER_BACKPRESSURE_MAX_CAPACITY) {
                    log.err("producer: {} PRODUCER_BACKPRESSURE_MAX_CAPACITY reached: {}", .{
                        self.id,
                        PRODUCER_BACKPRESSURE_MAX_CAPACITY,
                    });
                    return error.BackpressureMaxCapacity;
                }
                try self.backpressure.append(value);
                return;
            };

            self.produced_count += 1;
        }

        pub fn tick(self: *Self) !void {
            // do nothing if there is nothing to do
            if (self.queue.count == 0) return;

            self.topic.mutex.lock();
            defer self.topic.mutex.unlock();

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.backpressure.items.len > 0) {
                const n = self.topic.queue.enqueueMany(self.backpressure.items);

                std.mem.copyForwards(VALUE_TYPE, self.backpressure.items, self.backpressure.items[n..]);
                self.backpressure.items.len -= n;
                self.produced_count += @intCast(n);
            }

            _ = self.topic.queue.concatenateAvailable(self.queue);
        }

        pub fn run(self: *Self, ready: *UnbufferedChannel(bool)) void {
            ready.send(true);
            while (true) {
                // check if we have received a signale to close the topic
                const signal = self.close_channel.tryReceive(0) catch false;
                if (signal) {
                    // log.info("signal received to stop producer {}", .{self.id});
                    // log.debug("producer {}: produced {} items", .{ self.id, self.produced_count });
                    return;
                }

                self.tick() catch unreachable;
                std.Thread.sleep(1 * std.time.ns_per_us);
            }
        }

        pub fn close(self: *Self) void {
            self.close_channel.send(true);
        }
    };
}

pub fn Worker(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        close_channel: UnbufferedChannel(bool),
        id: usize,
        processed_count: u128,
        queue: *RingBuffer(T),
        topic: *Topic(T),

        pub fn init(allocator: std.mem.Allocator, id: usize, topic: *Topic(T)) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, WORKER_QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .allocator = allocator,
                .close_channel = UnbufferedChannel(bool).new(),
                .id = id,
                .processed_count = 0,
                .queue = queue,
                .topic = topic,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
            self.allocator.destroy(self.queue);
        }

        pub fn tick(self: *Self) !void {
            self.topic.mutex.lock();
            defer self.topic.mutex.unlock();

            _ = self.queue.concatenateAvailable(self.topic.queue);
            while (self.queue.dequeue()) |_| {
                self.processed_count += 1;
            }
        }

        pub fn run(self: *Self, ready: *UnbufferedChannel(bool)) void {
            ready.send(true);
            while (true) {
                // check if we have received a signale to close the topic
                const signal = self.close_channel.tryReceive(0) catch false;
                if (signal) {
                    // log.err("signal received to stop worker {}", .{self.id});
                    // log.err("worker {}: processed {} items", .{ self.id, self.processed_count });
                    return;
                }

                self.tick() catch unreachable;
                std.Thread.sleep(1 * std.time.ns_per_us);
            }
        }

        pub fn close(self: *Self) void {
            self.close_channel.send(true);
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var topic = try Topic(VALUE_TYPE).init(allocator);
    defer topic.deinit();

    var producers = std.array_list.Managed(*Producer(VALUE_TYPE)).init(allocator);
    defer producers.deinit();

    var workers = std.array_list.Managed(*Worker(VALUE_TYPE)).init(allocator);
    defer workers.deinit();

    for (0..PRODUCER_COUNT) |i| {
        const producer = try allocator.create(Producer(VALUE_TYPE));
        errdefer allocator.destroy(producer);

        producer.* = try Producer(VALUE_TYPE).init(allocator, i, &topic);
        errdefer producer.deinit();

        try producers.append(producer);
    }

    for (0..WORKER_COUNT) |i| {
        const worker = try allocator.create(Worker(VALUE_TYPE));
        errdefer allocator.destroy(worker);

        worker.* = try Worker(VALUE_TYPE).init(allocator, i, &topic);
        errdefer worker.deinit();

        try workers.append(worker);
    }

    for (producers.items) |producer| {
        var ready_channel = UnbufferedChannel(bool).new();

        const th = try std.Thread.spawn(
            .{},
            Producer(VALUE_TYPE).run,
            .{ producer, &ready_channel },
        );
        th.detach();

        _ = ready_channel.receive();
        log.debug("producer {} ready", .{producer.id});
    }

    for (workers.items) |worker| {
        var ready_channel = UnbufferedChannel(bool).new();

        const th = try std.Thread.spawn(
            .{},
            Worker(VALUE_TYPE).run,
            .{ worker, &ready_channel },
        );
        th.detach();

        _ = ready_channel.receive();
        log.debug("worker {} ready", .{worker.id});
    }

    var timer = try std.time.Timer.start();
    const start = timer.read();

    for (0..ITERATIONS) |_| {
        for (producers.items) |producer| {
            producer.produce(&sardine) catch {
                log.err("producer: {} throttling", .{producer.id});
                std.Thread.sleep(100 * std.time.ns_per_ms);
                try producer.produce(&sardine);
            };
        }
    }

    var produced_count: u128 = 0;

    while (produced_count != ITERATIONS * PRODUCER_COUNT) {
        std.Thread.sleep(1 * std.time.ns_per_ms);
        produced_count = 0;
        for (producers.items) |producer| {
            produced_count += producer.produced_count;
        }
    }

    var processed_count: u128 = 0;
    while (processed_count != produced_count) {
        std.Thread.sleep(1 * std.time.ns_per_ms);
        processed_count = 0;
        for (workers.items) |worker| {
            processed_count += worker.processed_count;
        }
    }

    log.err("took {}ms, total iters {}, total processed {}, total produced {}", .{
        (timer.read() - start) / std.time.ns_per_ms,
        ITERATIONS,
        processed_count,
        produced_count,
    });

    const expected_processed = ITERATIONS * PRODUCER_COUNT;

    log.err("expected processed {}, actual processed {}, difference {}", .{
        expected_processed,
        processed_count,
        expected_processed - processed_count,
    });

    for (producers.items) |producer| {
        log.err("producer {} produced {}", .{ producer.id, producer.produced_count });
        producer.close();
        producer.deinit();
        allocator.destroy(producer);
    }

    for (workers.items) |worker| {
        log.err("worker {} processed {}", .{ worker.id, worker.processed_count });
        worker.close();
        worker.deinit();
        allocator.destroy(worker);
    }

    assert(processed_count == produced_count);
}
