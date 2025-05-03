const std = @import("std");
const testing = std.testing;

// const Event = enum {
//     Started,
//     Stopped,
//     Message,
// };
//
// const EventData = union(Event) {
//     Started: void,
//     Stopped: i32,
//     Message: []const u8,
// };

pub fn EventEmitter(
    comptime Event: type,
    comptime Context: type,
    comptime EventData: type,
) type {
    return struct {
        const Self = @This();

        pub const ListenerCallback = *const fn (event: Event, context: Context, data: EventData) void;

        pub const Listener = struct {
            context: Context,
            callback: ListenerCallback,
        };

        allocator: std.mem.Allocator,
        listeners: std.AutoHashMap(Event, *std.ArrayList(Listener)),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .listeners = std.AutoHashMap(Event, *std.ArrayList(Listener)).init(allocator),
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

        pub fn addEventListener(self: *Self, event: Event, context: Context, callback: ListenerCallback) !void {
            // self.mutex.lock();
            // defer self.mutex.unlock();

            if (self.listeners.get(event)) |listeners_list| {
                try listeners_list.append(.{ .context = context, .callback = callback });
            } else {
                // create a new list
                const listener_list = try self.allocator.create(std.ArrayList(Listener));
                errdefer self.allocator.destroy(listener_list);

                listener_list.* = try std.ArrayList(Listener).initCapacity(self.allocator, 1);
                errdefer listener_list.deinit();

                listener_list.appendAssumeCapacity(.{ .context = context, .callback = callback });

                try self.listeners.put(event, listener_list);
            }
        }

        pub fn removeEventListener(self: *Self, event: Event, callback: ListenerCallback) bool {
            // self.mutex.lock();
            // defer self.mutex.unlock();

            if (self.listeners.get(event)) |listener_list| {
                for (listener_list.items, 0..listener_list.items.len) |listener, i| {
                    if (listener.callback == callback) {
                        _ = listener_list.swapRemove(i);
                        return true;
                    }
                }
            }

            return false;
        }

        pub fn emit(self: *Self, data: EventData) void {
            const event = @as(Event, data);
            if (self.listeners.get(event)) |listener_list| {
                for (listener_list.items) |listener| {
                    listener.callback(event, listener.context, data);
                }
            }
        }
    };
}

const TestEnum = enum {
    data_sent,
    data_received,
};

test "init/deinit" {
    const allocator = testing.allocator;

    var ee = EventEmitter(TestEnum).init(allocator);
    defer ee.deinit();

    // try ee.addEventListener(.data_sent, dataSentCallback);
    // try ee.addEventListener(.data_received, dataReceivedCallback);
}
