const std = @import("std");
const archive = @import("archive");

const alloc = std.heap.page_allocator;

pub fn main() !void {
    const in_dir = try std.fs.cwd().openIterableDir("tests/zip", .{});
    var it = in_dir.iterate();

    while (try it.next()) |entry| {
        const fd = try in_dir.dir.openFile(entry.name, .{});
        defer fd.close();

        const extract_path = try std.fs.path.join(alloc, &.{ "tests/extract/zip", entry.name });
        defer alloc.free(extract_path);

        try std.fs.cwd().deleteTree(extract_path);

        var extract_dir = try std.fs.cwd().makeOpenPath(extract_path, .{});
        defer extract_dir.close();

        // const str = try fd.readToEndAlloc(alloc, 1024 * 1024 * 1024);
        // defer alloc.free(str);

        // var stream = std.io.FixedBufferStream([]const u8){ .buffer = str, .pos = 0 };

        // var source = std.io.StreamSource{ .const_buffer = stream };
        var source = std.io.StreamSource{ .file = fd };

        var timer = std.time.Timer.start() catch unreachable;

        var arc = archive.formats.zip.reader.ArchiveReader.init(alloc, source);
        defer arc.deinit();

        timer.reset();

        try arc.load();

        const load_taken = @intToFloat(f64, timer.read()) / 1e9;
        const load_speed = @intToFloat(f64, arc.__directory_size) / load_taken;

        var size: usize = 0;

        timer.reset();

        for (arc.directory.items) |_, i| {
            const hdr = arc.getHeader(i);

            size += hdr.uncompressed_size;

            if (hdr.uncompressed_size > 0) {
                try extract_dir.makePath(std.fs.path.dirname(hdr.filename) orelse ".");
                const out = try extract_dir.createFile(hdr.filename, .{});
                defer out.close();

                try arc.extractFile(hdr, out.writer());
            }
        }

        const taken_extract = @intToFloat(f64, timer.read()) / 1e9;
        const speed_extract = @intToFloat(f64, size) / taken_extract;

        std.debug.print(
            \\name: {s}
            \\size: {d}
            \\directory: {d} items, {d} bytes, {d} bytes of filenames
            \\
            \\load: {d:.6} ms, {d:.6} MB/s
            \\extract: {d:.6} ms, {d:.6} MB/s
            \\
            \\
        , .{
            entry.name,
            try source.getEndPos(),
            arc.directory.items.len,
            arc.__directory_size,
            arc.filename_buf.items.len,
            load_taken * 1e3,
            load_speed / 1e6,
            taken_extract * 1e3,
            speed_extract / 1e6,
        });
    }
}
