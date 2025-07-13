const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{}); // e.g.: std.builtin.OptimizeMode.ReleaseSmall

    // Create the executable module and wol module
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // note: wol module is created so that other projects can use it with zig fetch and @import("wol").
    const wol_module = b.addModule("wol", .{
        .root_source_file = b.path("src/wol.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies from local modules
    exe_module.addImport("wol", wol_module);

    // Add dependencies from third-party libs (see build.zig.zon)
    exe_module.addImport("clap", b.dependency("clap", .{}).module("clap"));

    // Create, add and install the executable
    const exe = b.addExecutable(.{
        .root_module = exe_module,
        .name = "zig-wol",
    });
    b.installArtifact(exe);

    // Generate documentation step (run this with "zig build docs")
    const install_docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    // Create a test step (run this with "zig build test") to run all tests in src/tests.zig
    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
