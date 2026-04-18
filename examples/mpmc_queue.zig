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
const PRODUCER_QUEUE_SIZE = 5_000;
const WORKER_QUEUE_SIZE = 5_000;
const ITERATIONS = 100_000;
const WORKER_COUNT = 100;
const PRODUCER_COUNT = 100;
const PRODUCER_BACKPRESSURE_MAX_CAPACITY = PRODUCER_QUEUE_SIZE * 10;

pub fn Topic(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        mutex: std.Io.Mutex,
        queue: *RingBuffer(T),

        pub fn init(allocator: std.mem.Allocator) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).initCapacity(allocator, TOPIC_QUEUE_SIZE);
            errdefer queue.deinit(allocator);

            return Self{
                .allocator = allocator,
                .mutex = .init,
                .queue = queue,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit(self.allocator);

            self.allocator.destroy(self.queue);
        }
    };
}

pub fn Producer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        io: std.Io,
        backpressure: std.array_list.Managed(VALUE_TYPE),
        close_channel: UnbufferedChannel(bool),
        id: usize,
        mutex: std.Io.Mutex,
        produced_count: u128,
        queue: *RingBuffer(T),
        topic: *Topic(T),

        pub fn init(allocator: std.mem.Allocator, io: std.Io, id: usize, topic: *Topic(T)) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).initCapacity(allocator, PRODUCER_QUEUE_SIZE);
            errdefer queue.deinit(allocator);

            return Self{
                .allocator = allocator,
                .io = io,
                .backpressure = std.array_list.Managed(VALUE_TYPE).init(allocator),
                .close_channel = UnbufferedChannel(bool).new(io),
                .id = id,
                .mutex = .init,
                .produced_count = 0,
                .queue = queue,
                .topic = topic,
            };
        }

        pub fn deinit(self: *Self) void {
            self.backpressure.deinit();
            self.queue.deinit(self.allocator);
            self.allocator.destroy(self.queue);
        }

        pub fn produce(self: *Self, value: T) !void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            // this should really never happen unless the size of the allocator is fixed. So I've made it
            // fixed size for now.
            self.queue.enqueue(self.allocator, value) catch {
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

            self.topic.mutex.lockUncancelable(self.io);
            defer self.topic.mutex.unlock(self.io);

            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            if (self.backpressure.items.len > 0) {
                const n = self.backpressure.items.len - self.topic.queue.count;
                try self.topic.queue.enqueueSlice(self.allocator, self.backpressure.items);

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
                const signal = self.close_channel.tryReceive(.fromMilliseconds(0)) catch false;
                if (signal) {
                    // log.info("signal received to stop producer {}", .{self.id});
                    // log.debug("producer {}: produced {} items", .{ self.id, self.produced_count });
                    return;
                }

                self.tick() catch unreachable;
                std.Io.sleep(self.io, .fromMilliseconds(1), .awake) catch unreachable;
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
        io: std.Io,

        pub fn init(allocator: std.mem.Allocator, io: std.Io, id: usize, topic: *Topic(T)) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).initCapacity(allocator, WORKER_QUEUE_SIZE);
            errdefer queue.deinit(allocator);

            return Self{
                .allocator = allocator,
                .io = io,
                .close_channel = UnbufferedChannel(bool).new(io),
                .id = id,
                .processed_count = 0,
                .queue = queue,
                .topic = topic,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit(self.allocator);
            self.allocator.destroy(self.queue);
        }

        pub fn tick(self: *Self) !void {
            self.topic.mutex.lockUncancelable(self.io);
            defer self.topic.mutex.unlock(self.io);

            _ = self.queue.concatenateAvailable(self.topic.queue);
            while (self.queue.dequeue()) |_| {
                self.processed_count += 1;
            }
        }

        pub fn run(self: *Self, ready: *UnbufferedChannel(bool)) void {
            ready.send(true);
            while (true) {
                // check if we have received a signale to close the topic
                const signal = self.close_channel.tryReceive(.fromMilliseconds(0)) catch false;
                if (signal) {
                    // log.err("signal received to stop worker {}", .{self.id});
                    // log.err("worker {}: processed {} items", .{ self.id, self.processed_count });
                    return;
                }

                self.tick() catch unreachable;
                std.Io.sleep(self.io, .fromMilliseconds(1), .awake) catch unreachable;
            }
        }

        pub fn close(self: *Self) void {
            self.close_channel.send(true);
        }
    };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var topic_buf: [(@sizeOf(VALUE_TYPE) * TOPIC_QUEUE_SIZE) * 2]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&topic_buf);
    const topic_allocator = fba.allocator();

    var topic = try Topic(VALUE_TYPE).init(topic_allocator);
    defer topic.deinit();

    var producers = std.array_list.Managed(*Producer(VALUE_TYPE)).init(allocator);
    defer producers.deinit();

    var workers = std.array_list.Managed(*Worker(VALUE_TYPE)).init(allocator);
    defer workers.deinit();

    for (0..PRODUCER_COUNT) |i| {
        const producer = try allocator.create(Producer(VALUE_TYPE));
        errdefer allocator.destroy(producer);

        producer.* = try Producer(VALUE_TYPE).init(allocator, io, i, &topic);
        errdefer producer.deinit();

        try producers.append(producer);
    }

    for (0..WORKER_COUNT) |i| {
        const worker = try allocator.create(Worker(VALUE_TYPE));
        errdefer allocator.destroy(worker);

        worker.* = try Worker(VALUE_TYPE).init(allocator, io, i, &topic);
        errdefer worker.deinit();

        try workers.append(worker);
    }

    for (producers.items) |producer| {
        var ready_channel = UnbufferedChannel(bool).new(io);

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
        var ready_channel = UnbufferedChannel(bool).new(io);

        const th = try std.Thread.spawn(
            .{},
            Worker(VALUE_TYPE).run,
            .{ worker, &ready_channel },
        );
        th.detach();

        _ = ready_channel.receive();
        log.debug("worker {} ready", .{worker.id});
    }

    const start = std.Io.Timestamp.now(io, .awake);

    for (0..ITERATIONS) |_| {
        for (producers.items) |producer| {
            producer.produce(&sardine) catch {
                log.warn("producer: {} throttling", .{producer.id});
                std.Io.sleep(io, .fromMilliseconds(100), .awake) catch unreachable;
                try producer.produce(&sardine);
            };
        }
    }

    var produced_count: u128 = 0;

    while (produced_count != ITERATIONS * PRODUCER_COUNT) {
        std.Io.sleep(io, .fromMilliseconds(1), .awake) catch unreachable;
        produced_count = 0;
        for (producers.items) |producer| {
            produced_count += producer.produced_count;
        }
    }

    var processed_count: u128 = 0;
    while (processed_count != produced_count) {
        std.Io.sleep(io, .fromMilliseconds(1), .awake) catch unreachable;
        processed_count = 0;
        for (workers.items) |worker| {
            processed_count += worker.processed_count;
        }
    }

    const end = std.Io.Timestamp.now(io, .awake);
    log.info("took {}ms, total iters {}, total processed {}, total produced {}", .{
        @divTrunc(end.nanoseconds - start.nanoseconds, std.time.ns_per_ms),
        ITERATIONS,
        processed_count,
        produced_count,
    });

    const expected_processed = ITERATIONS * PRODUCER_COUNT;

    log.info("expected processed {}, actual processed {}, difference {}", .{
        expected_processed,
        processed_count,
        expected_processed - processed_count,
    });

    for (producers.items) |producer| {
        log.info("producer {} produced {}", .{ producer.id, producer.produced_count });
        producer.close();
        producer.deinit();
        allocator.destroy(producer);
    }

    for (workers.items) |worker| {
        log.info("worker {} processed {}", .{ worker.id, worker.processed_count });
        worker.close();
        worker.deinit();
        allocator.destroy(worker);
    }

    assert(processed_count == produced_count);
}
