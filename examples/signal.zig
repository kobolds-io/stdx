const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.Signal);

const Signal = @import("stdx").Signal;
const UnbufferedChannel = @import("stdx").UnbufferedChannel;
const RingBuffer = @import("stdx").RingBuffer;

const Reply = struct {
    result: usize,
};

const Request = struct {
    left: usize,
    right: usize,
    op: Operation,
    signal: *Signal(Reply),
};

const Operation = enum {
    add,
    subtract,
    multiply,
    divide,
};

const CalculatorState = enum {
    running,
    closing,
    closed,
};

const ITERATIONS = 100_000;
const AsyncCalculator = struct {
    const Self = @This();

    close_channel: UnbufferedChannel(bool),
    done_channel: UnbufferedChannel(bool),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    requests: *RingBuffer(Request),
    state: CalculatorState,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const requests = try allocator.create(RingBuffer(Request));
        errdefer allocator.destroy(requests);

        requests.* = try RingBuffer(Request).init(allocator, ITERATIONS);
        errdefer requests.deinit();

        return Self{
            .close_channel = UnbufferedChannel(bool).new(),
            .done_channel = UnbufferedChannel(bool).new(),
            .mutex = .{},
            .requests = requests,
            .state = .closed,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.requests.deinit();
        self.allocator.destroy(self.requests);
    }

    pub fn handleRequest(req: Request) void {
        const left = req.left;
        const right = req.right;

        const rep = switch (req.op) {
            .add => Reply{ .result = left + right },
            .subtract => Reply{ .result = left - right },
            .multiply => Reply{ .result = left * right },
            .divide => Reply{ .result = left / right },
        };

        req.signal.send(rep);
    }

    pub fn run(self: *Self, ready_channel: *UnbufferedChannel(bool)) void {
        self.state = .running;
        ready_channel.send(true);
        while (true) {
            // check if the close channel has received a close command
            const close_channel_received = self.close_channel.tryReceive(0) catch false;
            if (close_channel_received) {
                self.state = .closing;
            }

            switch (self.state) {
                .running => {
                    self.mutex.lock();
                    defer self.mutex.unlock();

                    while (self.requests.dequeue()) |req| {
                        AsyncCalculator.handleRequest(req);
                    }

                    // This is the tick rate and completely arbitrary
                    std.Thread.sleep(1 * std.time.ns_per_ms);
                },
                .closing => {
                    self.state = .closed;
                    self.done_channel.send(true);
                    return;
                },
                .closed => return,
            }
        }
    }

    pub fn close(self: *Self) void {
        switch (self.state) {
            .closed, .closing => return,
            else => {
                self.mutex.lock();
                defer self.mutex.unlock();

                self.close_channel.send(true);
            },
        }

        _ = self.done_channel.receive();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // spawn the async calculator
    var ready_channel = UnbufferedChannel(bool).new();
    var calculator = try AsyncCalculator.init(allocator);
    defer calculator.deinit();

    const calculator_thread = try std.Thread.spawn(.{}, AsyncCalculator.run, .{ &calculator, &ready_channel });
    defer calculator.close();
    calculator_thread.detach();

    _ = ready_channel.tryReceive(100 * std.time.ns_per_ms) catch |err| {
        calculator.close();
        return err;
    };

    // at this point we know that the calculator is running
    var signals = std.array_list.Managed(*Signal(Reply)).init(allocator);
    defer signals.deinit();

    // at this point we know that the calculator is running
    var requests = std.array_list.Managed(Request).init(allocator);
    defer requests.deinit();

    // everything is setup now
    var timer = try std.time.Timer.start();
    const enqueue_start = timer.read();

    // enqueue all the requests at once
    {
        calculator.mutex.lock();
        defer calculator.mutex.unlock();

        for (0..ITERATIONS) |_| {
            const signal = try allocator.create(Signal(Reply));
            errdefer allocator.destroy(signal);

            signal.* = Signal(Reply).new();

            try signals.append(signal);

            const req = Request{
                .left = 10,
                .right = 5,
                .op = .add,
                .signal = signal,
            };

            try requests.append(req);

            try calculator.requests.enqueue(req);
        }
    }

    const enqueue_end = timer.read();
    const await_start = timer.read();

    // This is the main thread handling each request it received
    for (requests.items) |req| {
        const rep = req.signal.receive();

        assert(rep.result == 15);
        allocator.destroy(req.signal);
    }

    const await_end = timer.read();

    log.err("total_time: {}ms, enqueue_time: {}ms, await_time {}ms, total iters {}", .{
        (await_end - enqueue_start) / std.time.ns_per_ms,
        (enqueue_end - enqueue_start) / std.time.ns_per_ms,
        (await_end - await_start) / std.time.ns_per_ms,
        ITERATIONS,
    });
}
