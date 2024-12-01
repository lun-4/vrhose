const std = @import("std");
const ring = @import("ring_buffer.zig");
const beam = @import("beam");

const MAX_POST_BUFFER_SIZE = if (DEBUG) 400 else 35000; // assuming firehose goes bananas and is 500posts/sec, and we want to hold 70sec of history, that's 35000 posts
const MAX_POST_RETURN_SIZE = if (DEBUG) 100 else 10000;

const IncomingPost = struct {
    timestamp: f64,
    text: []const u8,
    languages: []const u8,
    author_name: []const u8,
    author_handle: []const u8,
    author_did: []const u8,
    flags: []const u8,
    world_id: ?[]const u8,
    micro_id: []const u8,
    hash: i64,
};

const Post = struct {
    init: bool,
    timestamp: f64,
    text: []const u8,
    languages: []const u8,
    author_name: []const u8,
    author_handle: []const u8,
    author_did: []const u8,
    flags: []const u8,
    world_id: ?[]const u8,
    micro_id: []const u8,
    hash: i64,

    const Self = @This();
    pub fn createFromIncoming(post: IncomingPost, allocator: std.mem.Allocator) !Self {
        return Self{
            .init = true,
            .timestamp = post.timestamp,
            .hash = post.hash,
            .text = try allocator.dupe(u8, post.text),
            .languages = try allocator.dupe(u8, post.languages),
            .author_name = try allocator.dupe(u8, post.author_name),
            .author_handle = try allocator.dupe(u8, post.author_handle),
            .author_did = try allocator.dupe(u8, post.author_did),
            .flags = try allocator.dupe(u8, post.flags),
            .world_id = if (post.world_id) |wrld_id| try allocator.dupe(u8, wrld_id) else null,
            .micro_id = try allocator.dupe(u8, post.micro_id),
        };
    }

    pub fn deinitVia(self: *Self, allocator: std.mem.Allocator) void {
        if (self.init) {
            allocator.free(self.text);
            allocator.free(self.languages);
            allocator.free(self.author_name);
            allocator.free(self.author_handle);
            allocator.free(self.author_did);
            allocator.free(self.micro_id);
            allocator.free(self.flags);
            if (self.world_id) |id| allocator.free(id);
            self.init = false;
        }
    }
};
const PostBuffer = ring.RingBuffer(Post);
const Storage = struct {
    allocator: std.mem.Allocator,
    posts: PostBuffer,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        debug("initializing a storage", .{});
        const buf = PostBuffer.init(allocator, MAX_POST_BUFFER_SIZE) catch @panic("out of memory for post buffer init");
        const self = Self{
            .posts = buf,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.posts.buffer) |*post| {
            post.deinitVia(self.posts.allocator);
        }
        self.posts.deinit();
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
    return initBeam(num_cores);
}

fn initA(allocator: std.mem.Allocator, num_cores: usize) void {
    debug("initializing for given amount of cores: {d}", .{num_cores});
    mutex.lock();
    defer mutex.unlock();
    storages = allocator.alloc(Storage, num_cores) catch @panic("out of memory for initialization");
    for (0..num_cores) |i| {
        debug("init core {d}", .{i});
        const storage = Storage.init(allocator);
        debug("initted {d}", .{i});
        storages[i] = storage;
    }
}
fn initBeam(num_cores: usize) void {
    debug("initializing for given amount of cores: {d}", .{num_cores});
    mutex.lock();
    defer mutex.unlock();

    storages = beam.allocator.alloc(Storage, num_cores) catch @panic("out of memory for initialization");
    for (0..num_cores) |i| {
        debug("init core {d}", .{i});
        const storage = Storage.init(beam.allocator);
        debug("initted {d}", .{i});
        storages[i] = storage;
    }
}

pub fn create() usize {
    const handle = last_handle;
    debug("creating for handle {d}", .{handle});
    last_handle += 1;
    if (last_handle > storages.len) {
        // TODO: make this possible. a timeliner could die and we can attach to terminate(). release the storage then
        // reassign so that teimeliner crashes don't crash the entire app
        @panic("no more handles available. one of the timeliners crashed and wants to continue, but that is not possible.");
    }
    return handle;
}

pub fn insert_post(handle: usize, post: IncomingPost) void {
    return insertPost((&storages[handle]).allocator, handle, post);
}

const DEBUG = false;

fn insertPost(allocator: std.mem.Allocator, handle: usize, post: IncomingPost) void {
    //debug("insert!", .{});
    const storage = &storages[handle];
    if (storage.posts.len == MAX_POST_BUFFER_SIZE) {
        const post_to_delete = storage.posts.pop().?;
        if (DEBUG and handle == 0) {
            debug("popped {}", .{post_to_delete.timestamp});
        }
        post_to_delete.deinitVia(allocator);
    }
    std.debug.assert(storage.posts.len <= MAX_POST_BUFFER_SIZE);
    if (DEBUG and false) {
        debug(
            "[{d}] {d}/{d}, timestamp={}, text={s}, languages={s}, author_handle={s}, hash={}",
            .{ handle, storage.posts.readableLength(), MAX_POST_BUFFER_SIZE, post.timestamp, post.text, post.languages, post.author_handle, post.hash },
        );
    }
    const owned_post = Post.createFromIncoming(post, allocator) catch @panic("ran out of memory for string dupe");
    storage.posts.push(owned_post) catch @panic("must not be out of memory here");
}

//pub fn fetch(handle: usize, timestamp: f64) ![]*const Post {
//    return fetchA((&storages[handle]).allocator, handle, timestamp);
//}

pub fn fetch(handle: usize, timestamp: f64) !beam.term {
    const storage = &storages[handle];

    var cnt: usize = 0;
    var it1 = storage.posts.iterator();
    while (it1.next()) |post| {
        if (post.timestamp >= timestamp) {
            cnt += 1;
        }
    }
    var result = try storage.allocator.alloc(*const Post, cnt);

    var idx: usize = 0;
    var it = storage.posts.iterator();
    while (it.next()) |post| {
        if (post.timestamp >= timestamp) {
            result[idx] = post;
            idx += 1;
        }
    }
    if (idx != cnt) @panic("must not be!");
    if (DEBUG) debug("sending {d} posts", .{result.len});
    const term = beam.make(result, .{});
    storage.allocator.free(result);
    return term;

    //return result;
}

// test "it works" {
//     const allocator = std.testing.allocator;
//     initA(allocator, 1);
//     defer {
//         for (storages) |*storage| {
//             storage.deinit();
//             allocator.destroy(storage);
//         }
//     }
//     const handle = create();
//     const BASE_TIMESTAMP = 100377371;
//     for (0..MAX_POST_BUFFER_SIZE) |i| {
//         insertPost(allocator, handle, .{
//             .timestamp = @floatFromInt(BASE_TIMESTAMP + i),
//             .text = "a",
//             .languages = "b",
//             .author_name = "c",
//             .author_handle = "c",
//             .hash = @intCast(19327 + i),
//             .flags = "f",
//             .world_id = "w",
//         });
//     }
//     const storage = &storages[handle];
//     defer {
//         for (storage.posts.buffer) |*post| {
//             post.deinitVia(allocator);
//         }
//     }

//     const posts = try fetchA(allocator, handle, BASE_TIMESTAMP);
//     defer deinitGivenList(allocator, posts);
//     try std.testing.expectEqual(MAX_POST_BUFFER_SIZE, posts.len);
//     insertPost(allocator, handle, .{
//         .timestamp = @floatFromInt(BASE_TIMESTAMP + MAX_POST_BUFFER_SIZE + 1),
//         .text = "a",
//         .languages = "b",
//         .author_name = "c",
//         .author_handle = "c",
//         .hash = @intCast(88567376),
//         .flags = "f",
//         .world_id = "w",
//     });

//     const posts2 = try fetchA(allocator, handle, BASE_TIMESTAMP);
//     defer deinitGivenList(allocator, posts2);
//     try std.testing.expectEqual(MAX_POST_BUFFER_SIZE, posts2.len);
//     insertPost(allocator, handle, .{
//         .timestamp = @floatFromInt(BASE_TIMESTAMP + MAX_POST_BUFFER_SIZE + 2),
//         .text = "a",
//         .languages = "b",
//         .author_name = "c",
//         .author_handle = "c",
//         .hash = @intCast(88567376),
//         .flags = "f",
//         .world_id = "w",
//     });
//     const posts3 = try fetchA(allocator, handle, BASE_TIMESTAMP + MAX_POST_BUFFER_SIZE);
//     defer deinitGivenList(allocator, posts3);
//     try std.testing.expectEqual(2, posts3.len);
// }

// fn deinitGivenList(allocator: std.mem.Allocator, list: []*Post) void {
//     for (list) |post| post.deinitVia(allocator);
//     allocator.free(list);
// }
