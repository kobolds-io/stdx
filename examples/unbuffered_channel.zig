const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const UnbufferedChannel = stdx.UnbufferedChannel;
const log = std.log.scoped(.UnbufferedChannelExample);

pub fn main() !void {
    var channel = UnbufferedChannel(usize).new();

    log.info("sending an item", .{});
    channel.send(1);

    // ... some magical other thread

    log.info("receiving an item", .{});
    const received_item = channel.receive();
    assert(received_item == 1);
}
