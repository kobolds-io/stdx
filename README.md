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
      1. [Multithreading](#multithreading)
         1. [BufferedChannel](#bufferedchannel)
         2. [UnbufferedChannel](#unbufferedchannel)
         3. [Signal](#signal)
      2. [Events](#events)
         1. [EventEmitter](#eventemitter)
      3. [Queues/Lists](#queues/lists)
         1. [ManagedQueue](#managedqueue)
         2. [UnmanagedQueue](#unmanagedqueue)
         3. [RingBuffer](#ringbuffer)
      4. [Memory Management](#memory-management)
         1. [MemoryPool](#memorypool)

## Usage

| zig version | stdx version |
|-------------|--------------|
| 0.15.x      | 0.2.1        |
| 0.16.0      | 0.3.0        |


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
zig fetch --save  https://gitlab.com/kobolds-io/stdx/-/archive/v0.3.0/stdx-v0.3.0.tar.gz
```

Alternatively, you can install `stdx` just like any other `zig` dependency by editing your `build.zig.zon` file.

```zig
    .dependencies = .{
        .stdx = .{
            .url = "https://gitlab.com/kobolds-io/stdx/-/archive/v0.3.0/stdx-v0.3.0.tar.gz",
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
  CPU Cores:        24
  Total Memory:     14.412GiB
--------------------------------------------------------

|----------------------------|
| BufferedChannel Benchmarks |
|----------------------------|
benchmark          runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
-------------------------------------------------------------------------------------------------------------------------------
send 10000 items   65535    6.458s         98.546us ± 12.445us   (93.112us ... 1.438ms)       97.844us   132.5us    144.742us  
receive 10000 ite  65535    5.439s         83.008us ± 45.284us   (78.147us ... 7.636ms)       82.294us   133.062us  163.666us  

|-------------------------|
| EventEmitter Benchmarks |
|-------------------------|
benchmark                        runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------------
emit 1 listeners 10000 items     1        34.795us       34.795us ± 0ns        (34.795us ... 34.795us)      34.795us   34.795us   34.795us   
emit 10 listeners 10000 items    1        109.427us      109.427us ± 0ns       (109.427us ... 109.427us)    109.427us  109.427us  109.427us  
emit 100 listeners 10000 items   1        991.267us      991.267us ± 0ns       (991.267us ... 991.267us)    991.267us  991.267us  991.267us  

|-----------------------|
| MemoryPool Benchmarks |
|-----------------------|
benchmark                  runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------
create 10000 items         65535    12.175s        185.784us ± 60.638us  (173.106us ... 14.178ms)     186.858us  239.059us  263.416us  
unsafeCreate 10000 items   65535    10.013s        152.803us ± 58.121us  (144.741us ... 13.891ms)     152.56us   196.424us  216.088us  

|-----------------------|
| RingBuffer Benchmarks |
|-----------------------|
benchmark                 runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
--------------------------------------------------------------------------------------------------------------------------------------
prepend 10000 items       65535    2.199s         33.559us ± 9.921us    (31.828us ... 859.609us)     32.669us   58.883us   81.022us   
enqueue 10000 items       65535    2.067s         31.552us ± 43.04us    (29.761us ... 10.219ms)      30.621us   55.161us   72.415us   
enqueueMany 10000 items   65535    2.07s          31.596us ± 8.914us    (28.938us ... 970.921us)     31.236us   47.932us   59.374us   
dequeue 10000 items       65535    2.126s         32.45us ± 11.355us    (30.902us ... 783.759us)     31.542us   56.903us   83.488us   
dequeueMany 10000 items   65535    2s             30.519us ± 9.973us    (29.121us ... 1.345ms)       29.845us   53.819us   69.766us   
concatenate 10000 items   65535    2.187s         33.386us ± 33.989us   (31.201us ... 8.407ms)       32.739us   57.035us   72.596us   
copy 10000 items          65535    2.159s         32.948us ± 8.64us     (30.486us ... 516.128us)     32.541us   57.097us   72.168us   
sort 10000 items          65535    31.428s        479.575us ± 129.938us (435.62us ... 17.483ms)      473.571us  812.069us  1.049ms    

|-------------------|
| Signal Benchmarks |
|-------------------|
benchmark                  runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------
send/receive 10000 items   65535    13.55s         206.762us ± 57.545us  (184.572us ... 9.724ms)      204.871us  325.636us  386.952us  

|------------------------------|
| UnbufferedChannel Benchmarks |
|------------------------------|
benchmark                  runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------
send/receive 10000 items   65535    21.432s        327.042us ± 52.381us  (309.834us ... 5.604ms)      325.329us  477.18us   524.423us  
```

## Contributing

Please see [Contributing](./CONTRIBUTING.md) for more information on how to get involved.

## Code of Conduct

Please see the [Code of Conduct](./CODE_OF_CONDUCT.md) file. Simple library, simple rules.

---

# Documentation

## stdx

The `stdx` top level module. Directly contains data structures and is the parent module to modules like `io` and `net`.

### Mutlithreading

#### BufferedChannel

> added v0.0.3 as `stdx.BufferedChannel`

The `BufferedChannel` is a structure that can be used to safely transmit data across threads. It uses a backing buffer which stores the actual values transmitted. Additionally it has a very simple api `send`/`receive` and supports concepts like cancellation and timeouts.

See [example](./examples/buffered_channel.zig) and [source](./src/buffered_channel.zig) for more information on usage.

#### UnbufferedChannel

> added v0.0.3 as `stdx.UnbufferedChannel`

The `UnbufferedChannel` is a structure that can be used to safely transmit data across threads. It uses a `Condition` to notify receivers that there is new data. Additionally it has a very simple api `send`/`receive` and supports concepts like timeouts but does not currently support cancellation.

See [example](./examples/unbuffered_channel.zig) and [source](./src/unbuffered_channel.zig) for more information on usage.

#### Signal

> added v0.0.8 as `stdx.Signal`

The `Signal` is a structure that can be used to safely transmit data across threads. Unlike a channel, it does not require that both threads become synchronized at the same point. Think of a `Signal` as a way for a sender to throw a value over the fence and a receiver to pick the value at a later time (when it is convenient for the receiver). `Signal`s are "one shots", meaning that they should only ever be used once. These structures are ideal for things like `request`->`reply` kinds of problems.

See [example](./examples/signal.zig) and [source](./src/signal.zig) for more information on usage.

### Events

#### EventEmitter

> added v0.0.6 as `stdx.EventEmitter`

The `EventEmitter` is a tool for managing communications across callbacks. This is a very similar implementation to the nodejs event emitter class which is one of the fundemental building blocks for asynchronous events. The `EventEmitter` provides a simple(ish) api to register `Callback`s with appropriate `Context`s to be called when a specific `Event` is called.

See [example](./examples/event_emitter.zig) and [source](./src/event_emitter.zig) for more information on usage.

### Queues/Lists

#### ManagedQueue

> added v0.0.2 as `stdx.ManagedQueue`

The `ManagedQueue` is a generic queue implementation that uses a singly linked list. It allows for the management of a queue with operations like enqueueing, dequeueing, checking if the queue is empty, concatenating two queues, and handles the allocation/deallocation of memory used by the queue. The queue is managed by an allocator, which is used for creating and destroying nodes.

See [example](./examples/managed_queue.zig) and [source](./src/managed_queue.zig) for more information on usage.

#### UnmanagedQueue

> added v0.0.2 as `stdx.UnmanagedQueue`

The `UnmanagedQueue` is a generic queue implementation that uses a singly linked list. It most closely represents the `std.SinglyLinkedList` in its functionality. Differing from the `ManagedQueue`, the `UnmanagedQueue` requires memory allocations to be external to the queue and provides a generic `Node` structure to help link everything together.

Please also see `UnmanagedQueueNode` which is the `Node` used by the `UnmanagedQueue`.

See [example](./examples/unmanaged_queue.zig) and [source](./src/unmanaged_queue.zig) for more information on usage.

#### RingBuffer

> added v0.0.1 as `stdx.RingBuffer`

A `RingBuffer` is a data structure that is really useful for managing memory in a fixed memory allocation. This particular implementation is particularly useful for a fixed size queue. Kobolds uses the `RingBuffer` data structure for inboxes and outboxes for when messages are received/sent through TCP connections.

See [example](./examples/ring_buffer.zig) and [source](./src/ring_buffer.zig) for more information on usage.

### Memory Management

#### MemoryPool

> added v0.0.1 as `stdx.MemoryPool`

A `MemoryPool` is a structure that uses pre-allocated blocks of memory to quickly allocoate and deallocate resources quickly. It is very useful in situations where you have statically allocated memory but you will have fluctuating usage of that memory. A good example would be handling messages flowing throughout a system.

See [example](./examples/memory_pool.zig) and [source](./src/memory_pool.zig) for more information on usage.
