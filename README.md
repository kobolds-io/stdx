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
            .url = "https://github.com/kobolds-io/stdx/archive/refs/tags/v0.0.8.tar.gz",
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
send 10000 items       65535    6.023s         91.911us ± 9.739us     (84.589us ... 1.224ms)       92.753us   117.245us  127.908us 
receive 10000 items    65535    5.252s         80.149us ± 81.776us    (74.105us ... 20.92ms)       78.253us   100.384us  110.577us 

|-------------------------|
| EventEmitter Benchmarks |
|-------------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
emit 1 listeners 10000 65535    1.348s         20.57us ± 5.868us      (18.989us ... 1.277ms)       20.086us   28.444us   34.267us  
emit 10 listeners 1000 65535    6.699s         102.221us ± 8.004us    (94.788us ... 651.443us)     101.171us  131.12us   141.943us 
emit 100 listeners 100 65535    1m4.102s       978.141us ± 170.618us  (801.628us ... 42.85ms)      979.128us  1.109ms    1.153ms   

|-----------------------|
| MemoryPool Benchmarks |
|-----------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
create 10000 items     65535    11.195s        170.832us ± 14.034us   (154.051us ... 782.661us)    173.37us   210.343us  226.573us 
unsafeCreate 10000 ite 65535    9.1s           138.859us ± 18.31us    (125.438us ... 3.193ms)      139.498us  177.102us  194.618us 

|-----------------------|
| RingBuffer Benchmarks |
|-----------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
enqueue 10000 items    65535    2.09s          31.895us ± 5.643us     (29.393us ... 591.054us)     31.035us   44.913us   56.298us  
enqueueMany 10000 item 65535    2.081s         31.762us ± 4.208us     (29.366us ... 249.166us)     30.996us   42.863us   52.171us  
dequeue 10000 items    65535    1.038s         15.842us ± 3.086us     (14.645us ... 191.955us)     15.483us   22.757us   27.744us  
dequeueMany 10000 item 65535    2.075s         31.669us ± 4.581us     (29.301us ... 596.145us)     30.946us   42.096us   48.55us   
concatenate 10000 item 65535    2.129s         32.496us ± 6.142us     (29.688us ... 999.682us)     31.736us   45.44us    54.384us  
copy 10000 items       65535    2.198s         33.54us ± 5.096us      (29.758us ... 322.781us)     33.474us   45.536us   56.505us  

|-------------------|
| Signal Benchmarks |
|-------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
send/receive 10000 ite 65535    10.305s        157.253us ± 97.686us   (145.048us ... 24.931ms)     156.48us   196.237us  218.677us 

|------------------------------|
| UnbufferedChannel Benchmarks |
|------------------------------|
benchmark              runs     total time     time/run (avg ± σ)     (min ... max)                p75        p99        p995      
-----------------------------------------------------------------------------------------------------------------------------
send/receive 10000 ite 65535    19.194s        292.884us ± 19.063us   (272.291us ... 1.49ms)       293.928us  340.837us  364.945us
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
