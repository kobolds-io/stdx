const std = @import("std");
const log = std.log.scoped(.spsc_queue);
const assert = std.debug.assert;

const stdx = @import("stdx");

const SPSCQueue = stdx.SPSCQueue;

const Producer = struct {
    fn run(queue: *SPSCQueue(u64), total_items: usize) void {
        var i: u64 = 0;
        while (i < total_items) {
            // spin until space is available
            if (queue.enqueue(i)) {
                i += 1;
                continue;
            }
            log.debug("producer - queue full, waiting for space", .{});
        }
        log.debug("producer - produced {d} messages", .{total_items});
    }
};

const Consumer = struct {
    fn run(queue: *SPSCQueue(u64), total_items: usize) void {
        var expected: u64 = 0;
        while (expected < total_items) {
            if (queue.dequeue()) |val| {
                assert(val == expected);
                expected += 1;
            }
            log.debug("consumer - queue empty, waiting for new message", .{});
        }

        log.debug("consumer - consumed {d} messages", .{total_items});
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Queue is shared between threads
    var shared_q = try SPSCQueue(u64).init(allocator, 1024);
    defer shared_q.deinit(allocator);

    const total_items: u64 = 1_000_000;
    const producer = try std.Thread.spawn(.{}, Producer.run, .{ &shared_q, total_items });
    const consumer = try std.Thread.spawn(.{}, Consumer.run, .{ &shared_q, total_items });

    producer.join();
    consumer.join();

    log.info("transferred {d} messages between producer and consumer threads", .{total_items});
}
