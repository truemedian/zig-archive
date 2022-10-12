const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    // Library Tests

    const lib_tests = b.addTest("src/main.zig");
    lib_tests.setBuildMode(mode);

    const tests = b.step("test", "Run all library tests");
    tests.dependOn(&lib_tests.step);

    // Test Runners

    const zip_runner = b.addExecutable("zip-test", "tests/zip.zig");
    zip_runner.setBuildMode(mode);

    zip_runner.addPackagePath("archive", "src/main.zig");

    const run_zip_runner = zip_runner.run();
    zip_runner.install();

    const run_tests = b.step("zip", "Run zip tests");
    run_tests.dependOn(&run_zip_runner.step);
}
