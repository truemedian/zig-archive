const std = @import("std");
const archive = @import("archive");

const alloc = std.heap.c_allocator;

pub fn main() !void {
    try std.fs.cwd().makePath("tests/zip");

    const file = try std.fs.cwd().createFile("tests/zip/test.zip", .{});
    defer file.close();

    var stream = std.io.StreamSource{ .file = file };

    var arc = archive.formats.zip.writer.ArchiveWriter.init(alloc, &stream);
    defer arc.deinit();

    var i: usize = 0;
    while (i < 100000) : (i += 1) {
        const name = try std.fmt.allocPrint(alloc, "test{}.txt", .{i});
        defer alloc.free(name);

        try arc.writeString(name, "aaaa", false);
    }

    try arc.finish();
}
