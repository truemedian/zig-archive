const std = @import("std");
const archive = @import("archive");

const alloc = std.heap.page_allocator;

pub fn main() !void {
    const in_dir = try std.fs.cwd().openIterableDir("tests/zip", .{});
    var it = in_dir.iterate();

    while (try it.next()) |entry| {
        var first = true;

        var benchmark = Benchmark(.{ "load", "extract" }, 60){};
        var timer = std.time.Timer.start() catch unreachable;

        const fd = try in_dir.dir.openFile(entry.name, .{});
        defer fd.close();

        const extract_path = try std.fs.path.join(alloc, &.{ "tests/extract/zip", entry.name });
        defer alloc.free(extract_path);

        const str = try fd.readToEndAlloc(alloc, 1024 * 1024 * 1024);
        defer alloc.free(str);

        var runtime_timer = std.time.Timer.start() catch unreachable;

        while (benchmark.run()) {
            try std.fs.cwd().deleteTree(extract_path);

            var extract_dir = try std.fs.cwd().makeOpenPath(extract_path, .{});
            defer extract_dir.close();

            var stream = std.io.fixedBufferStream(@as([]const u8, str));
            var source = std.io.StreamSource{ .const_buffer = stream };
            // var source = std.io.StreamSource{ .file = fd };

            var arc = archive.formats.zip.reader.ArchiveReader.init(alloc, source);
            defer arc.deinit();

            // Load

            timer.reset();

            try arc.load();

            benchmark.add("load", timer.read());
            benchmark.setSize("load", arc.__directory_size);

            // Extract

            var size: usize = 0;

            timer.reset();

            for (arc.directory.items) |_, j| {
                const hdr = arc.getHeader(j);

                size += hdr.uncompressed_size;

                if (hdr.uncompressed_size > 0) {
                    // try extract_dir.makePath(std.fs.path.dirname(hdr.filename) orelse ".");
                    // const out = try extract_dir.createFile(hdr.filename, .{});
                    // defer out.close();

                    const out = std.io.null_writer;

                    try arc.extractFile(hdr, out);
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
                    arc.__directory_size,
                    arc.filename_buf.items.len,
                });
            }
        }

        const runtime = runtime_timer.read();
        std.debug.print("done in {d}s\n\n", .{runtime / 1_000_000_000});

        benchmark.report();
    }
}

pub fn Benchmark(
    comptime datasets: anytype,
    comptime runtime_sec: comptime_int,
) type {
    return struct {
        const Self = @This();

        measurements: [datasets.len]std.ArrayListUnmanaged(f64) = .{.{}} ** datasets.len,
        sizes: [datasets.len]usize = .{0} ** datasets.len,

        samples: usize = 0,
        iteration: usize = 0,
        warmups: i32 = 100,

        pub fn run(self: *Self) bool {
            if (self.warmups >= 0) {
                if (self.warmups == 0) {
                    var samples = std.math.inf(f64);

                    inline for (datasets) |dataset| {
                        samples = std.math.min(samples, (runtime_sec * 1e9) / self.mean(dataset));
                    }

                    self.samples = @floatToInt(usize, samples) + 1;
                }

                self.warmups -= 1;

                return true;
            } else {
                if (self.iteration == self.samples)
                    return false;

                self.iteration += 1;
                return true;
            }
        }

        pub fn add(self: *Self, comptime field: []const u8, measurement: u64) void {
            self.measurements[indexOf(field)]
                .append(alloc, @intToFloat(f64, measurement)) catch @panic("oom");
        }

        pub fn setSize(self: *Self, comptime field: []const u8, size: usize) void {
            self.sizes[indexOf(field)] = size;
        }

        fn indexOf(comptime field: []const u8) comptime_int {
            inline for (datasets) |dataset, i| {
                if (std.mem.eql(u8, dataset, field)) return i;
            }

            unreachable;
        }

        pub fn min(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var val: f64 = std.math.inf(f64);

            for (items) |measurement| {
                if (measurement < val) val = measurement;
            }

            return val;
        }

        pub fn max(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var val: f64 = -std.math.inf(f64);

            for (items) |measurement| {
                if (measurement > val) val = measurement;
            }

            return val;
        }

        pub fn mean(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var sum: f64 = 0.0;

            for (items) |measurement| {
                sum += measurement;
            }

            return sum / @intToFloat(f64, items.len);
        }

        pub fn median(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            std.sort.sort(f64, items, {}, comptime std.sort.asc(f64));

            if (items.len % 2 == 0) {
                return (items[items.len / 2] + items[items.len / 2 - 1]) / 2;
            } else {
                return items[items.len / 2];
            }
        }

        pub fn stddev(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var sum_sq: f64 = 0.0;

            for (items) |measurement| {
                sum_sq += measurement * measurement;
            }

            const avg = self.mean(field);

            return std.math.sqrt(sum_sq / @intToFloat(f64, items.len) - avg * avg);
        }

        pub fn confidence(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            const dev = self.stddev(field);

            return 2.58 * dev / std.math.sqrt(@intToFloat(f64, items.len));
        }

        pub fn meanSpeed(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var sum: f64 = 0.0;

            for (items) |measurement| {
                sum += @intToFloat(f64, self.sizes[indexOf(field)]) / (measurement / 1e9);
            }

            return sum / @intToFloat(f64, items.len);
        }

        pub fn stddevSpeed(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var sum_sq: f64 = 0.0;

            for (items) |measurement| {
                const speed = @intToFloat(f64, self.sizes[indexOf(field)]) / (measurement / 1e9);

                sum_sq += speed * speed;
            }

            const avg = self.meanSpeed(field);

            return std.math.sqrt(sum_sq / @intToFloat(f64, items.len) - avg * avg);
        }

        pub fn confidenceSpeed(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            const dev = self.stddevSpeed(field);

            return 2.58 * dev / std.math.sqrt(@intToFloat(f64, items.len));
        }

        pub fn reportSingle(self: Self, comptime field: []const u8) void {
            std.debug.print(
                \\{s} ({d} samples):
                \\  min: {}
                \\  max: {}
                \\  mean: {} ± {}
                \\  median: {}
                \\  stddev: {}
                \\  speed: {} ± {}
                \\
                \\
            , .{
                field,
                self.samples,
                Nanoseconds{ .data = self.min(field) },
                Nanoseconds{ .data = self.max(field) },
                Nanoseconds{ .data = self.mean(field) },
                Nanoseconds{ .data = self.confidence(field) },
                Nanoseconds{ .data = self.median(field) },
                Nanoseconds{ .data = self.stddev(field) },
                BytesPerSecond{ .data = self.meanSpeed(field) },
                BytesPerSecond{ .data = self.confidenceSpeed(field) },
            });
        }

        pub fn report(self: Self) void {
            inline for (datasets) |dataset| {
                self.reportSingle(dataset);
            }
        }
    };
}

fn formatBytesPerSecond(
    data: f64,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    if (data > 1024 * 1024 * 1024) {
        try writer.print("{d:.3} GB/s", .{data / (1024 * 1024 * 1024)});
    } else if (data > 1024 * 1024) {
        try writer.print("{d:.3} MB/s", .{data / (1024 * 1024)});
    } else if (data > 1024) {
        try writer.print("{d:.3} KB/s", .{data / (1024)});
    } else {
        try writer.print("{d:.3} B/s", .{data});
    }
}

const BytesPerSecond = std.fmt.Formatter(formatBytesPerSecond);

fn formatNanoseconds(
    data: f64,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    if (data > std.time.ns_per_min) {
        try writer.print("{d:.3} min", .{data / std.time.ns_per_min});
    } else if (data > std.time.ns_per_s) {
        try writer.print("{d:.3} s", .{data / std.time.ns_per_s});
    } else if (data > std.time.ns_per_ms) {
        try writer.print("{d:.3} ms", .{data / std.time.ns_per_ms});
    } else if (data > std.time.ns_per_us) {
        try writer.print("{d:.3} us", .{data / std.time.ns_per_us});
    } else {
        try writer.print("{d:.3} ns", .{data});
    }
}

const Nanoseconds = std.fmt.Formatter(formatNanoseconds);
