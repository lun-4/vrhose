const std = @import("std");
const ring = @import("ring_buffer.zig");
const beam = @import("beam");

const MAX_POST_BUFFER_SIZE = 400;
const MAX_POST_RETURN_SIZE = 100;

const Post = struct {
    timestamp: f64,
    text: []const u8,
    languages: []const u8,
    author_handle: []const u8,
    hash: i64,

    const Self = @This();
    pub fn copyVia(self: Self, allocator: std.mem.Allocator) !Post {
        return Self{
            .timestamp = self.timestamp,
            .hash = self.hash,
            .text = try allocator.dupe(u8, self.text),
            .languages = try allocator.dupe(u8, self.languages),
            .author_handle = try allocator.dupe(u8, self.author_handle),
        };
    }

    pub fn deinitVia(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        allocator.free(self.languages);
        allocator.free(self.author_handle);
    }
};
const PostBuffer = ring.RingBuffer(Post);
const Storage = struct {
    posts: PostBuffer,

    const Self = @This();
    pub fn init() Self {
        debug("init?", .{});
        const buf = PostBuffer.init(beam.allocator, MAX_POST_BUFFER_SIZE) catch @panic("out of memory for post buffer init");
        const self = Self{ .posts = buf };
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
    if (storage.posts.len == MAX_POST_BUFFER_SIZE) {
        const post_to_delete = storage.posts.pop().?;
        if (handle == 0) {
            debug("popped {}", .{post_to_delete.timestamp});
        }
        post_to_delete.deinitVia(beam.allocator);
    }
    std.debug.assert(storage.posts.len <= MAX_POST_BUFFER_SIZE);
    if (false) {
        debug(
            "[{d}] {d}/{d}, timestamp={}, text={s}, languages={s}, author_handle={s}, hash={}",
            .{ handle, storage.posts.readableLength(), MAX_POST_BUFFER_SIZE, post.timestamp, post.text, post.languages, post.author_handle, post.hash },
        );
    }
    const owned_post = post.copyVia(beam.allocator) catch @panic("ran out of memory for string dupe");
    storage.posts.push(owned_post) catch @panic("must not be out of memory here");
}

pub fn fetch(handle: usize, timestamp: f64) ![]Post {
    const storage = &storages[handle];

    var result = std.ArrayList(Post).init(beam.allocator);
    try result.ensureTotalCapacity(MAX_POST_RETURN_SIZE);

    var it = storage.posts.iterator();
    while (it.next()) |post| {
        //       debug("t= {s}", .{post.text});
        if (post.timestamp >= timestamp) {
            result.append(post) catch |err| switch (err) {
                error.OutOfMemory => continue,
                else => unreachable,
            };
        }
    }
    const posts_result = result.toOwnedSlice();
    return posts_result;
}
