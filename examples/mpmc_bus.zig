const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const BufferedChannel = stdx.BufferedChannel;
const UnbufferedChannel = stdx.UnbufferedChannel;
const CancellationToken = stdx.CancellationToken;
const RingBuffer = stdx.RingBuffer;
const log = std.log.scoped(.MPSCBusExample);

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
const BUS_QUEUE_SIZE = 1_000;
const PRODUCER_QUEUE_SIZE = 1_000;
const CONSUMER_QUEUE_SIZE = 1_000;
const ITERATIONS = 1_000;
const CONSUMER_COUNT = 10;
const PRODUCER_COUNT = 1;

pub fn doProduce(
    producers: *std.ArrayList(*Producer(VALUE_TYPE)),
    iterations: usize,
    value: VALUE_TYPE,
    ready_channel: *UnbufferedChannel(bool),
) void {
    ready_channel.send(true);
    for (0..iterations) |_| {
        var i: usize = 0;
        while (i < producers.items.len) {
            const producer = producers.items[i];

            // try to produce an item
            producer.produce(value) catch {
                // this producer is too fast
                std.time.sleep(1 * std.time.ns_per_ms);

                continue;
            };

            i += 1;
        }
    }
}

pub fn Bus(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex,
        queue: *RingBuffer(T),
        consumers: *std.ArrayList(*Consumer(T)),
        producers: *std.ArrayList(*Producer(T)),
        close_channel: UnbufferedChannel(bool),
        last_producer_index: usize,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, BUS_QUEUE_SIZE);
            errdefer queue.deinit();

            const consumers = try allocator.create(std.ArrayList(*Consumer(T)));
            errdefer allocator.destroy(consumers);

            consumers.* = std.ArrayList(*Consumer(T)).init(allocator);
            errdefer consumers.deinit();

            const producers = try allocator.create(std.ArrayList(*Producer(T)));
            errdefer allocator.destroy(producers);

            producers.* = std.ArrayList(*Producer(T)).init(allocator);
            errdefer producers.deinit();

            return Self{
                .allocator = allocator,
                .mutex = std.Thread.Mutex{},
                .queue = queue,
                .consumers = consumers,
                .producers = producers,
                .close_channel = UnbufferedChannel(bool).new(),
                .last_producer_index = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
            self.consumers.deinit();
            self.producers.deinit();

            self.allocator.destroy(self.queue);
            self.allocator.destroy(self.consumers);
            self.allocator.destroy(self.producers);
        }

        pub fn tick(self: *Self) !void {
            if (self.producers.items.len > 0) {
                self.mutex.lock();
                defer self.mutex.unlock();

                var processed: usize = 0;
                const producer_count = self.producers.items.len;

                while (processed < producer_count) : (processed += 1) {
                    const producer_index = (self.last_producer_index + processed) % producer_count;
                    const producer = self.producers.items[producer_index];

                    if (self.queue.available() == 0) {
                        log.debug("bus queue full producer index: {}", .{producer_index});

                        // next tick should resume from the next producer
                        self.last_producer_index = producer_index;
                        break;
                    }

                    producer.mutex.lock();
                    defer producer.mutex.unlock();

                    _ = self.queue.concatenateAvailable(producer.queue);
                }

                // If we completed the loop, set last index to the next producer
                if (processed == producer_count and self.queue.available() > 0) {
                    self.last_producer_index = (self.last_producer_index + 1) % producer_count;
                }
            }

            if (self.consumers.items.len > 0) {
                self.mutex.lock();
                defer self.mutex.unlock();

                var max_available = self.queue.count;
                for (self.consumers.items) |consumer| {
                    const consumer_available = consumer.queue.available();
                    if (consumer_available < max_available) {
                        max_available = consumer_available;
                    }
                }
            }

            // if there are no items in the queue, then there is nothing to do
            if (self.queue.count == 0) return;

            // if there are no consumers of the items on the bus, then there is no work to be done
            if (self.consumers.items.len == 0) return;

            // FIX: there should be a consumer mutex to ensure that the number of consumers remains constant throughout this tick
            const consumer_queues = try self.allocator.alloc(*RingBuffer(T), self.consumers.items.len);
            defer self.allocator.free(consumer_queues);

            self.mutex.lock();
            defer self.mutex.unlock();

            for (self.consumers.items, 0..self.consumers.items.len) |consumer, i| {
                consumer.mutex.lock();
                consumer_queues[i] = consumer.queue;
            }
            defer {
                for (self.consumers.items) |consumer| {
                    consumer.mutex.unlock();
                }
            }

            _ = self.queue.copyMaxToOthers(consumer_queues);
        }

        pub fn run(self: *Self, ready: *UnbufferedChannel(bool)) void {
            ready.send(true);
            while (true) {
                // check if we have received a signale to close the topic
                const signal = self.close_channel.tryReceive(0) catch false;
                if (signal) {
                    return;
                }

                self.tick() catch unreachable;
                std.time.sleep(1 * std.time.ns_per_us);
            }
        }

        pub fn close(self: *Self) void {
            self.close_channel.send(true);
        }
    };
}

pub fn Consumer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        close_channel: UnbufferedChannel(bool),
        id: usize,
        mutex: std.Thread.Mutex,
        consumed_count: u128,
        queue: *RingBuffer(T),
        bus: *Bus(T),

        pub fn init(allocator: std.mem.Allocator, id: usize, bus: *Bus(T)) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, CONSUMER_QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .allocator = allocator,
                .close_channel = UnbufferedChannel(bool).new(),
                .id = id,
                .mutex = .{},
                .consumed_count = 0,
                .queue = queue,
                .bus = bus,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();

            self.allocator.destroy(self.queue);
        }

        pub fn tick(self: *Self) !void {
            if (self.queue.count == 0) return;

            self.mutex.lock();
            defer self.mutex.unlock();

            // FIX: this is just some BS where the consumer is dropping the items and not
            // actually doing any work. This is an example so don't look to deeply into it.
            self.consumed_count += self.queue.count;
            self.queue.reset();
        }

        pub fn run(self: *Self, ready: *UnbufferedChannel(bool)) void {
            ready.send(true);
            while (true) {
                // check if we have received a signale to close the topic
                const signal = self.close_channel.tryReceive(0) catch false;
                if (signal) {
                    return;
                }

                self.tick() catch unreachable;
                std.time.sleep(1 * std.time.ns_per_us);
            }
        }

        pub fn close(self: *Self) void {
            self.close_channel.send(true);
        }
    };
}

pub fn Producer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        close_channel: UnbufferedChannel(bool),
        id: usize,
        mutex: std.Thread.Mutex,
        produced_count: u128,
        queue: *RingBuffer(T),

        pub fn init(allocator: std.mem.Allocator, id: usize) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, PRODUCER_QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .allocator = allocator,
                .close_channel = UnbufferedChannel(bool).new(),
                .id = id,
                .mutex = .{},
                .produced_count = 0,
                .queue = queue,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
            self.allocator.destroy(self.queue);
        }

        pub fn produce(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.queue.enqueue(value);

            self.produced_count += 1;
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var bus = try Bus(VALUE_TYPE).init(allocator);
    defer bus.deinit();

    var consumers = std.ArrayList(*Consumer(VALUE_TYPE)).init(allocator);
    defer consumers.deinit();

    var producers = std.ArrayList(*Producer(VALUE_TYPE)).init(allocator);
    defer producers.deinit();

    var bus_ready_channel = UnbufferedChannel(bool).new();

    const th = try std.Thread.spawn(
        .{},
        Bus(VALUE_TYPE).run,
        .{ &bus, &bus_ready_channel },
    );
    th.detach();

    _ = bus_ready_channel.receive();
    defer bus.close();

    std.time.sleep(500 * std.time.ns_per_ms);

    // spawn all the consumers
    for (0..CONSUMER_COUNT) |i| {
        const consumer = try allocator.create(Consumer(VALUE_TYPE));
        errdefer allocator.destroy(consumer);

        consumer.* = try Consumer(VALUE_TYPE).init(allocator, i, &bus);
        errdefer consumer.deinit();

        try consumers.append(consumer);

        var ready_channel = UnbufferedChannel(bool).new();

        const consumer_thread = try std.Thread.spawn(
            .{},
            Consumer(VALUE_TYPE).run,
            .{ consumer, &ready_channel },
        );
        consumer_thread.detach();

        _ = ready_channel.receive();
        errdefer consumer.close();

        bus.mutex.lock();
        defer bus.mutex.unlock();

        try bus.consumers.append(consumer);
    }

    // spawn all the producers
    for (0..PRODUCER_COUNT) |i| {
        const producer = try allocator.create(Producer(VALUE_TYPE));
        errdefer allocator.destroy(producer);

        producer.* = try Producer(VALUE_TYPE).init(allocator, i);
        errdefer producer.deinit();

        try producers.append(producer);

        bus.mutex.lock();
        defer bus.mutex.unlock();

        try bus.producers.append(producer);
    }

    // spawn all the consumers
    assert(bus.producers.items.len == PRODUCER_COUNT);
    assert(bus.consumers.items.len == CONSUMER_COUNT);

    var do_produce_ready_chan = UnbufferedChannel(bool).new();
    const do_produce_thread = try std.Thread.spawn(.{}, doProduce, .{ &producers, ITERATIONS, &sardine, &do_produce_ready_chan });
    do_produce_thread.detach();

    _ = do_produce_ready_chan.receive();

    // everything is setup now
    var timer = try std.time.Timer.start();
    const start = timer.read();

    var total_items_produced: u128 = 0;
    while (total_items_produced != ITERATIONS * PRODUCER_COUNT) {
        std.time.sleep(1 * std.time.ns_per_ms);
        total_items_produced = 0;
        for (producers.items) |producer| {
            total_items_produced += producer.produced_count;
        }
    }

    var total_items_consumed: u128 = 0;
    while (total_items_consumed != ITERATIONS * PRODUCER_COUNT * CONSUMER_COUNT) {
        std.time.sleep(1 * std.time.ns_per_ms);
        total_items_consumed = 0;
        for (consumers.items) |consumer| {
            total_items_consumed += consumer.consumed_count;
        }
    }

    log.err("took {}ms, total iters {}, total_items_produced {}, total_items_consumed {}", .{
        (timer.read() - start) / std.time.ns_per_ms,
        ITERATIONS,
        total_items_produced,
        total_items_consumed,
    });

    log.err("producer_count {}, consumer count {}", .{
        PRODUCER_COUNT,
        CONSUMER_COUNT,
    });

    // Clean up all of the producers
    for (producers.items) |producer| {
        // producer.close();
        producer.deinit();
        allocator.destroy(producer);
    }

    // Clean up all of the consumers
    for (consumers.items) |consumer| {
        // remove this consumer from the bus
        bus.mutex.lock();
        defer bus.mutex.unlock();

        for (bus.consumers.items, 0..bus.consumers.items.len) |bus_consumer, i| {
            if (consumer == bus_consumer) {
                _ = bus.consumers.swapRemove(i);
                break;
            }
        }

        consumer.close();
        consumer.deinit();
        allocator.destroy(consumer);
    }
}
