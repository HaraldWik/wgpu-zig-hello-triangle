const std = @import("std");
const c = @import("c");

pub const gpu = @import("gpu.zig");
pub const Obj = @import("Obj.zig");

pub const App = struct {
    const Self = @This();

    window: *c.GLFWwindow,

    pub fn init(title: [:0]const u8, width: u32, height: u32) !Self {
        if (c.glfwInit() != 0) return error.GlfwInit;

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);

        const window = c.glfwCreateWindow(@intCast(width), @intCast(height), title, null, null) orelse return error.GlfwCreateWindow;

        return .{ .window = window };
    }

    pub fn deinit(self: Self) void {
        c.glfwDestroyWindow(self.window);
        c.glfwTerminate();
    }

    pub fn update(self: Self) bool {
        if (c.glfwWindowShouldClose(self.window) == 1) return true;
        c.glfwPollEvents();

        // c.glClear(c.GL_COLOR_BUFFER_BIT);
        // c.glClearColor(0.1, 0.4, 0.6, 1.0);
        c.glfwSwapBuffers(self.window);

        return false;
    }
};
