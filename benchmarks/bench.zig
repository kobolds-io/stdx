const std = @import("std");
const zbench = @import("zbench");

test "prints system info" {
    var stderr = std.fs.File.stderr().writerStreaming(&.{});
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
