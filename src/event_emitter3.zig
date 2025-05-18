const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.EventEmitter);
const assert = std.debug.assert;

pub fn EventEmitter(comptime Event: type, comptime Data: type) type {
    return struct {
        const Self = @This();

        const EventListener = *const fn (data: Data) void;

        allocator: std.mem.Allocator,
        event_listeners: std.AutoHashMap(Event, *std.ArrayList(EventListener)),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .event_listeners = std.AutoHashMap(Event, *std.ArrayList(EventListener)).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var event_listeners_iterator = self.event_listeners.valueIterator();
            while (event_listeners_iterator.next()) |entry| {
                const list = entry.*;
                list.deinit();
                self.allocator.destroy(list);
            }

            self.event_listeners.deinit();
        }

        pub fn addEventListener(self: *Self, event: Event, listener: EventListener) !void {
            if (self.event_listeners.get(event)) |entry| {
                try entry.append(listener);
            } else {
                const list = try self.allocator.create(std.ArrayList(EventListener));
                errdefer self.allocator.destroy(list);

                list.* = try std.ArrayList(EventListener).initCapacity(self.allocator, 1);
                errdefer list.deinit();

                list.appendAssumeCapacity(listener);

                try self.event_listeners.put(event, list);
            }
        }

        pub fn removeEventListener(self: *Self, event: Event, listener: EventListener) bool {
            if (self.event_listeners.get(event)) |listeners| {
                for (listeners.items, 0..listeners.items.len) |existing_listener, i| {
                    if (existing_listener == listener) {
                        _ = listeners.swapRemove(i);
                        return true;
                    }
                }
            }

            return false;
        }

        pub fn emit(self: *Self, event: Event, data: Data) void {
            if (self.event_listeners.get(event)) |listeners| {
                for (listeners.items) |listener| {
                    listener(data);
                }
            }
        }
    };
}

test "init/deinit" {
    const allocator = testing.allocator;

    var ee = EventEmitter(u32, u32).init(allocator);
    defer ee.deinit();
}

test "basic emit" {
    const allocator = testing.allocator;

    const TestEvent = enum {
        hello,
        world,
    };

    var ee = EventEmitter(TestEvent, u32).init(allocator);
    defer ee.deinit();

    const listener = struct {
        fn callback(data: u32) void {
            _ = data;
            // log.err("asdfasdf {}", .{data});
        }
    }.callback;

    try ee.addEventListener(.hello, listener);
    defer assert(ee.removeEventListener(.hello, listener));

    ee.emit(.hello, 123);
}
