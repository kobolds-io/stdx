const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const BufferedChannel = stdx.BufferedChannel;
const CancellationToken = stdx.CancellationToken;
const log = std.log.scoped(.BufferedChannelExample);

const FileUploader = struct {
    bytes: []const u8,
    event_channel: *BufferedChannel(UploadEvent),
    id: usize,

    pub fn upload(self: *FileUploader, cancel_token: *CancellationToken) void {
        self.event_channel.send(.{ .label = .uploading, .uploader_id = self.id });
        defer self.event_channel.send(.{ .label = .done, .uploader_id = self.id });

        var total_time_elapsed: u64 = 0;
        const rand = std.crypto.random;

        var i: usize = 0;
        while (i < self.bytes.len) : (i += 5) {
            if (cancel_token.isCancelled()) {
                self.event_channel.send(.{ .label = .cancelled, .uploader_id = self.id });
                log.warn("file uploader: {} - cancelled upload, bytes uploaded: {}", .{ self.id, i });
                return;
            }

            // random delay to simulate upload time
            const delay = rand.intRangeAtMost(u64, 10, 250);

            const end = @min(i + 5, self.bytes.len);
            const chunk = self.bytes[i..end];
            _ = chunk;

            std.Thread.sleep(delay * std.time.ns_per_ms);
            total_time_elapsed += delay;

            log.debug("file uploader: {} - total bytes uploaded {} bytes - took {}ms", .{ self.id, i, delay });
        }

        log.info("file uploader: {} - done - took {}ms", .{ self.id, total_time_elapsed });
    }
};

const UploadEvent = struct {
    label: UploadEventLabel,
    uploader_id: usize,
};

const UploadEventLabel = enum {
    done,
    uploading,
    cancelled,
};

const UploadManager = struct {
    uploaders: std.AutoHashMap(usize, *FileUploader),
    uploader_events: BufferedChannel(UploadEvent),
    cancel_token: CancellationToken,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) UploadManager {
        return UploadManager{
            .uploaders = std.AutoHashMap(usize, *FileUploader).init(allocator),
            .uploader_events = BufferedChannel(UploadEvent).init(allocator, 1_000) catch unreachable,
            .cancel_token = CancellationToken{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UploadManager) void {
        var file_uploaders_iter = self.uploaders.valueIterator();
        while (file_uploaders_iter.next()) |entry| {
            const file_uploader = entry.*;
            self.allocator.destroy(file_uploader);
        }

        self.uploaders.deinit();
        self.uploader_events.deinit();
    }

    pub fn run(self: *UploadManager, worker_count: usize, timeout: i64) !void {
        // spawn `n` file uploaders and start uploading the files
        for (0..worker_count) |id| {
            const file_uploader = try self.allocator.create(FileUploader);
            errdefer self.allocator.destroy(file_uploader);

            file_uploader.* = FileUploader{
                .event_channel = &self.uploader_events,
                .id = id,
                .bytes = "this is a really long stream of bytes that is going to make somone very rich some day if they were just to copy it into their source code because yeah that is how software works.",
            };

            try self.uploaders.put(id, file_uploader);

            // spawn a thread where the file is uploaded by the uploader
            const th = try std.Thread.spawn(.{}, FileUploader.upload, .{ file_uploader, &self.cancel_token });
            th.detach();
        }

        var done_count: usize = 0;
        var cancelled_count: usize = 0;

        var now = std.time.milliTimestamp();
        const deadline = now + timeout;
        while (true) {
            if (now > deadline) {
                if (!self.cancel_token.isCancelled()) {
                    log.err("upload manager: global deadline exceeded. cancelling remaining uploads", .{});
                    self.cancel_token.cancel();
                }
            }
            now = std.time.milliTimestamp();

            const event = self.uploader_events.tryReceive(100_000, null) catch continue;
            switch (event.label) {
                .done => {
                    if (self.uploaders.fetchRemove(event.uploader_id)) |entry| {
                        const file_uploader = entry.value;
                        done_count += 1;
                        self.allocator.destroy(file_uploader);
                    }

                    if (self.uploaders.count() == 0) {
                        break;
                    }
                },
                .cancelled => {
                    if (self.uploaders.fetchRemove(event.uploader_id)) |entry| {
                        const file_uploader = entry.value;
                        cancelled_count += 1;
                        self.allocator.destroy(file_uploader);
                    }

                    if (self.uploaders.count() == 0) {
                        break;
                    }
                },
                else => {},
            }
        } else {
            log.err("upload manager: global timeout exceeded", .{});
        }

        log.info("upload manager: success: {}, cancelled: {}", .{ done_count, cancelled_count });
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // initialize a channel of usizes with a capacity of 10 items
    var channel = try BufferedChannel(usize).init(allocator, 10);
    defer channel.deinit();

    // put a single item into the channel. This will not block because
    // the channel.buffer is not full
    channel.send(1);

    const received_item = channel.receive();
    assert(received_item == 1);

    // test a multi threaded file upload manager that spawns multiple threads of FileUploader.
    var upload_manager = UploadManager.init(allocator);
    defer upload_manager.deinit();

    // Change the second argument to change the global timeout
    try upload_manager.run(100, 3_000);
}
