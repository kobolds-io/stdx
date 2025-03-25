# Overview

**CAUTION** this project is current in development and should be used at your own risk. Until there is a stable tagged release, be careful.

This is a library adding several generally useful tools that are either not included in the standard library or have slightly different behavior. As the `zig` programming language matures, we should get more and more awesome `std` library features but until then...

All data structures, algorithms and utilities included in this library are written from scratch. This minimizes the threat of malicious or unintentional supply chain attacks. It also ensures that all code is controlled in a single place and HOPEFULLY minimizes the chance that `zig` turns into the hellish monstrocity that is `npm` and the `nodejs` ecosystem.

# Table of Contents

1. [Overview](#overview)
   1. [Usage](#usage)
   2. [Installation](#installation)
   3. [Organization](#organization)
   4. [Examples](#examples)
   5. [Benchmarks](#benchmarks)
   6. [Contributing](#contributing)
   7. [Code of Conduct](#code-of-conduct)
2. [Documentation](#documentation)
   1. [stdx](#stdx)
      1. [ManagedQueue](#managedqueue)
      2. [MemoryPool](#memorypool)
      3. [RingBuffer](#ringbuffer)
      4. [UnmanagedQueue](#unmanagedqueue)
      5. [IO](#io)

## Usage

Using `stdx` is just as simple as using any other `zig` dependency.

```zig
// import the library into your file
const stdx = @import("stdx");

fn main() !void {
    // your code
    // ....

    const memory_pool = stdx.MemoryPool(i32).init(allocator, 200);
    defer memory_pool.deinit();

    // your code
    // ...
}

```

## Installation

... TODO

## Organization

This library follows the organization of the `zig` `std` library. You will see familiar hierarchies like `stdx.mem` for memory stuff and `std.RingBuffer` for other data structures. As I build this library out, I'll add more notes and documentation.

## Examples

There are examples included in this library that go over a brief overview of how each feature can be used. You can build and run examples by performing the following steps. Examples are in the [examples](./examples/) directory. Examples are always welcome.

```bash
zig build examples

./zig-out/bin/<example_name>
```

Examples are best used if you modify the code and add print statements to figure out what is going on. Look at the source code files for additional tips on how features work by taking a look at the `test`s included in the source code.

## Benchmarks

There are benchmarks included in this library that you can run your local hardware or target hardware. You can run benchmarksby performing the following steps. Benchmarks are in the [benchmarks](./benchmarks/) directory. More benchmarks are always welcome. Benchmarks in this library are written using [`zbench`](https://github.com/hendriknielaender/zBench) by hendriknielander. Please check out that repo and star it and support other `zig` developers.

**Note** Benchmarks are always a point of contention between everyone. One of my goals is to provision some hardware in the cloud that is consistently used as the hardware for all comparisons. Until then, you can run the code locally to test out your performance.

```bash
zig build bench
```

Example output

```plaintext
--------------------------------------------------------
  Operating System: linux x86_64
  CPU:              13th Gen Intel(R) Core(TM) i9-13900K
  CPU Cores:        24
  Total Memory:     23.298GiB
--------------------------------------------------------

|-----------------------|
| RingBuffer Benchmarks |
|-----------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995
-----------------------------------------------------------------------------------------------------------------------------
enqueue 50000 items    65535    10.341s        157.795us ± 69.484us   (154.559us ... 16.834ms)     156.684us  184.294us  193.402us
enqueueMany 50000 item 65535    10.334s        157.688us ± 8.199us    (154.661us ... 590.616us)    157.991us  184.786us  194.115us
dequeue 50000 items    65535    10.303s        157.214us ± 10.164us   (154.466us ... 1.361ms)      154.634us  184.993us  195.988us
dequeueMany 50000 item 65535    5.153s         78.639us ± 41.379us    (77.23us ... 9.312ms)        77.279us   94.893us   104.777us
```

## Contributing

Please see [Contributing](./CONTRIBUTING.md) for more information on how to get involved.

## Code of Conduct

Please see the [Code of Conduct](./CONTRIBUTING.md) located within the CONTRIBUTING.md file.

---

# Documentation

## stdx

The `stdx` top level module. Directly contains data structures and is the parent module to modules like `io` and `net`.

### ManagedQueue

The `ManagedQueue` is a generic queue implementation that uses a singly linked list. It allows for the management of a queue with operations like enqueueing, dequeueing, checking if the queue is empty, concatenating two queues, and handles the allocation/deallocation of memory used by the queue. The queue is managed by an allocator, which is used for creating and destroying nodes.

See [example](./examples/managed_queue.zig) and [source](./src/managed_queue.zig) for more information on usage.

### MemoryPool

A `MemoryPool` is a structure that uses pre-allocated blocks of memory to quickly allocoate and deallocate resources quickly. It is very useful in situations where you have statically allocated memory but you will have fluctuating usage of that memory. A good example would be handling messages flowing throughout a system.

See [example](./examples/memory_pool.zig) and [source](./src/memory_pool.zig) for more information on usage.

### RingBuffer

A `RingBuffer` is a data structure that is really useful for managing memory in a fixed memory allocation. This particular implementation is particularly useful for a fixed size queue. Kobolds uses the `RingBuffer` data structure for inboxes and outboxes for when messages are received/sent through TCP connections.

See [example](./examples/ring_buffer.zig) and [source](./src/ring_buffer.zig) for more information on usage.

### UnmanagedQueue

The `UnmanagedQueue` is a generic queue implementation that uses a singly linked list. It most closely represents the `std.SinglyLinkedList` in its functionality. Differing from the `ManagedQueue`, the `UnmanagedQueue` requires memory allocations to be external to the queue and provides a generic `Node` structure to help link everything together.

Please also see `UnmanagedQueueNode` which is the `Node` used by the `UnmanagedQueue`.

See [example](./examples/unmanaged_queue.zig) and [source](./src/unmanaged_queue.zig) for more information on usage.

### IO

Module containing solutions for handling input and output
