const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_mod.linkSystemLibrary("glfw", .{ .needed = true });
    lib_mod.linkSystemLibrary("GL", .{ .needed = true }); // or OpenGL on mac
    lib_mod.linkSystemLibrary("X11", .{ .needed = true }); // for Linux, if GLFW needs it

    const zglfw = b.dependency("zglfw", .{});
    lib_mod.addImport("zglfw", zglfw.module("root"));
    if (target.result.os.tag != .emscripten) lib_mod.linkLibrary(zglfw.artifact("glfw"));
    lib_mod.linkSystemLibrary("X11", .{ .needed = true });

    const wgpu_native_dep = b.dependency("wgpu_native_zig", .{});
    lib_mod.addImport("wgpu", wgpu_native_dep.module("wgpu"));

    lib_mod.linkSystemLibrary("SDL3_image", .{ .needed = true });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("engine_lib", lib_mod);

    const exe = b.addExecutable(.{
        .name = "engine",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
