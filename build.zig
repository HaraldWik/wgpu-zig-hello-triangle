const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_mod = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#if defined(_WIN32) || defined(_WIN64)
            \\#define GLFW_EXPOSE_NATIVE_WIN32
            \\#elif defined(__APPLE__) || defined(__MACH__)
            \\#define GLFW_EXPOSE_NATIVE_COCOA
            \\#elif defined(__linux__) || defined(__unix)
            \\#define GLFW_EXPOSE_NATIVE_WAYLAND
            \\#define GLFW_EXPOSE_NATIVE_X11
            \\#endif
            \\
            \\#include <GLFW/glfw3.h>
            \\#include <GLFW/glfw3native.h>
        ),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }).createModule();
    c_mod.linkSystemLibrary("glfw", .{});

    const wgpu_mod = b.dependency("wgpu_native_zig", .{}).module("wgpu");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
            .{ .name = "wgpu", .module = wgpu_mod },
        },
    });
    mod.linkSystemLibrary("SDL3_image", .{});

    // mod.linkSystemLibrary("glfw", .{});
    // mod.linkSystemLibrary("GL", .{}); // or OpenGL on mac
    mod.linkSystemLibrary("X11", .{}); // for Linux, if GLFW needs it

    mod.linkSystemLibrary("SDL3_image", .{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
            .{ .name = "engine_lib", .module = mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "wgpu_zig_hello_triangle",
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
        .root_module = mod,
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
