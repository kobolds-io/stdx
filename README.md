
# Overview

[![Latest Release](https://gitlab.com/kobolds-io/stdx/-/badges/release.svg)](https://gitlab.com/kobolds-io/stdx/-/releases)
![License](https://img.shields.io/gitlab/license/kobolds-io/stdx)
![Last Commit](https://img.shields.io/gitlab/last-commit/kobolds-io/stdx)
![Zig](https://img.shields.io/badge/Zig-0.16.0-orange.svg?logo=zig)

This is a library adding several generally useful tools that are either not included in the standard library or have slightly different behavior. As the `zig` programming language matures, we should get more and more awesome `std` library features but until then...

All data structures, algorithms and utilities included in this library are written from scratch. This minimizes the threat of malicious or unintentional supply chain attacks. It also ensures that all code is controlled in a single place and HOPEFULLY minimizes the chance that `zig` turns into the hellish monstrocity that is `npm` and the `nodejs` ecosystem.

In general people use this library for the `RingBuffer` and the `MemoryPool` datastructures. See below for details.

## Mirrors and Sources:

- [GitLab source repo](https://gitlab.com/kobolds-io/stdx)
- [Github mirror](https://github.com/kobolds-io/stdx)

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
zig fetch --save  https://gitlab.com/kobolds-io/stdx/-/archive/v0.4.2/stdx-v0.4.2.tar.gz
```

Alternatively, you can install `stdx` just like any other `zig` dependency by editing your `build.zig.zon` file.

```zig
    .dependencies = .{
        .stdx = .{
            .url = "https://gitlab.com/kobolds-io/stdx/-/archive/v0.4.2/stdx-v0.4.2.tar.gz",
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
send 10000 items      65535    6.758s         103.129us ± 56.977us  (94.173us ... 2.228ms)       97.916us   185.366us  305.859us  
receive 10000 items   65535    5.483s         83.677us ± 46.198us   (78.25us ... 2.358ms)        81.354us   123.01us   153.525us  

|-------------------------|
| EventEmitter Benchmarks |
|-------------------------|
benchmark                        runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------------
emit 1 listeners 10000 items     1        34.873us       34.873us ± 0ns        (34.873us ... 34.873us)      34.873us   34.873us   34.873us   
emit 10 listeners 10000 items    1        127.325us      127.325us ± 0ns       (127.325us ... 127.325us)    127.325us  127.325us  127.325us  
emit 100 listeners 10000 items   1        965.19us       965.19us ± 0ns        (965.19us ... 965.19us)      965.19us   965.19us   965.19us   

|-----------------------|
| MemoryPool Benchmarks |
|-----------------------|
benchmark                  runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------
create 10000 items         65535    7.338s         111.983us ± 222.903us (103.098us ... 56.148ms)     107.315us  188.812us  289.756us  
unsafeCreate 10000 items   65535    2.46s          37.546us ± 26.152us   (31.679us ... 3.347ms)       36.152us   60.501us   81.959us   

|-----------------------|
| RingBuffer Benchmarks |
|-----------------------|
benchmark                 runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
--------------------------------------------------------------------------------------------------------------------------------------
prepend 10000 items       65535    2.19s          33.43us ± 20.94us     (31.61us ... 3.341ms)        32.695us   49.459us   66.142us   
enqueue 10000 items       65535    2.052s         31.319us ± 15.602us   (29.77us ... 1.341ms)        30.534us   47.761us   62.658us   
enqueueMany 10000 items   65535    2.108s         32.174us ± 16.592us   (30.505us ... 1.811ms)       31.274us   49.685us   68.702us   
dequeue 10000 items       65535    2.128s         32.478us ± 19.812us   (30.902us ... 2.511ms)       31.53us    48.531us   68.012us   
dequeueMany 10000 items   65535    2.121s         32.365us ± 21.093us   (30.145us ... 3.586ms)       31.481us   48.585us   63.087us   
concatenate 10000 items   65535    2.221s         33.897us ± 17.985us   (31.19us ... 1.619ms)        33.091us   51.95us    71.648us   
copy 10000 items          65535    2.185s         33.344us ± 16.53us    (30.254us ... 1.561ms)       32.928us   50.223us   67.278us   
sort 10000 items          65535    32.111s        489.992us ± 196.468us (449.964us ... 40.18ms)      489.539us  725.412us  897.449us  

|-------------------|
| Signal Benchmarks |
|-------------------|
benchmark                  runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------
send/receive 10000 items   65535    13.558s        206.891us ± 47.929us  (194.362us ... 4.781ms)      204.129us  327.755us  407.956us  

|----------------------|
| SPSCQueue Benchmarks |
|----------------------|
benchmark             runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
----------------------------------------------------------------------------------------------------------------------------------
enqueue 32768 items   65535    2.433s         37.132us ± 13.599us   (34.916us ... 1.296ms)       35.82us    61.574us   80.153us   

|------------------------------|
| UnbufferedChannel Benchmarks |
|------------------------------|
benchmark                  runs     total time     time/run (avg ± σ)    (min ... max)                p75        p99        p995      
---------------------------------------------------------------------------------------------------------------------------------------
send/receive 10000 items   65535    23.242s        354.66us ± 56.14us    (334.546us ... 4.329ms)      355.011us  536.348us  627.56us   
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
