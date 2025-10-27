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

        listeners: std.AutoHashMapUnmanaged(Event, *std.ArrayList(Listener)),

        pub fn new() Self {
            return Self.empty;
        }

        pub const empty = Self{
            .listeners = .empty,
        };

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            var listeners_iter = self.listeners.valueIterator();
            while (listeners_iter.next()) |listener_list_ptr| {
                const listener_list = listener_list_ptr.*;

                // deinit and destroy the list
                listener_list.deinit(allocator);
                allocator.destroy(listener_list);
            }

            self.listeners.deinit(allocator);
        }

        pub fn addEventListener(self: *Self, allocator: std.mem.Allocator, context: Context, event: Event, callback: ListenerCallback) !void {
            if (self.listeners.get(event)) |listeners_list| {
                try listeners_list.append(allocator, .{ .context = context, .callback = callback });
            } else {
                // create a new list
                const listener_list = try allocator.create(std.ArrayList(Listener));
                errdefer allocator.destroy(listener_list);

                listener_list.* = try std.ArrayList(Listener).initCapacity(allocator, 1);
                errdefer listener_list.deinit(allocator);

                listener_list.appendAssumeCapacity(.{ .context = context, .callback = callback });

                try self.listeners.put(allocator, event, listener_list);
            }
        }

        pub fn removeEventListener(self: *Self, context: Context, event: Event, callback: ListenerCallback) bool {
            if (self.listeners.get(event)) |listener_list| {
                for (listener_list.items, 0..listener_list.items.len) |listener, i| {
                    if (listener.callback == callback and listener.context == context) {
                        // TODO: figure out if this is a memory leak??
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

    var ee: EventEmitter(TestEvent, *TestContext, u32) = .empty;
    defer ee.deinit(allocator);
}

test "basic emit" {
    const allocator = testing.allocator;

    var ee: EventEmitter(TestEvent, *TestContext, u32) = .empty;
    defer ee.deinit(allocator);

    var test_context = TestContext{
        .data = 0,
    };

    try ee.addEventListener(allocator, &test_context, .data_sent, TestContext.onDataSent);
    defer _ = ee.removeEventListener(&test_context, .data_sent, TestContext.onDataSent);

    const want: u32 = 100;

    try testing.expectEqual(0, test_context.data);

    ee.emit(.data_sent, 100);

    try testing.expectEqual(want, test_context.data);
}
