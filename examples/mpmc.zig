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
const QUEUE_SIZE: usize = 10_000;
const ITERATIONS = 1_000_000;

pub fn Topic(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        queue: *RingBuffer(T),
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, QUEUE_SIZE);
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

        pub fn init(allocator: std.mem.Allocator, id: usize, topic: *Topic(T)) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .id = id,
                .topic = topic,
                .queue = queue,
                .allocator = allocator,
                .published_count = 0,
                .mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
            self.allocator.destroy(self.queue);
        }

        pub fn publish(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.queue.enqueue(value);
            self.published_count += 1;
        }

        pub fn tick(self: *Self) !void {
            // do nothing if there is nothing to do
            if (self.queue.count == 0) return;

            self.topic.mutex.lock();
            defer self.topic.mutex.unlock();

            self.mutex.lock();
            defer self.mutex.unlock();

            self.topic.queue.concatenateAvailable(self.queue);
            // log.debug("publisher: {} self.queue.count {}", .{ self.id, self.queue.count });
        }

        pub fn run(self: *Self, ready: *UnbufferedChannel(bool), close: *UnbufferedChannel(bool)) void {
            ready.send(true);
            while (true) {
                // check if we have received a signale to close the topic
                const signal = close.timedReceive(0) catch false;
                if (signal) {
                    log.info("signal received to stop publisher {}", .{self.id});
                    log.debug("publisher {}: published {} items", .{ self.id, self.published_count });
                    return;
                }

                self.tick() catch unreachable;
                std.time.sleep(1 * std.time.ns_per_us);
            }
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

        pub fn init(allocator: std.mem.Allocator, id: usize, topic: *Topic(T)) !Self {
            const queue = try allocator.create(RingBuffer(T));
            errdefer allocator.destroy(queue);

            queue.* = try RingBuffer(T).init(allocator, QUEUE_SIZE);
            errdefer queue.deinit();

            return Self{
                .allocator = allocator,
                .topic = topic,
                .id = id,
                .processed_count = 0,
                .queue = queue,
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

        pub fn run(self: *Self, ready: *UnbufferedChannel(bool), close: *UnbufferedChannel(bool)) void {
            ready.send(true);
            while (true) {
                // check if we have received a signale to close the topic
                const signal = close.timedReceive(0) catch false;
                if (signal) {
                    log.err("signal received to stop subscriber {}", .{self.id});
                    log.err("subscriber {}: processed {} items", .{ self.id, self.processed_count });
                    return;
                }

                self.tick() catch unreachable;
                std.time.sleep(1 * std.time.ns_per_us);
            }
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var topic = try Topic(VALUE_TYPE).init(allocator);
    defer topic.deinit();

    var publisher_1 = try Publisher(VALUE_TYPE).init(allocator, 1, &topic);
    defer publisher_1.deinit();

    var publisher_2 = try Publisher(VALUE_TYPE).init(allocator, 2, &topic);
    defer publisher_2.deinit();

    var subscriber_1 = try Subscriber(VALUE_TYPE).init(allocator, 1, &topic);
    defer subscriber_1.deinit();

    var subscriber_2 = try Subscriber(VALUE_TYPE).init(allocator, 2, &topic);
    defer subscriber_2.deinit();

    var subscriber_3 = try Subscriber(VALUE_TYPE).init(allocator, 3, &topic);
    defer subscriber_3.deinit();

    var subscriber_1_close_channel = UnbufferedChannel(bool).new();
    var subscriber_2_close_channel = UnbufferedChannel(bool).new();
    var subscriber_3_close_channel = UnbufferedChannel(bool).new();
    var publisher_1_close_channel = UnbufferedChannel(bool).new();
    var publisher_2_close_channel = UnbufferedChannel(bool).new();

    var subscriber_1_ready_channel = UnbufferedChannel(bool).new();
    var subscriber_2_ready_channel = UnbufferedChannel(bool).new();
    var subscriber_3_ready_channel = UnbufferedChannel(bool).new();
    var publisher_1_ready_channel = UnbufferedChannel(bool).new();
    var publisher_2_ready_channel = UnbufferedChannel(bool).new();

    const subscriber_1_thread = try std.Thread.spawn(
        .{},
        Subscriber(usize).run,
        .{ &subscriber_1, &subscriber_1_ready_channel, &subscriber_1_close_channel },
    );
    subscriber_1_thread.detach();
    const subscriber_2_thread = try std.Thread.spawn(
        .{},
        Subscriber(usize).run,
        .{ &subscriber_2, &subscriber_2_ready_channel, &subscriber_2_close_channel },
    );
    subscriber_2_thread.detach();

    const subscriber_3_thread = try std.Thread.spawn(
        .{},
        Subscriber(usize).run,
        .{ &subscriber_3, &subscriber_3_ready_channel, &subscriber_3_close_channel },
    );
    subscriber_3_thread.detach();

    const publisher_1_thread = try std.Thread.spawn(
        .{},
        Publisher(usize).run,
        .{ &publisher_1, &publisher_1_ready_channel, &publisher_1_close_channel },
    );
    publisher_1_thread.detach();
    const publisher_2_thread = try std.Thread.spawn(
        .{},
        Publisher(usize).run,
        .{ &publisher_2, &publisher_2_ready_channel, &publisher_2_close_channel },
    );
    publisher_2_thread.detach();

    _ = subscriber_1_ready_channel.receive();
    _ = subscriber_2_ready_channel.receive();
    _ = subscriber_3_ready_channel.receive();
    _ = publisher_1_ready_channel.receive();
    _ = publisher_2_ready_channel.receive();

    var timer = try std.time.Timer.start();
    const start = timer.read();

    for (0..ITERATIONS) |_| {
        publisher_1.publish(1) catch {
            log.err("publisher {} dropping", .{publisher_1.id});
            std.time.sleep(1 * std.time.ns_per_ms);
            continue;
        };
        publisher_2.publish(2) catch {
            log.err("publisher {} dropping", .{publisher_2.id});
            std.time.sleep(1 * std.time.ns_per_ms);
            continue;
        };
    }

    const published_count = publisher_1.published_count + publisher_2.published_count;
    var processed_count = subscriber_1.processed_count + subscriber_2.processed_count + subscriber_3.processed_count;

    while (processed_count != published_count) {
        std.time.sleep(1 * std.time.ns_per_ms);
        processed_count = subscriber_1.processed_count + subscriber_2.processed_count + subscriber_3.processed_count;
    }

    log.err("took {}ms, total iters {}, total processed {}, total published {}", .{
        (timer.read() - start) / std.time.ns_per_ms,
        ITERATIONS,
        processed_count,
        published_count,
    });

    const expected_processed = 2 * ITERATIONS;

    log.err("expected processed {}, actual processed {}, difference {}", .{
        expected_processed,
        processed_count,
        expected_processed - processed_count,
    });

    publisher_1_close_channel.send(true);
    publisher_2_close_channel.send(true);

    subscriber_1_close_channel.send(true);
    subscriber_2_close_channel.send(true);
    subscriber_3_close_channel.send(true);

    assert(processed_count == published_count);

    std.time.sleep(100 * std.time.ns_per_ms);
}
