const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const MemoryPool = stdx.MemoryPool;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // initialize a memory pool of i32s with a capacity of 100 items
    var memory_pool = try MemoryPool(i32).init(allocator, 100);
    defer memory_pool.deinit();

    // create a new ptr
    const ptr = try memory_pool.create();

    // verify the ptr type
    assert(@TypeOf(ptr) == *i32);

    // use your new pointer
    ptr.* = 12345;

    // check how many ptrs are available
    assert(memory_pool.available() == memory_pool.capacity - 1);

    // clean up your pointer
    memory_pool.destroy(ptr);
}
