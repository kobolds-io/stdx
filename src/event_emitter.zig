const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

pub fn EventEmitter(
    comptime Event: type,
    comptime Context: type,
    comptime Data: type,
) type {
    return struct {
        const Self = @This();

        pub const ListenerCallback = *const fn (context: Context, event: Event, data: Data) void;

        pub const Listener = struct {
            context: Context,
            callback: ListenerCallback,
        };

        allocator: std.mem.Allocator,
        listeners: std.AutoHashMap(Event, *std.array_list.Managed(Listener)),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .listeners = std.AutoHashMap(Event, *std.array_list.Managed(Listener)).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var listeners_iter = self.listeners.valueIterator();
            while (listeners_iter.next()) |listener_list_ptr| {
                const listener_list = listener_list_ptr.*;

                // deinit and destroy the list
                listener_list.deinit();
                self.allocator.destroy(listener_list);
            }

            self.listeners.deinit();
        }

        pub fn addEventListener(self: *Self, context: Context, event: Event, callback: ListenerCallback) !void {
            if (self.listeners.get(event)) |listeners_list| {
                try listeners_list.append(.{ .context = context, .callback = callback });
            } else {
                // create a new list
                const listener_list = try self.allocator.create(std.array_list.Managed(Listener));
                errdefer self.allocator.destroy(listener_list);

                listener_list.* = try std.array_list.Managed(Listener).initCapacity(self.allocator, 1);
                errdefer listener_list.deinit();

                listener_list.appendAssumeCapacity(.{ .context = context, .callback = callback });

                try self.listeners.put(event, listener_list);
            }
        }

        pub fn removeEventListener(self: *Self, context: Context, event: Event, callback: ListenerCallback) bool {
            if (self.listeners.get(event)) |listener_list| {
                for (listener_list.items, 0..listener_list.items.len) |listener, i| {
                    if (listener.callback == callback and listener.context == context) {
                        _ = listener_list.swapRemove(i);
                        return true;
                    }
                }
            }

            return false;
        }

        pub fn emit(self: *Self, event: Event, data: Data) void {
            if (self.listeners.get(event)) |listener_list| {
                for (listener_list.items) |listener| {
                    listener.callback(listener.context, event, data);
                }
            }
        }
    };
}

const TestEvent = enum {
    data_sent,
    data_received,
};

const TestContext = struct {
    const Self = @This();
    data: u32,

    pub fn onDataSent(self: *Self, event: TestEvent, data: u32) void {
        assert(event == .data_sent);

        self.data = data;
    }
};

test "init/deinit" {
    const allocator = testing.allocator;

    var ee = EventEmitter(TestEvent, *TestContext, u32).init(allocator);
    defer ee.deinit();
}

test "basic emit" {
    const allocator = testing.allocator;

    var ee = EventEmitter(TestEvent, *TestContext, u32).init(allocator);
    defer ee.deinit();

    var test_context = TestContext{
        .data = 0,
    };

    try ee.addEventListener(&test_context, .data_sent, TestContext.onDataSent);
    defer _ = ee.removeEventListener(&test_context, .data_sent, TestContext.onDataSent);

    const want: u32 = 100;

    try testing.expectEqual(0, test_context.data);

    ee.emit(.data_sent, 100);

    try testing.expectEqual(want, test_context.data);
}
