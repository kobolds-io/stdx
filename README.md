# Overview

This is a library adding several generally useful tools that are either not included in the standard library or have slightly different behavior. As the `zig` programming language matures, we should get more and more awesome `std` library features but until then...

All data structures, algorithms and utilities included in this library are written from scratch. This minimizes the threat of malicious or unintentional supply chain attacks. It also ensures that all code is controlled in a single place and HOPEFULLY minimizes the chance that `zig` turns into the hellish monstrocity that is `npm` and the `nodejs` ecosystem.

In general people use this library for the `RingBuffer` and the `MemoryPool` datastructures. See below for details.

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
      1. [BufferedChannel](#bufferedchannel)
      1. [UnbufferedChannel](#unbufferedchannel)
      1. [Signal](#signal)
      1. [EventEmitter](#eventemitter)
      1. [ManagedQueue](#managedqueue)
      1. [UnmanagedQueue](#unmanagedqueue)
      1. [RingBuffer](#ringbuffer)
      1. [SPSCQueue](#spscqueue)
      1. [MemoryPool](#memorypool)

## Usage

| zig version | stdx version |
|-------------|--------------|
| 0.15.x      | 0.2.1        |
| 0.16.0      | 0.3.0+       |


Using `stdx` is just as simple as using any other `zig` dependency.

```zig
// import the library into your file
const stdx = @import("stdx");

fn main(init: std.process.Init) !void {
    const io = init.io;
    // your code
    // ....

    const memory_pool = try stdx.MemoryPool(i32).init(allocator, io, 200);
    defer memory_pool.deinit();

    // your code
    // ...
}

```

## Installation

Install using zig fetch

```bash
zig fetch --save  https://gitlab.com/kobolds-io/stdx/-/archive/v0.4.0/stdx-v0.4.0.tar.gz
```

Alternatively, you can install `stdx` just like any other `zig` dependency by editing your `build.zig.zon` file.

```zig
    .dependencies = .{
        .stdx = .{
            .url = "https://gitlab.com/kobolds-io/stdx/-/archive/v0.4.0/stdx-v0.4.0.tar.gz",
            .hash = "<hash>",
        },
    },
```

run `zig build --fetch` to fetch the dependencies. This will return an error as the has will not match. Copy the new hash and try again.Sometimes `zig` is helpful and it caches stuff for you in the `zig-cache` dir. Try deleting that directory if you see some issues.

In the `build.zig` file add the library as a dependency.

```zig
// ...boilerplate

const stdx_dep = b.dependency("stdx", .{
    .target = target,
    .optimize = optimize,
});
const stdx_mod = stdx_dep.module("stdx");

exe.root_module.addImport("stdx", stdx_mod);
```

## Organization

This library organized as `stdx.<DataStructure/Algorithm>`. Very simple.

## Examples

There are examples included in this library that go over a brief overview of how each feature can be used. You can build and run examples by performing the following steps. Examples are in the [examples](./examples/) directory. Examples are always welcome.

```bash

# add optimization flags if you want ;)
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
zig build bench -Doptimize=ReleaseSafe
```

Example output

```plaintext
--------------------------------------------------------
  Operating System: linux x86_64
  CPU:              13th Gen Intel(R) Core(TM) i9-13900K
  CPU Cores:        20
  Total Memory:     15.231GiB
--------------------------------------------------------

|----------------------------|
| BufferedChannel Benchmarks |
|----------------------------|
benchmark             runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
----------------------------------------------------------------------------------------------------------------------------------
send 10000 items      65535    6.582s         100.443us ± 74.163us  (93.403us ... 17.685ms)      97.897us   158.247us  216.298us  
receive 10000 items   65535    5.486s         83.719us ± 39.086us   (78.145us ... 5.366ms)       80.685us   152.69us   210.89us   

|-------------------------|
| EventEmitter Benchmarks |
|-------------------------|
benchmark                        runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------------
emit 1 listeners 10000 items     1        42.919us       42.919us ± 0ns        (42.919us ... 42.919us)      42.919us   42.919us   42.919us   
emit 10 listeners 10000 items    1        108.16us       108.16us ± 0ns        (108.16us ... 108.16us)      108.16us   108.16us   108.16us   
emit 100 listeners 10000 items   1        965.921us      965.921us ± 0ns       (965.921us ... 965.921us)    965.921us  965.921us  965.921us  

|-----------------------|
| MemoryPool Benchmarks |
|-----------------------|
benchmark                  runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------
create 10000 items         65535    11.685s        178.314us ± 69.83us   (163.422us ... 7.901ms)      173.104us  355.144us  439.676us  
unsafeCreate 10000 items   65535    10.33s         157.633us ± 95.015us  (143.799us ... 21.987ms)     155.112us  231.164us  338.253us  

|-----------------------|
| RingBuffer Benchmarks |
|-----------------------|
benchmark                 runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
--------------------------------------------------------------------------------------------------------------------------------------
prepend 10000 items       65535    2.202s         33.611us ± 26.286us   (31.613us ... 2.555ms)       32.528us   53.687us   73.069us   
enqueue 10000 items       65535    2.068s         31.57us ± 21.238us    (29.733us ... 1.965ms)       30.485us   52.625us   77.973us   
enqueueMany 10000 items   65535    2.113s         32.257us ± 21.989us   (30.5us ... 2.584ms)         31.302us   50.415us   72.556us   
dequeue 10000 items       65535    2.129s         32.493us ± 24.179us   (30.902us ... 3.52ms)        31.545us   50.08us    69.156us   
dequeueMany 10000 items   65535    2.134s         32.569us ± 18.521us   (30.727us ... 1.878ms)       31.487us   53.854us   76.081us   
concatenate 10000 items   65535    2.213s         33.778us ± 17.403us   (30.984us ... 1.562ms)       32.912us   57.457us   79.33us    
copy 10000 items          65535    2.202s         33.607us ± 14.318us   (30.427us ... 1.347ms)       32.947us   55.995us   75.985us   
sort 10000 items          65535    31.83s         485.7us ± 319.158us   (445.451us ... 50.809ms)     481.307us  757.336us  929.362us  

|-------------------|
| Signal Benchmarks |
|-------------------|
benchmark                  runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------
send/receive 10000 items   65535    13.546s        206.71us ± 97.295us   (194.428us ... 20.028ms)     203.046us  300.959us  417.082us  

|----------------------|
| SPSCQueue Benchmarks |
|----------------------|
benchmark             runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
----------------------------------------------------------------------------------------------------------------------------------
enqueue 32768 items   65535    2.455s         37.462us ± 23.54us    (33.107us ... 2.457ms)       35.786us   63.421us   86.974us   

|------------------------------|
| UnbufferedChannel Benchmarks |
|------------------------------|
benchmark                  runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------
send/receive 10000 items   65535    22.004s        335.77us ± 172.052us  (304.268us ... 32.905ms)     333.293us  515.434us  629.298us  
```

## Contributing

Please see [Contributing](./CONTRIBUTING.md) for more information on how to get involved.

## Code of Conduct

Please see the [Code of Conduct](./CODE_OF_CONDUCT.md) file. Simple library, simple rules.

---

# Documentation

## stdx

The `stdx` top level module and should be imported as `const stdx = @import("stdx");` or importing structures directly using `const RingBuffer = @import("stdx").RingBuffer;`.

### BufferedChannel

> added v0.0.3 as `stdx.BufferedChannel`

The `BufferedChannel` is a structure that can be used to safely transmit data across threads. It uses a backing buffer which stores the actual values transmitted. Additionally it has a very simple api `send`/`receive` and supports concepts like cancellation and timeouts.

See [example](./examples/buffered_channel.zig) and [source](./src/buffered_channel.zig) for more information on usage.

### UnbufferedChannel

> added v0.0.3 as `stdx.UnbufferedChannel`

The `UnbufferedChannel` is a structure that can be used to safely transmit data across threads. It uses a `Condition` to notify receivers that there is new data. Additionally it has a very simple api `send`/`receive` and supports concepts like timeouts but does not currently support cancellation.

See [example](./examples/unbuffered_channel.zig) and [source](./src/unbuffered_channel.zig) for more information on usage.

### Signal

> added v0.0.8 as `stdx.Signal`

The `Signal` is a structure that can be used to safely transmit data across threads. Unlike a channel, it does not require that both threads become synchronized at the same point. Think of a `Signal` as a way for a sender to throw a value over the fence and a receiver to pick the value at a later time (when it is convenient for the receiver). `Signal`s are "one shots", meaning that they should only ever be used once. These structures are ideal for things like `request`->`reply` kinds of problems.

See [example](./examples/signal.zig) and [source](./src/signal.zig) for more information on usage.

### ManagedQueue

> added v0.0.2 as `stdx.ManagedQueue`

The `ManagedQueue` is a generic queue implementation that uses a singly linked list. It allows for the management of a queue with operations like enqueueing, dequeueing, checking if the queue is empty, concatenating two queues, and handles the allocation/deallocation of memory used by the queue. The queue is managed by an allocator, which is used for creating and destroying nodes.

See [example](./examples/managed_queue.zig) and [source](./src/managed_queue.zig) for more information on usage.

### UnmanagedQueue

> added v0.0.2 as `stdx.UnmanagedQueue`

The `UnmanagedQueue` is a generic queue implementation that uses a singly linked list. It most closely represents the `std.SinglyLinkedList` in its functionality. Differing from the `ManagedQueue`, the `UnmanagedQueue` requires memory allocations to be external to the queue and provides a generic `Node` structure to help link everything together.

Please also see `UnmanagedQueueNode` which is the `Node` used by the `UnmanagedQueue`.

See [example](./examples/unmanaged_queue.zig) and [source](./src/unmanaged_queue.zig) for more information on usage.

### RingBuffer

> added v0.0.1 as `stdx.RingBuffer`

A `RingBuffer` is a data structure that is really useful for managing memory in a fixed memory allocation. This particular implementation is particularly useful for a fixed size queue. Kobolds uses the `RingBuffer` data structure for inboxes and outboxes for when messages are received/sent through TCP connections.

See [example](./examples/ring_buffer.zig) and [source](./src/ring_buffer.zig) for more information on usage.


### SPSCQueue

> added v0.4.0 as `stdx.SPSCQueue`

SPSCQueue is a lock-free, atomic queue for passing data safely between one producer thread and one consumer thread. It behaves like a lightweight channel, but avoids locks and blocking, making it a good fit for high-throughput, one-way handoff between threads. Use it when data only needs to flow in one direction and you want predictable, low-overhead communication.

See [example](./examples/spsc_queue.zig) and [source](./src/spsc_queue.zig) for more information on usage.

### MemoryPool

> added v0.0.1 as `stdx.MemoryPool`

A `MemoryPool` is a structure that uses pre-allocated blocks of memory to quickly allocoate and deallocate resources quickly. It is very useful in situations where you have statically allocated memory but you will have fluctuating usage of that memory. A good example would be handling messages flowing throughout a system.

See [example](./examples/memory_pool.zig) and [source](./src/memory_pool.zig) for more information on usage.

### EventEmitter

> added v0.0.6 as `stdx.EventEmitter`

The `EventEmitter` is a tool for managing communications across callbacks. This is a very similar implementation to the nodejs event emitter class which is one of the fundemental building blocks for asynchronous events. The `EventEmitter` provides a simple(ish) api to register `Callback`s with appropriate `Context`s to be called when a specific `Event` is called.

See [example](./examples/event_emitter.zig) and [source](./src/event_emitter.zig) for more information on usage.
