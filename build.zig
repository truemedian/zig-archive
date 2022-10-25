const std = @import("std");

const Builder = std.build.Builder;

const tests = .{
    "read_zip",
    "write_zip",
};

const bench = .{
    "bench_zip",
};

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    // Library Tests

    const lib_tests = b.addTest("src/main.zig");
    lib_tests.setBuildMode(mode);

    const lib_tests_step = b.step("test", "Run all library tests");
    lib_tests_step.dependOn(&lib_tests.step);

    // Test Runners

    inline for (tests) |file| {
        const zip_runner = b.addExecutable(file, "tests/" ++ file ++ ".zig");
        zip_runner.setBuildMode(mode);

        zip_runner.addPackagePath("archive", "src/main.zig");

        zip_runner.install();
        const run_zip_runner = zip_runner.run();

        const run_tests = b.step(file, "Run tests");
        run_tests.dependOn(&run_zip_runner.step);
    }
    // Benchmarks

    const preallocate = b.option(bool, "preallocate", "Allocate the file into memory rather than reading from disk [true].") orelse true;
    const void_write = b.option(bool, "void_write", "Write to a void file rather than a real file when extracting [true].") orelse true;
    const runtime = b.option(u32, "runtime", "How long to run benchmarks in seconds [60].") orelse 60;

    const bench_options = b.addOptions();
    bench_options.addOption(bool, "preallocate", preallocate);
    bench_options.addOption(bool, "void_write", void_write);
    bench_options.addOption(u32, "runtime", runtime);

    inline for (bench) |file| {
        const zip_bench = b.addExecutable(file, "tests/" ++ file ++ ".zig");
        zip_bench.setBuildMode(mode);
        zip_bench.addOptions("build_options", bench_options);
        zip_bench.addPackagePath("archive", "src/main.zig");

        zip_bench.install();
        const run_zip_bench = zip_bench.run();

        const zip_bench_step = b.step(file, "Run benchmark");
        zip_bench_step.dependOn(&run_zip_bench.step);
    }
}
