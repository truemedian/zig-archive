const std = @import("std");

pub fn mixin(comptime ReaderType: type, comptime SeekerType: type) type {
    const ReaderCtx = std.meta.fieldInfo(ReaderType, .context).field_type;
    const SeekerTypeCtx = std.meta.fieldInfo(SeekerType, .context).field_type;

    if (ReaderCtx != SeekerTypeCtx)
        @compileError("ReaderType and SeekerType must have the same context type");

    return struct {
        pub const BufferedReader = std.io.BufferedReader(8192, ReaderType);

        pub inline fn buffered(reader: ReaderType) BufferedReader {
            return BufferedReader{ .unbuffered_reader = reader };
        }

        pub fn seekBy(seeker: SeekerType, buffer: *BufferedReader, offset: i64) !void {
            if (offset == 0) return;

            if (offset > 0) {
                const u_offset = @intCast(u64, offset);

                if (u_offset <= buffer.fifo.count) {
                    buffer.fifo.discard(u_offset);
                } else if (u_offset <= buffer.fifo.count + buffer.fifo.buf.len) {
                    const left = u_offset - buffer.fifo.count;

                    buffer.fifo.discard(buffer.fifo.count);
                    try buffer.reader().skipBytes(left, .{ .buf_size = 8192 });
                } else {
                    const left = u_offset - buffer.fifo.count;

                    buffer.fifo.discard(buffer.fifo.count);
                    try seeker.seekBy(@intCast(i64, left));
                }
            } else {
                const left = offset - @intCast(i64, buffer.fifo.count);

                buffer.fifo.discard(buffer.fifo.count);
                try seeker.seekBy(left);
            }
        }

        pub fn getPos(seeker: SeekerType, buffer: *BufferedReader) !u64 {
            const pos = try seeker.getPos();

            return pos - buffer.fifo.count;
        }

        pub fn seekTo(seeker: SeekerType, buffer: *BufferedReader, pos: u64) !void {
            const offset = @intCast(i64, pos) - @intCast(i64, try getPos(seeker, buffer));

            try seeker.seekBy(buffer, offset);
        }

        pub const LimitedReader = struct {
            unlimited_reader: BufferedReader.Reader,
            limit: usize,
            pos: usize = 0,

            pub const Error = BufferedReader.Reader.Error;
            pub const Reader = std.io.Reader(*Self, Error, read);

            const Self = @This();

            pub fn init(unlimited_reader: BufferedReader.Reader, limit: usize) Self {
                return .{
                    .unlimited_reader = unlimited_reader,
                    .limit = limit,
                };
            }

            fn read(self: *Self, dest: []u8) Error!usize {
                if (self.pos >= self.limit) return 0;

                const left = std.math.min(self.limit - self.pos, dest.len);
                const num_read = try self.unlimited_reader.read(dest[0..left]);
                self.pos += num_read;

                return num_read;
            }

            pub fn reader(self: *Self) Reader {
                return .{ .context = self };
            }
        };
    };
}
