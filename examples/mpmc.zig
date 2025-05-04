const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const BufferedChannel = stdx.BufferedChannel;
const UnbufferedChannel = stdx.UnbufferedChannel;
const CancellationToken = stdx.CancellationToken;
const RingBuffer = stdx.RingBuffer;
const log = std.log.scoped(.MPSCExample);

// This is the type that will be processed
const VALUE_TYPE: type = usize;
const TOPIC_QUEUE_SIZE = 50_000;
const PUBLISHER_QUEUE_SIZE = 5_000;
const SUBSCRIBER_QUEUE_SIZE = 5_000;
const ITERATIONS = 100_000;
const SUBSCRIBER_COUNT = 5;
const PUBLISHER_COUNT = 3;
const PUBLISHER_BACKPRESSURE_MAX_CAPACITY = PUBLISHER_QUEUE_SIZE * 10;

pub fn Topic(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        queue: *RingBuffer(T),
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, TOPIC_QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .allocator = allocator,
                .queue = queue,
                .mutex = std.Thread.Mutex{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();

            self.allocator.destroy(self.queue);
        }
    };
}

pub fn Publisher(comptime T: type) type {
    return struct {
        const Self = @This();
        id: usize,
        topic: *Topic(T),
        allocator: std.mem.Allocator,
        queue: *RingBuffer(T),
        published_count: u128,
        mutex: std.Thread.Mutex,
        close_channel: UnbufferedChannel(bool),
        backpressure: std.ArrayList(VALUE_TYPE),

        pub fn init(allocator: std.mem.Allocator, id: usize, topic: *Topic(T)) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, PUBLISHER_QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .id = id,
                .topic = topic,
                .queue = queue,
                .allocator = allocator,
                .published_count = 0,
                .mutex = .{},
                .close_channel = UnbufferedChannel(bool).new(),
                .backpressure = std.ArrayList(VALUE_TYPE).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.backpressure.deinit();
            self.queue.deinit();
            self.allocator.destroy(self.queue);
        }

        pub fn publish(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.queue.enqueue(value) catch {
                if (self.backpressure.items.len + 1 == PUBLISHER_BACKPRESSURE_MAX_CAPACITY) {
                    log.err("Publisher: {} PUBLISHER_BACKPRESSURE_MAX_CAPACITY reached: {}", .{
                        self.id,
                        PUBLISHER_BACKPRESSURE_MAX_CAPACITY,
                    });
                    return error.BackpressureMaxCapacity;
                }
                try self.backpressure.append(value);
                // log.err("publisher: {} adding value to backpressure", .{self.id});
                return;
            };

            self.published_count += 1;
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
                self.published_count += @intCast(n);
            }

            self.topic.queue.concatenateAvailable(self.queue);
        }

        pub fn run(self: *Self, ready: *UnbufferedChannel(bool)) void {
            ready.send(true);
            while (true) {
                // check if we have received a signale to close the topic
                const signal = self.close_channel.timedReceive(0) catch false;
                if (signal) {
                    // log.info("signal received to stop publisher {}", .{self.id});
                    // log.debug("publisher {}: published {} items", .{ self.id, self.published_count });
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

pub fn Subscriber(comptime T: type) type {
    return struct {
        const Self = @This();

        queue: *RingBuffer(T),
        topic: *Topic(T),
        id: usize,
        processed_count: u128,
        allocator: std.mem.Allocator,
        close_channel: UnbufferedChannel(bool),

        pub fn init(allocator: std.mem.Allocator, id: usize, topic: *Topic(T)) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, SUBSCRIBER_QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .allocator = allocator,
                .topic = topic,
                .id = id,
                .processed_count = 0,
                .queue = queue,
                .close_channel = UnbufferedChannel(bool).new(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
            self.allocator.destroy(self.queue);
        }

        pub fn tick(self: *Self) !void {
            self.topic.mutex.lock();
            defer self.topic.mutex.unlock();

            self.queue.concatenateAvailable(self.topic.queue);
            while (self.queue.dequeue()) |_| {
                self.processed_count += 1;
            }
        }

        pub fn run(self: *Self, ready: *UnbufferedChannel(bool)) void {
            ready.send(true);
            while (true) {
                // check if we have received a signale to close the topic
                const signal = self.close_channel.timedReceive(0) catch false;
                if (signal) {
                    // log.err("signal received to stop subscriber {}", .{self.id});
                    // log.err("subscriber {}: processed {} items", .{ self.id, self.processed_count });
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var topic = try Topic(VALUE_TYPE).init(allocator);
    defer topic.deinit();

    var publishers = std.ArrayList(*Publisher(VALUE_TYPE)).init(allocator);
    defer publishers.deinit();

    var subscribers = std.ArrayList(*Subscriber(VALUE_TYPE)).init(allocator);
    defer subscribers.deinit();

    for (0..PUBLISHER_COUNT) |i| {
        const publisher = try allocator.create(Publisher(VALUE_TYPE));
        errdefer allocator.destroy(publisher);

        publisher.* = try Publisher(VALUE_TYPE).init(allocator, i, &topic);
        errdefer publisher.deinit();

        try publishers.append(publisher);
    }

    for (0..SUBSCRIBER_COUNT) |i| {
        const subscriber = try allocator.create(Subscriber(VALUE_TYPE));
        errdefer allocator.destroy(subscriber);

        subscriber.* = try Subscriber(VALUE_TYPE).init(allocator, i, &topic);
        errdefer subscriber.deinit();

        try subscribers.append(subscriber);
    }

    for (publishers.items) |publisher| {
        var ready_channel = UnbufferedChannel(bool).new();

        const th = try std.Thread.spawn(
            .{},
            Publisher(VALUE_TYPE).run,
            .{ publisher, &ready_channel },
        );
        th.detach();

        _ = ready_channel.receive();
    }

    for (subscribers.items) |subscriber| {
        var ready_channel = UnbufferedChannel(bool).new();

        const th = try std.Thread.spawn(
            .{},
            Subscriber(VALUE_TYPE).run,
            .{ subscriber, &ready_channel },
        );
        th.detach();

        _ = ready_channel.receive();
    }

    var timer = try std.time.Timer.start();
    const start = timer.read();

    for (0..ITERATIONS) |_| {
        for (publishers.items) |publisher| {
            publisher.publish(publisher.id) catch {
                log.err("publisher: {} throttling", .{publisher.id});
                std.time.sleep(100 * std.time.ns_per_ms);
                try publisher.publish(publisher.id);
            };
        }
    }

    var published_count: u128 = 0;

    while (published_count != ITERATIONS * PUBLISHER_COUNT) {
        std.time.sleep(1 * std.time.ns_per_ms);
        published_count = 0;
        for (publishers.items) |publisher| {
            published_count += publisher.published_count;
        }
    }

    var processed_count: u128 = 0;
    while (processed_count != published_count) {
        std.time.sleep(1 * std.time.ns_per_ms);
        processed_count = 0;
        for (subscribers.items) |subscriber| {
            processed_count += subscriber.processed_count;
        }
    }

    log.err("took {}ms, total iters {}, total processed {}, total published {}", .{
        (timer.read() - start) / std.time.ns_per_ms,
        ITERATIONS,
        processed_count,
        published_count,
    });

    const expected_processed = ITERATIONS * PUBLISHER_COUNT;

    log.err("expected processed {}, actual processed {}, difference {}", .{
        expected_processed,
        processed_count,
        expected_processed - processed_count,
    });

    for (publishers.items) |publisher| {
        log.err("publisher {} published {}", .{ publisher.id, publisher.published_count });
        publisher.close();
    }

    for (subscribers.items) |subscriber| {
        log.err("subscriber {} processed {}", .{ subscriber.id, subscriber.processed_count });
        subscriber.close();
    }

    assert(processed_count == published_count);

    std.time.sleep(100 * std.time.ns_per_ms);
}
