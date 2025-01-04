const std = @import("std");

const version = std.SemanticVersion{ .major = 1, .minor = 0, .patch = 1 };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "nrz",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = optimize == .ReleaseFast,
    });

    const buildOptions = b.addOptions();
    buildOptions.addOption(std.SemanticVersion, "version", version);

    exe.root_module.addOptions("build_options", buildOptions);

    b.installArtifact(exe);

    const exe_check = b.addExecutable(.{
        .name = "nrz",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = optimize == .ReleaseFast,
    });

    const check = b.step("check", "zls build check");
    check.dependOn(&exe_check.step);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const string_tests = b.addTest(.{
        .root_source_file = b.path("src/string.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_string_tests = b.addRunArtifact(string_tests);

    const helpers_tests = b.addTest(.{
        .root_source_file = b.path("src/helpers.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_helpers_tests = b.addRunArtifact(helpers_tests);

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_string_tests.step);
    test_step.dependOn(&run_helpers_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const clean_step = b.step("clean", "clean caches");
    clean_step.dependOn(&b.addRemoveDirTree(b.pathFromRoot(".zig-cache/")).step);
}
