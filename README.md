# stdx

**in development** this project is current in development and should be used at your own risk. Until there is a stable tagged release, be careful.

This is a library adding several genrally useful tools that are either not included in the standard library or have slightly different behavior.
As the `zig` programming language matures, we should get more and more awesome `std` library features but until then...

This is a zero-dependency project and is derived only for the existing `zig` `std` library.

# Table of Contents

1. [stdx](#stdx)
   1. [Usage](#usage)
   2. [Installation](#installation)
   3. [Library Organization](#library-organization)
   4. [Examples](#examples)
   5. [Data Structures](#data-structures)
      1. [MemoryPool](#memorypool)
      2. [RingBuffer](#ringbuffer)
      3. [ManagedQueue](#managedqueue)
      4. [UnmanagedQueue](#unmanagedqueue)

## Usage

... TODO

## Installation

... TODO

## Library Organization

This library follows the organization of the `zig` `std` library. You will see familiar hierarchies like `stdx.mem` for memory stuff and `std.RingBuffer` for other data structures. As I build this library out, I'll add more notes and documentation.

## Examples

There are examples included in this library that go over a brief overview of how each feature can be used. You can build and run examples by performing the following steps.

```bash
zig build examples

./zig-out/bin/<example_name>
```

Examples are best used if you modify the code and add print statements to figure out what is going on. Look at the source code files for additional tips on how features work by taking a look at the `test`s included in the source code.

## Data Structures

### MemoryPool

A memory pool is a structure that uses pre-allocated blocks of memory to quickly allocoate and deallocate resources quickly. It is very useful in situations where you have statically allocated memory but you will have fluctuating usage of that memory. A good example would be handling messages flowing throughout a system.

See [example](./examples/memory_pool.zig) and [source](./src/memory_pool.zig) for more information on usage.

### RingBuffer

A ring buffer is a data structure that is really useful for managing memory in a fixed memory allocation. This particular implementation is particularly useful for a fixed size queue. Kobolds uses the RingBuffer data structure for inboxes and outboxes for when messages are received/sent through TCP connections.

See [example](./examples/ring_buffer.zig) and [source](./src/ring_buffer.zig) for more information on usage.

### ManagedQueue

### UnmanagedQueue
