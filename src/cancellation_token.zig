const atomic = @import("std").atomic;

pub const CancellationToken = struct {
    const Self = @This();
    cancelled: atomic.Value(bool) = atomic.Value(bool).init(false),

    pub fn cancel(self: *Self) void {
        self.cancelled.store(true, .seq_cst);
    }

    pub fn isCancelled(self: *Self) bool {
        return self.cancelled.load(.seq_cst);
    }
};
