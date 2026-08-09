const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const log = std.log.scoped(.Pool);

const RingBuffer = @import("./ring_buffer.zig").RingBuffer;

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

        /// A bitset that tracks memory blocks that are currently assigned.
        ///
        /// The bitset ensures that the pool does not mistakenly return or reuse memory slots
        /// that are still in use, helping to track the current state of the pool's memory slots.
        assigned_bits: std.DynamicBitSetUnmanaged,

        /// current count of the assigned pointers that have been created by this memory pool
        assigned_count: usize,

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
        mutex: std.Io.Mutex,

        /// The underlying io implementation
        io: std.Io,

        pub fn init(allocator: std.mem.Allocator, io: std.Io, capacity: usize) !Self {
            var free_list = try RingBuffer(*T).initCapacity(allocator, capacity);
            errdefer free_list.deinit(allocator);

            var backing_buffer = try std.ArrayList(T).initCapacity(allocator, capacity);
            errdefer backing_buffer.deinit(allocator);

            var assigned_bits = try std.DynamicBitSetUnmanaged.initEmpty(allocator, capacity);
            errdefer assigned_bits.deinit(allocator);

            for (0..capacity) |_| {
                // provide a zero value for the generic type so that it can
                // be used to fill the backing buffer.
                const p: T = undefined;

                backing_buffer.appendAssumeCapacity(p);
            }

            for (backing_buffer.items) |*v| free_list.enqueueAssumeCapacity(v);

            // if the backing buffer does not match the free queue, this means that the memory pool
            // will fundementally not work. We would have returned an allocation error already upon
            // creating the backing_buffer and the free_queue. This is purely a sanity check.
            assert(backing_buffer.items.len == free_list.count);
            assert(free_list.count == capacity);
            assert(assigned_bits.count() == 0);

            return Self{
                .allocator = allocator,
                .assigned_bits = assigned_bits,
                .assigned_count = 0,
                .capacity = capacity,
                .free_list = free_list,
                .backing_buffer = backing_buffer,
                .mutex = .init,
                .io = io,
            };
        }

        pub fn deinit(self: *Self) void {
            // NOTE: we could return a boolean here to denote if there is a value that leaked
            assert(self.assigned_count == 0);

            self.free_list.deinit(self.allocator);
            self.assigned_bits.deinit(self.allocator);
            self.backing_buffer.deinit(self.allocator);
        }

        /// return the number assigned ptrs in the memory pool.
        pub fn count(self: *Self) usize {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            return self.countUnsafe();
        }

        /// return the number assigned ptrs in the memory pool.
        pub fn countUnsafe(self: *Self) usize {
            return self.assigned_count;
        }

        /// return the number of free ptrs remaining in the memory pool.
        pub fn available(self: *Self) usize {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            return self.availableUnsafe();
        }

        /// Non thread safe version of `available`
        pub fn availableUnsafe(self: *Self) usize {
            return self.free_list.count;
        }

        /// Allocates a memory block from the memory pool. Threadsafe
        ///
        /// This function attempts to allocate a memory block from the pool by either
        /// reusing an existing block from the free list or failing if no memory is available.
        pub fn create(self: *Self) !*T {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            return self.unsafeCreate();
        }

        /// Non thread safe version of `create`
        pub fn unsafeCreate(self: *Self) !*T {
            const ptr = self.free_list.dequeue() orelse return error.OutOfMemory;
            const index = self.slotIndex(ptr).?;

            // guard to ensure that we are not overriding and existing ptr
            assert(!self.assigned_bits.isSet(index));

            self.assigned_bits.set(index);
            self.assigned_count += 1;

            return ptr;
        }

        /// Allocates multiple memory blocks from the memory pool. Thread safe
        ///
        /// This function attempts to allocate `n` memory blocks from the pool. It will either
        /// reuse existing blocks from the free list or fail if the required number of blocks
        /// are not available.
        pub fn createN(self: *Self, allocator: std.mem.Allocator, n: usize) ![]*T {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            return self.unsafeCreateN(allocator, n);
        }

        /// Unsafe version of `createN`.
        pub fn unsafeCreateN(self: *Self, allocator: std.mem.Allocator, n: usize) ![]*T {
            if (self.availableUnsafe() < n) return error.OutOfMemory;

            // create a small list
            var list = try std.ArrayList(*T).initCapacity(allocator, n);
            errdefer list.deinit(allocator);

            for (0..n) |_| {
                if (self.free_list.dequeue()) |ptr| {
                    const index = self.slotIndex(ptr).?;

                    // guard to ensure that we are not overriding and existing ptr
                    assert(!self.assigned_bits.isSet(index));

                    list.append(allocator, ptr) catch unreachable;

                    self.assigned_bits.set(index);
                    self.assigned_count += 1;
                } else break;
            }

            return list.toOwnedSlice(allocator);
        }

        /// Frees a memory block and returns it to the pool. Thread safe
        ///
        /// This function takes a pointer to a memory block previously allocated from the pool,
        /// removes it from the `assigned_map` to mark it as no longer in use, and then enqueues
        /// it back into the `free_list` for reuse.
        pub fn destroy(self: *Self, ptr: *T) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            return self.unsafeDestroy(ptr);
        }

        /// Unsafe version of `destroy`
        pub fn unsafeDestroy(self: *Self, ptr: *T) void {
            const index = self.slotIndex(ptr) orelse {
                log.err("ptr does not belong to this pool: {*}", .{ptr});
                unreachable;
            };

            if (!self.assigned_bits.isSet(index)) {
                log.err("ptr is not assigned or was already freed: {*}", .{ptr});
                unreachable;
            }

            self.assigned_bits.unset(index);
            self.assigned_count -= 1;

            self.free_list.enqueueAssumeCapacity(ptr);
        }

        // returns the index of the passed pointer is inside of the backing buffer
        fn slotIndex(self: *const Self, ptr: *T) ?usize {
            // get the location of the first item in the backing buffer
            const first = @intFromPtr(self.backing_buffer.items.ptr);

            // get the location of the target item
            const address = @intFromPtr(ptr);

            // capture the "step" size
            const item_size = @sizeOf(T);

            // get the last item in the backing buffer
            const end = first + (self.backing_buffer.items.len * item_size);

            // ensure that the item is within the memory pool
            if (address < first or address >= end) return null;

            // figure out the location of the target
            const offset = address - first;

            // the offset calculated is somehow not stepping to the same size of the item within
            if (offset % item_size != 0) return null;

            // return the index of where the item is in the backing buffer
            return offset / item_size;
        }
    };
}

test "init/deinit" {
    const allocator = testing.allocator;
    const io = testing.io;

    var memory_pool = try MemoryPool(usize).init(allocator, io, 100);
    defer memory_pool.deinit();
}

test "create and destroy" {
    const TestStruct = struct {
        data: usize = 0,
    };

    const allocator = testing.allocator;
    const io = testing.io;

    var memory_pool_create = try MemoryPool(TestStruct).init(allocator, io, 100);
    defer memory_pool_create.deinit();

    // create an ArrayList that will hold some pointers to be destroyed later
    var ptrs: std.ArrayList(*TestStruct) = .empty;
    defer ptrs.deinit(allocator);

    // fill the entire memory pool
    for (0..memory_pool_create.available()) |i| {
        const p = try memory_pool_create.create();
        p.* = .{ .data = @intCast(i) };

        try ptrs.append(allocator, p);
    }

    try testing.expectEqual(0, memory_pool_create.available());
    try testing.expectError(error.OutOfMemory, memory_pool_create.create());

    // remove one of the created items
    const removed_ptr = ptrs.pop().?;
    memory_pool_create.destroy(removed_ptr);

    try testing.expectEqual(1, memory_pool_create.available());

    // remove the rest of the items
    while (ptrs.pop()) |ptr| {
        memory_pool_create.destroy(ptr);
    }

    try testing.expectEqual(memory_pool_create.capacity, memory_pool_create.available());
}

test "create n ptrs" {
    const TestStruct = struct {
        data: usize = 0,
    };

    const allocator = testing.allocator;
    const io = testing.io;

    var memory_pool = try MemoryPool(TestStruct).init(allocator, io, 100);
    defer memory_pool.deinit();

    // create an ArrayList that will hold some pointers to be destroyed later
    var ptrs: std.ArrayList(*TestStruct) = .empty;
    defer ptrs.deinit(allocator);

    const p = try memory_pool.createN(allocator, 10);
    defer allocator.free(p);

    try testing.expectEqual(memory_pool.available(), memory_pool.capacity - p.len);

    for (p) |ptr| {
        memory_pool.destroy(ptr);
    }
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
    const io = testing.io;

    inline for (0..types.len) |i| {
        var memory_pool = try MemoryPool(types[i]).init(allocator, io, 100);
        defer memory_pool.deinit();

        // create an ArrayList that will hold some pointers to be destroyed later
        var ptrs: std.ArrayList(*types[i]) = .empty;
        defer ptrs.deinit(allocator);

        for (0..memory_pool.available()) |_| {
            const ptr = try memory_pool.create();

            try ptrs.append(allocator, ptr);
        }

        try testing.expectEqual(ptrs.items.len, memory_pool.capacity);

        // free all the pointers
        for (ptrs.items) |ptr| memory_pool.destroy(ptr);
    }
}
