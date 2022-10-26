const std = @import("std");
const archive = @import("archive");

const alloc = std.heap.page_allocator;

pub fn main() !void {
    const file = try std.fs.cwd().createFile("tests/zip/test.zip", .{ });
    defer file.close();

    var stream = std.io.StreamSource{ .file = file };

    var arc = archive.formats.zip.writer.ArchiveWriter.init(alloc, &stream);
    defer arc.deinit();

    try arc.writeString("test.txt", "aaaaaabbbbbbcccccc", true);
    try arc.finish();
}
