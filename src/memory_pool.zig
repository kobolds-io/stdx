const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const log = std.log.scoped(.Pool);

const RingBuffer = @import("./ring_buffer.zig").RingBuffer;

pub fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();

        assigned_map: std.AutoHashMap(*T, bool),
        capacity: u32,
        free_list: RingBuffer(*T),
        backing_buffer: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator, capacity: u32) !Self {
            assert(capacity > 0);

            var free_queue = try RingBuffer(*T).init(allocator, capacity);
            errdefer free_queue.deinit();

            var backing_buffer = try std.ArrayList(T).initCapacity(allocator, capacity);
            errdefer backing_buffer.deinit();

            for (0..capacity) |_| {
                backing_buffer.appendAssumeCapacity(0);
            }

            for (backing_buffer.items) |*v| {
                try free_queue.enqueue(v);
            }

            assert(backing_buffer.items.len == free_queue.count);

            return Self{
                .assigned_map = std.AutoHashMap(*T, bool).init(allocator),
                .capacity = capacity,
                .free_list = free_queue,
                .backing_buffer = backing_buffer,
            };
        }

        pub fn deinit(self: *Self) void {
            self.free_list.deinit();
            self.assigned_map.deinit();
            self.backing_buffer.deinit();
        }

        pub fn count(self: *Self) u32 {
            // this might be slow??
            return self.assigned_map.count();
        }

        pub fn available(self: *Self) u32 {
            return self.free_list.count;
        }

        pub fn create(self: *Self) !*T {
            if (self.available() == 0) return error.OutOfMemory;

            if (self.free_list.dequeue()) |ptr| {
                try self.assigned_map.put(ptr, true);

                return ptr;
            } else unreachable;
        }

        pub fn createN(self: *Self, allocator: std.mem.Allocator, n: u32) ![]*T {
            if (self.available() < n) return error.OutOfMemory;

            var list = try std.ArrayList(*T).initCapacity(allocator, n);
            errdefer list.deinit();

            for (0..n) |_| {
                if (self.free_list.dequeue()) |ptr| {
                    try list.append(ptr);
                    try self.assigned_map.put(ptr, true);
                } else break;
            }

            return list.toOwnedSlice();
        }

        pub fn destroy(self: *Self, ptr: *T) void {
            // free the ptr from the assinged queue and give it back to the unassigned queue
            const res = self.assigned_map.remove(ptr);
            if (!res) {
                log.err("ptr did not exist in pool {*}", .{ptr});
                unreachable;
            }

            self.free_list.enqueue(ptr) catch @panic("could not enqueue");
        }
    };
}
