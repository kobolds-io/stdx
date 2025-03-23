const std = @import("std");

const version = std.SemanticVersion{ .major = 0, .minor = 0, .patch = 0 };

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This is shamelessly taken from the `zbench` library's `build.zig` file. see [here](https://github.com/hendriknielaender/zBench/blob/b69a438f5a1a96d4dd0ea69e1dbcb73a209f76cd/build.zig)
    setupLibrary(b, target, optimize);

    setupTests(b, target, optimize);

    setupExamples(b, target, optimize);
}

fn setupLibrary(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const lib = b.addStaticLibrary(.{
        .name = "stdx",
        .root_source_file = b.path("src/stdx.zig"),
        .target = target,
        .optimize = optimize,
        .version = version,
    });

    b.installArtifact(lib);
}

fn setupTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

fn setupExamples(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const example_step = b.step("examples", "Build examples");
    const example_names = [_][]const u8{
        "ring_buffer",
    };

    for (example_names) |example_name| {
        const example_exe = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
            .target = target,
            .optimize = optimize,
        });
        const install_example = b.addInstallArtifact(example_exe, .{});

        const stdx_mod = b.addModule("stdx", .{
            .root_source_file = b.path("src/stdx.zig"),
            .target = target,
            .optimize = optimize,
        });

        example_exe.root_module.addImport("stdx", stdx_mod);
        example_step.dependOn(&example_exe.step);
        example_step.dependOn(&install_example.step);
    }
}
