const std = @import("std");
const zbench = @import("zbench");

test "prints system info" {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("--------------------------------------------------------\n");
    try stderr.print("{}", .{try zbench.getSystemInfo()});
    try stderr.writeAll("--------------------------------------------------------\n");
}

comptime {
    _ = @import("channel.zig");
    _ = @import("ring_buffer.zig");
    _ = @import("simple_channel.zig");
}
