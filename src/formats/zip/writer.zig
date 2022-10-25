const std = @import("std");

const math = std.math;
const ascii = std.ascii;
const deflate = std.compress.deflate;

const HashingWriter = @import("../../hashing_writer.zig").HashingWriter;

const format = @import("format.zig");

const version_needed_non64 = format.Version{ .vendor = .dos, .major = 2, .minor = 0 };
const version_needed_with64 = format.Version{ .vendor = .dos, .major = 4, .minor = 5 };

const Fifo = std.fifo.LinearFifo(u8, .{ .Static = 8192 });

pub const ArchiveWriter = struct {
    sink: *std.io.StreamSource,

    directory: std.ArrayListUnmanaged(format.CentralDirectoryRecord) = .{},
    filenames: std.ArrayListUnmanaged([]const u8) = .{},
    extra_data: std.ArrayListUnmanaged(format.ExtraFieldZip64) = .{},

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, sink: *std.io.StreamSource) ArchiveWriter {
        return .{
            .allocator = allocator,
            .sink = sink,
        };
    }

    pub fn deinit(self: *ArchiveWriter) void {
        self.directory.deinit(self.allocator);

        self.filenames.deinit(self.allocator);
    }

    pub fn finish(self: *ArchiveWriter) !void {
        const offset = try self.sink.getPos();
        for (self.directory.items) |record| {
            try record.write(self.sink.writer());

            const name = self.filenames.items[record.filename_idx];
            try self.sink.writer().writeAll(name);

            const extra = self.extra_data.items[record.filename_idx];
            try extra.write(self.sink.writer());
        }
        const final_offset = try self.sink.getPos();

        var eocd = std.mem.zeroes(format.EndOfCentralDirectoryRecord);
        eocd.entries_on_disk = @intCast(u16, self.directory.items.len);
        eocd.entries_total = @intCast(u16, self.directory.items.len);
        eocd.directory_size = @intCast(u32, final_offset - offset);
        eocd.directory_offset = @intCast(u32, offset);

        try eocd.write(self.sink.writer());
    }

    pub fn writeString(self: *ArchiveWriter, name: []const u8, str: []const u8, compress: bool) !void {
        const fbs = std.io.fixedBufferStream(str);

        var src = std.io.StreamSource{ .const_buffer = fbs };

        return self.writeSource(name, &src, compress);
    }

    pub fn writeSource(self: *ArchiveWriter, name: []const u8, src: *std.io.StreamSource, compress: bool) !void {
        var local = std.mem.zeroes(format.LocalFileRecord);

        local.signature = format.LocalFileRecord.signature;
        local.compression_method = if (compress) .deflated else .none;

        local.filename_len = @truncate(u16, name.len);

        const uncomp_size = try src.getEndPos();
        const local_offset = try self.sink.getPos();

        const need_size64 = uncomp_size > math.maxInt(i32);
        const need_offset64 = local_offset > math.maxInt(i32);

        var extra = format.ExtraFieldZip64{};

        if (need_size64) {
            local.version = version_needed_with64.write();

            extra.uncompressed = uncomp_size;
            extra.compressed = 0;
        } else {
            local.version = version_needed_non64.write();
        }

        local.extra_len = extra.length();

        try self.sink.seekBy(@intCast(i64, format.LocalFileRecord.size + name.len + local.extra_len));

        var hashing = HashingStreamWriter.init(self.sink.writer());
        var buffered = BufferedWriter{ .unbuffered_writer = hashing.writer() };
        var comp_size: u64 = 0;

        var fifo = Fifo.init();
        if (compress) {
            var compressor = try std.compress.deflate.compressor(self.allocator, buffered.writer(), .{});

            try fifo.pump(src.reader(), compressor.writer());
            try compressor.flush();

            comp_size = compressor.bytesWritten();
        } else {
            try fifo.pump(src.reader(), buffered.writer());
            comp_size = uncomp_size;
        }

        try buffered.flush();

        const last_offset = try self.sink.getPos();

        if (need_size64) {
            extra.compressed = comp_size;

            local.uncompressed_size = math.maxInt(u32);
            local.compressed_size = math.maxInt(u32);
        } else {
            local.uncompressed_size = @intCast(u32, uncomp_size);
            local.compressed_size = @intCast(u32, comp_size);
        }

        local.crc32 = hashing.hash.final();

        try self.sink.seekableStream().seekTo(local_offset);

        try local.write(self.sink.writer());
        try self.sink.writer().writeAll(name);

        try extra.write(self.sink.writer());

        try self.sink.seekTo(last_offset);

        var entry = try self.directory.addOne(self.allocator);
        entry.* = std.mem.zeroes(format.CentralDirectoryRecord);

        entry.version_made = local.version;
        entry.version_needed = local.version;
        entry.flags = local.flags;
        entry.compression_method = local.compression_method;
        entry.last_mod_time = local.last_mod_time;
        entry.last_mod_date = local.last_mod_date;
        entry.crc32 = local.crc32;
        entry.compressed_size = local.compressed_size;
        entry.uncompressed_size = local.uncompressed_size;
        entry.filename_len = local.filename_len;
        entry.extra_len = local.extra_len;

        if (need_offset64) {
            extra.offset = local_offset;

            entry.version_made = version_needed_with64.write();
            entry.version_needed = version_needed_with64.write();

            entry.local_offset = math.maxInt(u32);
            entry.extra_len = extra.length();
        } else {
            entry.local_offset = @intCast(u32, local_offset);
        }

        entry.filename_idx = self.filenames.items.len;

        const duped_name = try self.allocator.dupe(u8, name);
        try self.filenames.append(self.allocator, duped_name);
        try self.extra_data.append(self.allocator, extra);
    }
};

const BufferedWriter = std.io.BufferedWriter(8192, HashingStreamWriter.Writer);
const HashingStreamWriter = HashingWriter(std.io.StreamSource.Writer, format.Crc32);
