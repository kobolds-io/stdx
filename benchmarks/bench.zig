const std = @import("std");
const testing = std.testing;
const zbench = @import("zbench");

test "prints system info" {
    const io = testing.io;
    var stderr = std.Io.File.stderr().writerStreaming(io, &.{});
    const writer = &stderr.interface;

    try writer.writeAll("--------------------------------------------------------\n");
    try writer.print("{f}", .{try zbench.getSystemInfo()});
    try writer.writeAll("--------------------------------------------------------\n");
}

comptime {
    _ = @import("buffered_channel.zig");
    _ = @import("event_emitter.zig");
    _ = @import("memory_pool.zig");
    _ = @import("ring_buffer.zig");
    _ = @import("signal.zig");
    _ = @import("unbuffered_channel.zig");
}
