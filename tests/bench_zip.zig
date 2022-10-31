const std = @import("std");
const archive = @import("archive");

const Benchmark = @import("benchmark.zig").Benchmark;

const build_options = @import("build_options");

const alloc = std.heap.page_allocator;

pub fn main() !void {
    const in_dir = try std.fs.cwd().openIterableDir("tests/zip", .{});

    // Write Benchmarks

    std.debug.print("*** Write Benchmarks ***\n", .{});

    {
        var benchmark = Benchmark(.{ "add", "finish" }, build_options.runtime){};
        var timer = std.time.Timer.start() catch unreachable;

        var runtime_timer = std.time.Timer.start() catch unreachable;
        var first = true;

        var buf = try alloc.alloc(u8, 1037802);
        defer alloc.free(buf);

        while (benchmark.run()) {
            const fd = try in_dir.dir.createFile("small.zip", .{});
            defer fd.close();
            defer if (comptime build_options.void_write) in_dir.dir.deleteFile("small.zip") catch {};

            var fbs = std.io.fixedBufferStream(buf);

            var stream = if (comptime build_options.void_write)
                std.io.StreamSource{ .buffer = fbs }
            else
                std.io.StreamSource{ .file = fd };

            var arc = archive.formats.zip.writer.ArchiveWriter.init(alloc, &stream);
            defer arc.deinit();

            timer.reset();

            var i: usize = 0;
            while (i < 10000) : (i += 1) {
                const name = try std.fmt.allocPrint(alloc, "test{}.txt", .{i});
                defer alloc.free(name);

                try arc.writeString(name, "aaaa", false);
            }

            const offset = @intCast(usize, try stream.getPos());

            benchmark.add("add", timer.read());
            benchmark.setSize("add", offset);

            timer.reset();

            try arc.finish();

            const offset_after = @intCast(usize, try stream.getPos());

            benchmark.add("finish", timer.read());
            benchmark.setSize("finish", offset_after - offset);

            if (first) {
                first = false;
                std.debug.print(
                    \\name: small.zip
                    \\size: {d}
                    \\directory: {d} items, {d} bytes, {d} bytes of filenames
                    \\
                    \\
                , .{
                    try stream.getEndPos(),
                    arc.directory.items.len,
                    offset_after - offset,
                    arc.filenames.items.len,
                });
            }
        }

        const runtime = runtime_timer.read();
        std.debug.print("done in {d}s\n\n", .{runtime / 1_000_000_000});

        benchmark.report();
    }

    {
        var benchmark = Benchmark(.{ "add", "finish" }, build_options.runtime){};
        var timer = std.time.Timer.start() catch unreachable;

        var runtime_timer = std.time.Timer.start() catch unreachable;
        var first = true;

        var buf = try alloc.alloc(u8, 13402);
        defer alloc.free(buf);

        while (benchmark.run()) {
            const fd = try in_dir.dir.createFile("large.zip", .{});
            defer fd.close();
            defer if (comptime build_options.void_write) in_dir.dir.deleteFile("large.zip") catch {};

            var fbs = std.io.fixedBufferStream(buf);

            var stream = if (comptime build_options.void_write)
                std.io.StreamSource{ .buffer = fbs }
            else
                std.io.StreamSource{ .file = fd };


            var arc = archive.formats.zip.writer.ArchiveWriter.init(alloc, &stream);
            defer arc.deinit();

            timer.reset();

            var i: usize = 0;
            while (i < 100) : (i += 1) {
                const name = try std.fmt.allocPrint(alloc, "test{}.txt", .{i});
                defer alloc.free(name);

                try arc.writeString(name, "aaaa" ** 4096, true);
            }

            const offset = @intCast(usize, try stream.getPos());

            benchmark.add("add", timer.read());
            benchmark.setSize("add", offset);

            timer.reset();

            try arc.finish();

            const offset_after = @intCast(usize, try stream.getPos());

            benchmark.add("finish", timer.read());
            benchmark.setSize("finish", offset_after - offset);

            if (first) {
                first = false;
                std.debug.print(
                    \\name: large.zip
                    \\size: {d}
                    \\directory: {d} items, {d} bytes, {d} bytes of filenames
                    \\
                    \\
                , .{
                    try stream.getEndPos(),
                    arc.directory.items.len,
                    offset_after - offset,
                    arc.filenames.items.len,
                });
            }
        }

        const runtime = runtime_timer.read();
        std.debug.print("done in {d}s\n\n", .{runtime / 1_000_000_000});

        benchmark.report();
    }

    // Read Benchmarks

    std.debug.print("*** Read Benchmarks ***\n", .{});

    var it = in_dir.iterate();

    while (try it.next()) |entry| {
        var first = true;

        var benchmark = Benchmark(.{ "load", "extract" }, build_options.runtime){};
        var timer = std.time.Timer.start() catch unreachable;

        const fd = try in_dir.dir.openFile(entry.name, .{});
        defer fd.close();

        const extract_path = try std.fs.path.join(alloc, &.{ "tests/extract/zip", entry.name });
        defer alloc.free(extract_path);

        var extract_dir = try std.fs.cwd().makeOpenPath(extract_path, .{});
        defer extract_dir.close();

        const str = if (comptime build_options.preallocate)
            try fd.readToEndAlloc(alloc, 1024 * 1024 * 1024)
        else {};
        defer if (comptime build_options.preallocate) alloc.free(str);

        var runtime_timer = std.time.Timer.start() catch unreachable;

        while (benchmark.run()) {
            const stream = if (comptime build_options.preallocate)
                std.io.fixedBufferStream(@as([]const u8, str))
            else {};

            var source = if (comptime build_options.preallocate)
                std.io.StreamSource{ .const_buffer = stream }
            else
                std.io.StreamSource{ .file = fd };

            var arc = archive.formats.zip.reader.ArchiveReader.init(alloc, &source);
            defer arc.deinit();

            // Load

            timer.reset();

            try arc.load();

            benchmark.add("load", timer.read());
            benchmark.setSize("load", arc.directory_size);

            // Extract

            if (!comptime build_options.void_write) {
                try std.fs.cwd().deleteTree(extract_path);
            }

            var size: usize = 0;

            for (arc.directory.items) |_, j| {
                const hdr = arc.getHeader(j);

                size += hdr.uncompressed_size;

                if (hdr.uncompressed_size > 0) {
                    if (comptime build_options.void_write) {
                        const out = std.io.null_writer;

                        try arc.extractFile(hdr, out, true);
                    } else {
                        try extract_dir.makePath(std.fs.path.dirname(hdr.filename) orelse ".");
                        const out = try extract_dir.createFile(hdr.filename, .{});
                        defer out.close();

                        try arc.extractFile(hdr, out.writer(), true);
                    }
                }
            }

            benchmark.add("extract", timer.read());
            benchmark.setSize("extract", size);

            if (first) {
                first = false;
                std.debug.print(
                    \\name: {s}
                    \\size: {d}
                    \\directory: {d} items, {d} bytes, {d} bytes of filenames
                    \\
                    \\
                , .{
                    entry.name,
                    try source.getEndPos(),
                    arc.directory.items.len,
                    arc.directory_size,
                    arc.filename_buf.items.len,
                });
            }
        }

        const runtime = runtime_timer.read();
        std.debug.print("done in {d}s\n\n", .{runtime / 1_000_000_000});

        benchmark.report();
    }
}
