pub const std = @import("std");

pub fn HashingWriter(comptime WriterType: type, comptime Crc32: type) type {
    return struct {
        const Self = @This();

        pub const WriteError = WriterType.Error;

        sink: WriterType,
        hash: Crc32,

        pub const Writer = std.io.Writer(*Self, WriteError, write);

        pub fn init(writer_: WriterType) Self {
            return .{
                .sink = writer_,
                .hash = Crc32.init(),
            };
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            const nwrit = try self.sink.write(bytes);
            self.hash.update(bytes[0..nwrit]);
            return nwrit;
        }
    };
}
