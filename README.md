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
      2. [Events](#events)
         1. [EventEmitter](#eventemitter)
      3. [Queues/Lists](#queues/lists)
         1. [ManagedQueue](#managedqueue)
         2. [UnmanagedQueue](#unmanagedqueue)
         3. [RingBuffer](#ringbuffer)
      4. [Memory Management](#memory-management)
         1. [MemoryPool](#memorypool)

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
            .url = "https://github.com/kobolds-io/stdx/archive/refs/tags/v0.0.6.tar.gz",
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

**Note** Benchmarks are always a point of contention between everyone. One of my goals is to provision some hardware in the cloud that is consistently used as the hardware for all comparisons. Until then, you can run the code locally to test out your performance. These benchmarks are run inside of a virtual machine and the CPU is fully emulated. This means you will see better performance on your native machines.

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

|----------------------------|
| BufferedChannel Benchmarks |
|----------------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
send 10000 items       65535    5.965s         91.023us ± 7.508us     (89.18us ... 1.166ms)        90.997us   111.217us  121.943us 
receive 10000 items    65535    5.201s         79.371us ± 8.925us     (78.104us ... 1.877ms)       78.185us   97.073us   107.727us 

|-------------------------|
| EventEmitter Benchmarks |
|-------------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
emit 1 listeners 10000 65535    1.337s         20.41us ± 1.859us      (20.013us ... 120.505us)     20.133us   27.247us   30.298us  
emit 10 listeners 1000 65535    5.577s         85.106us ± 23.908us    (82.851us ... 5.995ms)       83.767us   105.897us  118.163us 
emit 100 listeners 100 65535    52.36s         798.966us ± 64.923us   (775.17us ... 8.91ms)        802.103us  865.649us  896.873us 

|-----------------------------|
| MemoryPool Benchmarks |
|-----------------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
create 10000 items     65535    10.735s        163.812us ± 86.3us     (155.554us ... 22.023ms)     166.003us  198.232us  209.304us 
unsafeCreate 10000 ite 65535    8.863s         135.245us ± 48.457us   (129.032us ... 10.55ms)      135.339us  163.31us   173.568us 

|-----------------------|
| RingBuffer Benchmarks |
|-----------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
enqueue 10000 items    65535    2.06s          31.443us ± 2.509us     (30.961us ... 238.007us)     30.994us   40.147us   44.321us  
enqueueMany 10000 item 65535    2.059s         31.421us ± 11.318us    (30.905us ... 2.85ms)        30.916us   39.47us    43.644us  
dequeue 10000 items    65535    1.026s         15.663us ± 1.6us       (15.445us ... 224.661us)     15.483us   21.639us   22.871us  
dequeueMany 10000 item 65535    2.06s          31.443us ± 22.549us    (30.902us ... 5.771ms)       30.941us   39.257us   42.487us  
concatenate 10000 item 65535    2.115s         32.283us ± 3.1us       (31.001us ... 260.724us)     31.789us   42.163us   45.938us  
copy 10000 items       65535    2.167s         33.08us ± 2.518us      (31.076us ... 224.525us)     33.543us   40.943us   44.441us  

|------------------------------|
| UnbufferedChannel Benchmarks |
|------------------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
send/receive 10000 ite 65535    18.802s        286.912us ± 19.327us   (281.686us ... 4.353ms)      288.182us  324.811us  336.871us
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

### Events

#### EventEmitter

> added v0.0.6

The `EventEmitter` is a tool for managing communications across callbacks. This is a very similar implementation to the nodejs event emitter class which is one of the fundemental building blocks for asynchronous events. The `EventEmitter` provides a simple(ish) api to register `Callback`s with appropriate `Context`s to be called when a specific `Event` is called. 

See [example](./examples/event_emitter.zig) and [source](./src/event_emitter.zig) for more information on usage.

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



