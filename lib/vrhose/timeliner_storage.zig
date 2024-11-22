const std = @import("std");
const beam = @import("beam");

const MAX_POST_BUFFER_SIZE = 1000;
const MAX_POST_RETURN_SIZE = 10000;

const Post = struct {
    timestamp: f64,
    text: []const u8,
    languages: []const u8,
    author_handle: []const u8,
    hash: i64,
};
const PostFifo = std.fifo.LinearFifo(Post, .Slice);
const Storage = struct {
    posts: PostFifo,

    const Self = @This();
    pub fn init() Self {
        const post_buffer = beam.allocator.alloc(Post, MAX_POST_BUFFER_SIZE) catch @panic("out of memory for post buffer init");
        debug("init?", .{});
        debug("init static post fifo", .{});
        const fifo = PostFifo.init(post_buffer);
        var self = Self{ .posts = fifo };
        debug("ensure 1", .{});
        self.posts.ensureTotalCapacity(MAX_POST_BUFFER_SIZE) catch @panic("misconfigured fifo");
        debug("ensure 2", .{});
        self.posts.ensureUnusedCapacity(MAX_POST_BUFFER_SIZE) catch @panic("logic bug");
        return self;
    }
};

var mutex = std.Thread.Mutex{};
var debug_log_mutex = std.Thread.Mutex{};

// this approach (one core accesses only one "storage" out of the array)
// lets us access those handles without requiring a global mutex, as long as fetching them stays in-mutex
var storages: []Storage = undefined;
var last_handle: usize = 0;

fn debug(comptime fmt: []const u8, args: anytype) void {
    debug_log_mutex.lock();
    defer debug_log_mutex.unlock();
    std.debug.print(fmt ++ "\n", args);
}

pub fn init(num_cores: usize) void {
    debug("initializing for given amount of cores: {d}", .{num_cores});
    mutex.lock();
    defer mutex.unlock();
    storages = beam.allocator.alloc(Storage, num_cores) catch @panic("out of memory for initialization");
    for (0..num_cores) |i| {
        debug("init core {d}", .{i});
        const storage = Storage.init();
        debug("initted {d}", .{i});
        storages[i] = storage;
    }
}

pub fn create() usize {
    const handle = last_handle;
    debug("creating for handle {d}", .{handle});
    last_handle += 1;
    return handle;
}

pub fn insert_post(handle: usize, post: Post) void {
    //debug("insert!", .{});
    const storage = &storages[handle];
    if (storage.posts.readableLength() == MAX_POST_BUFFER_SIZE) storage.posts.discard(1);
    //debug(
    //    "[{d}] {d}/{d}, timestamp={:.2}, textlen={d}, languages={s}, author_handle={s}, hash={}",
    //    .{ handle, storage.posts.readableLength(), MAX_POST_BUFFER_SIZE, post.timestamp, post.text.len, post.languages, post.author_handle, post.hash },
    //);
    storage.posts.writeItem(post) catch @panic("must not be out of memory here");
}

pub fn fetch(handle: usize, timestamp: f64) ![]Post {
    const storage = &storages[handle];
    const all_posts = storage.posts.readableSlice(0);
    var result = std.ArrayList(Post).init(beam.allocator);

    try result.ensureTotalCapacity(MAX_POST_RETURN_SIZE);

    for (all_posts) |post| {
        if (post.timestamp >= timestamp) {
            result.append(post) catch |err| switch (err) {
                error.OutOfMemory => continue,
                else => unreachable,
            };
        }
    }
    return result.toOwnedSlice();
}
