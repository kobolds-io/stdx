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
      1. [Channels](#channels)
         1. [BufferedChannel](#bufferedchannel)
         2. [UnbufferedChannel](#unbufferedchannel)
      2. [Queues/Lists](#queues/lists)
         1. [ManagedQueue](#managedqueue)
         2. [UnmanagedQueue](#unmanagedqueue)
         3. [RingBuffer](#ringbuffer)
      3. [Memory Management](#memory-management)
         1. [MemoryPool](#memorypool)
      4. [IO](#io)

## Usage

Using `stdx` is just as simple as using any other `zig` dependency.

```zig
// import the library into your file
const stdx = @import("stdx");

fn main() !void {
    // your code
    // ....

    const memory_pool = try stdx.MemoryPool(i32).init(allocator, 200);
    defer memory_pool.deinit();

    // your code
    // ...
}

```

## Installation

You can install `stdx` just like any other `zig` dependency by editing your `build.zig.zon` file.

```zig
    .dependencies = .{
        .stdx = .{
            // the latest version of the library is v0.0.2
            .url = "https://github.com/kobolds-io/stdx/archive/refs/tags/v0.0.3.tar.gz",
            .hash = "",
        },
    },
```

run `zig build --fetch` to fetch the dependencies. Sometimes `zig` is helpful and it caches stuff for you in the `zig-cache` dir. Try deleting that directory if you see some issues.

## Organization

This library follows the organization of the `zig` `std` library. You will see familiar hierarchies like `stdx.mem` for memory stuff and `std.<DATA_STRUCTURE>` for other data structures. As I build this library out, I'll add more notes and documentation.

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
# with standard optimizations (debug build)
zig build bench

# or with more optimizations
zig build bench -Doptimize=ReleaseFast
```

Example output

```plaintext
--------------------------------------------------------
  Operating System: linux x86_64
  CPU:              13th Gen Intel(R) Core(TM) i9-13900K
  CPU Cores:        24
  Total Memory:     23.298GiB
--------------------------------------------------------

|-----------------------------|
| Buffered Channel Benchmarks |
|-----------------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995
-----------------------------------------------------------------------------------------------------------------------------
send 10000 items       65535    6.149s         93.836us ± 9.887us     (89.192us ... 755.86us)      93.717us   130.28us   138.843us
receive 10000 items    65535    5.344s         81.546us ± 8.283us     (78.145us ... 866.417us)     80.36us    112.495us  121.757us

|------------------------------|
| UnbufferedChannel Benchmarks |
|------------------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995
-----------------------------------------------------------------------------------------------------------------------------
send/receive 10000 ite 65535    19.382s        295.763us ± 140.08us   (281.687us ... 21.894ms)     297.234us  402.857us  432.895us

|-----------------------|
| RingBuffer Benchmarks |
|-----------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995
-----------------------------------------------------------------------------------------------------------------------------
enqueue 10000 items    65535    2.078s         31.718us ± 3.631us     (30.903us ... 360.939us)     30.944us   45.638us   51.682us
enqueueMany 10000 item 65535    2.079s         31.732us ± 7.786us     (30.932us ... 1.792ms)       30.974us   45.326us   50.923us
dequeue 10000 items    65535    1.038s         15.85us ± 2.855us      (15.444us ... 364.095us)     15.484us   26.034us   29.312us
dequeueMany 10000 item 65535    2.077s         31.695us ± 3.58us      (30.9us ... 388.306us)       30.958us   45.359us   50.952us
concatenate 10000 item 65535    2.141s         32.683us ± 12.849us    (30.991us ... 3.166ms)       32.186us   47.566us   54.159us
copy 10000 items       65535    2.19s          33.426us ± 17.359us    (30.98us ... 3.166ms)        33.306us   46.634us   52.152us
```

## Contributing

Please see [Contributing](./CONTRIBUTING.md) for more information on how to get involved.

## Code of Conduct

Please see the [Code of Conduct](./CODE_OF_CONDUCT.md) file. Simple library, simple rules.

---

# Documentation

## stdx

The `stdx` top level module. Directly contains data structures and is the parent module to modules like `io` and `net`.

### Channels

#### BufferedChannel

> added v0.0.3

The `BufferedChannel` is a structure that can be used to safely transmit data across threads. It uses a backing buffer which stores the actual values transmitted. Additionally it has a very simple api `send`/`receive` and supports concepts like cancellation and timeouts.

See [example](./examples/buffered_channel.zig) and [source](./src/buffered_channel.zig) for more information on usage.

#### UnbufferedChannel

> added v0.0.3

The `UnbufferedChannel` is a structure that can be used to safely transmit data across threads. It uses a `Condition` to notify receivers that there is new data. Additionally it has a very simple api `send`/`receive` and supports concepts like timeouts but does not currently support cancellation.

See [example](./examples/unbuffered_channel.zig) and [source](./src/unbuffered_channel.zig) for more information on usage.

### Queues/Lists

#### ManagedQueue

> added v0.0.2

The `ManagedQueue` is a generic queue implementation that uses a singly linked list. It allows for the management of a queue with operations like enqueueing, dequeueing, checking if the queue is empty, concatenating two queues, and handles the allocation/deallocation of memory used by the queue. The queue is managed by an allocator, which is used for creating and destroying nodes.

See [example](./examples/managed_queue.zig) and [source](./src/managed_queue.zig) for more information on usage.

#### UnmanagedQueue

> added v0.0.2

The `UnmanagedQueue` is a generic queue implementation that uses a singly linked list. It most closely represents the `std.SinglyLinkedList` in its functionality. Differing from the `ManagedQueue`, the `UnmanagedQueue` requires memory allocations to be external to the queue and provides a generic `Node` structure to help link everything together.

Please also see `UnmanagedQueueNode` which is the `Node` used by the `UnmanagedQueue`.

See [example](./examples/unmanaged_queue.zig) and [source](./src/unmanaged_queue.zig) for more information on usage.

#### RingBuffer

> added v0.0.1

A `RingBuffer` is a data structure that is really useful for managing memory in a fixed memory allocation. This particular implementation is particularly useful for a fixed size queue. Kobolds uses the `RingBuffer` data structure for inboxes and outboxes for when messages are received/sent through TCP connections.

See [example](./examples/ring_buffer.zig) and [source](./src/ring_buffer.zig) for more information on usage.

### Memory Management

#### MemoryPool

> added v0.0.1

A `MemoryPool` is a structure that uses pre-allocated blocks of memory to quickly allocoate and deallocate resources quickly. It is very useful in situations where you have statically allocated memory but you will have fluctuating usage of that memory. A good example would be handling messages flowing throughout a system.

See [example](./examples/memory_pool.zig) and [source](./src/memory_pool.zig) for more information on usage.

### IO

Module containing solutions for handling input and output
