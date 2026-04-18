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

    pub fn upload(self: *FileUploader, io: std.Io, cancel_token: *CancellationToken) void {
        self.event_channel.send(.{ .label = .uploading, .uploader_id = self.id });
        defer self.event_channel.send(.{ .label = .done, .uploader_id = self.id });

        var total_time_elapsed: i64 = 0;
        var sort_prng = std.Random.DefaultPrng.init(0xdead_beef);
        const rand = sort_prng.random();

        var i: usize = 0;
        while (i < self.bytes.len) : (i += 5) {
            if (cancel_token.isCancelled()) {
                self.event_channel.send(.{ .label = .cancelled, .uploader_id = self.id });
                log.warn("file uploader: {} - cancelled upload, bytes uploaded: {}", .{ self.id, i });
                return;
            }

            // random delay to simulate upload time
            const delay = rand.intRangeAtMost(i64, 5, 100);

            const end = @min(i + 5, self.bytes.len);
            const chunk = self.bytes[i..end];
            _ = chunk;

            const duration = std.Io.Duration.fromMilliseconds(delay);
            std.Io.sleep(io, duration, .awake) catch unreachable;
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
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) UploadManager {
        return UploadManager{
            .uploaders = std.AutoHashMap(usize, *FileUploader).init(allocator),
            .uploader_events = BufferedChannel(UploadEvent).init(allocator, io, 1_000) catch unreachable,
            .cancel_token = CancellationToken{},
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn deinit(self: *UploadManager) void {
        var file_uploaders_iter = self.uploaders.valueIterator();
        while (file_uploaders_iter.next()) |entry| {
            const file_uploader = entry.*;
            self.allocator.destroy(file_uploader);
        }

        self.uploaders.deinit();
        self.uploader_events.deinit(self.allocator);
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
            const th = try std.Thread.spawn(.{}, FileUploader.upload, .{
                file_uploader,
                self.io,
                &self.cancel_token,
            });
            th.detach();
        }

        var done_count: usize = 0;
        var cancelled_count: usize = 0;

        var now = std.Io.Timestamp.now(self.io, .awake);
        const deadline = now.toMilliseconds() + timeout;
        while (true) {
            if (now.toMilliseconds() > deadline) {
                if (!self.cancel_token.isCancelled()) {
                    log.err("upload manager: global deadline exceeded. cancelling remaining uploads", .{});
                    self.cancel_token.cancel();
                }
            }
            now = std.Io.Timestamp.now(self.io, .awake);

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

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // initialize a channel of usizes with a capacity of 10 items
    var channel = try BufferedChannel(usize).init(allocator, io, 10);
    defer channel.deinit(allocator);

    // put a single item into the channel. This will not block because
    // the channel.buffer is not full
    channel.send(1);

    const received_item = channel.receive();
    assert(received_item == 1);

    // test a multi threaded file upload manager that spawns multiple threads of FileUploader.
    var upload_manager = UploadManager.init(allocator, io);
    defer upload_manager.deinit();

    // Change the second argument to change the global timeout
    try upload_manager.run(10, 3_000);
}
