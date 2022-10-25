const std = @import("std");

pub const formats = struct {
    pub const zip = struct {
        pub const reader = @import("formats/zip/reader.zig");
        pub const writer = @import("formats/zip/writer.zig");

        pub const internal = @import("formats/zip/format.zig");
    };
};

comptime {
    std.testing.refAllDecls(formats);
}
