const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "amun-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    b.installArtifact(exe);

    switch (target.result.os.tag) {
        .linux => {
            exe.linkSystemLibrary("LLVM-14");
            exe.addIncludePath(.{ .path = "/usr/lib/llvm-14/include/" });
        },
        .macos => {
            exe.addLibraryPath(.{ .path = "/usr/local/opt/llvm/lib" });
            exe.linkSystemLibrary("LLVM");
        },
        else => exe.linkSystemLibrary("LLVM"),
    }
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
