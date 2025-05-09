const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const log = std.log.scoped(.Pool);

const RingBuffer = @import("./ring_buffer.zig").RingBuffer;

const Error = error{
    OutOfMemory,
};

/// A `MemoryPool` is a structure used to manage dynamic memory allocation.
/// It is a pre-allocated region of memory that is divided into fixed-size
/// blocks, which can be allocated and deallocated more efficiently than
/// using traditional methods like global allocators.
pub fn MemoryPool(comptime T: type) type {
    return struct {
        const Self = @This();
        /// The allocator responsible for managing memory allocations.
        ///
        /// It allows the memory pool to be flexible with how memory is allocated and deallocated,
        /// providing a customizable way to manage raw memory.
        allocator: std.mem.Allocator,
        /// A map that tracks memory blocks that are currently assigned.
        ///
        /// The map ensures that the pool does not mistakenly return or reuse memory blocks
        /// that are still in use, helping to track the current state of the pool's memory blocks.
        assigned_map: std.AutoHashMap(*T, bool),

        /// A list that holds the memory blocks allocated by the pool.
        ///
        /// The `backing_buffer` is used to hold blocks that can be reused when memory is freed
        /// or when the pool needs to allocate new blocks.
        backing_buffer: std.ArrayList(T),

        /// The total capacity of the memory pool.
        ///
        /// The capacity helps in managing memory limits and optimizing the pool's memory usage.
        capacity: usize,

        /// A ring buffer used to manage available memory blocks.
        ///
        /// The `free_list` is essential for efficiently recycling memory and reducing the
        /// overhead of repeated memory allocations.
        free_list: RingBuffer(*T),

        /// A mutex used for thread safe operations
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            assert(capacity > 0);

            var free_queue = try RingBuffer(*T).init(allocator, capacity);
            errdefer free_queue.deinit();

            var backing_buffer = try std.ArrayList(T).initCapacity(allocator, capacity);
            errdefer backing_buffer.deinit();

            for (0..capacity) |_| {
                // provide a zero value for the generic type so that it can
                // be used to fill the backing buffer.
                const p: T = undefined;

                backing_buffer.appendAssumeCapacity(p);
            }

            for (backing_buffer.items) |*v| {
                try free_queue.enqueue(v);
            }

            assert(backing_buffer.items.len == free_queue.count);

            return Self{
                .allocator = allocator,
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

        /// return the number assigned ptrs in the memory pool.
        pub fn count(self: *Self) usize {
            return self.assigned_map.count();
        }

        // return the number of free ptrs remaining in the memory pool.
        pub fn available(self: *Self) usize {
            return self.free_list.count;
        }

        /// Allocates a memory block from the memory pool. Threadsafe
        ///
        /// This function attempts to allocate a memory block from the pool by either
        /// reusing an existing block from the free list or failing if no memory is available.
        pub fn create(self: *Self) !*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.unsafeCreate();
        }

        /// Non thread safe version of `create`
        pub fn unsafeCreate(self: *Self) !*T {
            if (self.available() == 0) return Error.OutOfMemory;

            if (self.free_list.dequeue()) |ptr| {
                try self.assigned_map.put(ptr, true);

                return ptr;
            } else unreachable;
        }

        /// Allocates multiple memory blocks from the memory pool. Thread safe
        ///
        /// This function attempts to allocate `n` memory blocks from the pool. It will either
        /// reuse existing blocks from the free list or fail if the required number of blocks
        /// are not available.
        pub fn createN(self: *Self, allocator: std.mem.Allocator, n: usize) ![]*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.unsafeCreateN(allocator, n);
        }

        /// Unsafe version of `createN`.
        pub fn unsafeCreateN(self: *Self, allocator: std.mem.Allocator, n: usize) ![]*T {
            if (self.available() < n) return Error.OutOfMemory;

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

        /// Frees a memory block and returns it to the pool. Thread safe
        ///
        /// This function takes a pointer to a memory block previously allocated from the pool,
        /// removes it from the `assigned_map` to mark it as no longer in use, and then enqueues
        /// it back into the `free_list` for reuse.
        pub fn destroy(self: *Self, ptr: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.unsafeDestroy(ptr);
        }

        /// Unsafe version of `destroy`
        pub fn unsafeDestroy(self: *Self, ptr: *T) void {
            const res = self.assigned_map.remove(ptr);
            if (!res) {
                log.err("ptr did not exist in pool {*}", .{ptr});
                unreachable;
            }

            self.free_list.enqueue(ptr) catch @panic("could not enqueue");
        }
    };
}

test "init/deinit" {
    const allocator = testing.allocator;

    var memory_pool = try MemoryPool(usize).init(allocator, 100);
    defer memory_pool.deinit();
}

test "create and destroy" {
    const TestStruct = struct {
        data: usize = 0,
    };

    const allocator = testing.allocator;

    var memory_pool = try MemoryPool(TestStruct).init(allocator, 100);
    defer memory_pool.deinit();

    // create an ArrayList that will hold some pointers to be destroyed later
    var ptrs = std.ArrayList(*TestStruct).init(allocator);
    defer ptrs.deinit();

    // fill the entire memory pool
    for (0..memory_pool.available()) |i| {
        const p = try memory_pool.create();
        p.* = .{ .data = @intCast(i) };

        try ptrs.append(p);
    }

    try testing.expectEqual(0, memory_pool.available());
    try testing.expectError(Error.OutOfMemory, memory_pool.create());

    // remove one of the created items
    const removed_ptr = ptrs.pop().?;
    memory_pool.destroy(removed_ptr);

    try testing.expectEqual(1, memory_pool.available());

    // remove the rest of the items
    while (ptrs.pop()) |ptr| {
        memory_pool.destroy(ptr);
    }

    try testing.expectEqual(memory_pool.capacity, memory_pool.available());
}

test "data types" {
    const Person = struct {
        name: []const u8,
        age: u8,
    };

    const Roster = struct {
        people: []*Person,
        teams: [][]const u8,
    };

    const types = [_]type{
        u8,
        u16,
        u32,
        u64,
        u128,
        usize,
        i8,
        i16,
        i32,
        i64,
        i128,
        []u8,
        Person,
        Roster,
        *Person,
        *Roster,
    };

    const allocator = testing.allocator;

    inline for (0..types.len) |i| {
        var memory_pool = try MemoryPool(types[i]).init(allocator, 100);
        defer memory_pool.deinit();

        // create an ArrayList that will hold some pointers to be destroyed later
        var ptrs = std.ArrayList(*types[i]).init(allocator);
        defer ptrs.deinit();

        for (0..memory_pool.available()) |_| {
            const ptr = try memory_pool.create();

            try ptrs.append(ptr);
        }

        try testing.expectEqual(ptrs.items.len, memory_pool.capacity);
    }
}
