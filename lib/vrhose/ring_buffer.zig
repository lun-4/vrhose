const std = @import("std");

pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: []T,
        head: usize,
        tail: usize,
        len: usize,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, initialCapacity: usize) !Self {
            const buffer = try allocator.alloc(T, initialCapacity);
            return Self{
                .buffer = buffer,
                .head = 0,
                .tail = 0,
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
        }

        pub fn push(self: *Self, item: T) !void {
            if (self.len == self.buffer.len) {
                return error.BufferFull;
            }

            self.buffer[self.tail] = item;
            self.tail = (self.tail + 1) % self.buffer.len;
            self.len += 1;
        }

        pub fn pop(self: *Self) ?*T {
            if (self.len == 0) {
                return null;
            }

            const item = &self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.len -= 1;
            return item;
        }

        pub fn peek(self: *Self) ?T {
            if (self.len == 0) {
                return null;
            }
            return self.buffer[self.head];
        }

        pub fn clear(self: *Self) void {
            self.head = 0;
            self.tail = 0;
            self.len = 0;
        }

        pub fn isFull(self: *Self) bool {
            return self.len == self.buffer.len;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.len == 0;
        }

        pub fn capacity(self: *Self) usize {
            return self.buffer.len;
        }

        pub fn length(self: *Self) usize {
            return self.len;
        }

        pub fn iterator(self: *Self) Iterator {
            return Iterator{
                .buffer = self,
                .current = 0,
            };
        }

        pub const Iterator = struct {
            buffer: *Self,
            current: usize,

            pub fn next(self: *Iterator) ?*T {
                if (self.current >= self.buffer.len) {
                    return null;
                }
                const index = (self.buffer.head + self.current) % self.buffer.buffer.len;
                self.current += 1;
                return &self.buffer.buffer[index];
            }
        };
    };
}
