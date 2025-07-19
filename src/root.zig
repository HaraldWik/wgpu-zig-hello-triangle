const std = @import("std");
const glfw = @import("zglfw");

const c = @cImport({
    @cInclude("GL/gl.h");
});

pub const gpu = @import("gpu.zig");
pub const Obj = @import("obj.zig");

pub const App = struct {
    const Self = @This();

    window: *glfw.Window,

    pub fn init(title: [:0]const u8, width: u32, height: u32) !Self {
        try glfw.init();

        glfw.windowHint(.client_api, .no_api);
        glfw.windowHint(.resizable, true);

        const window = try glfw.Window.create(@intCast(width), @intCast(height), title, null);

        // try glfw.setInputMode(window, .cursor, .disabled);

        return .{ .window = window };
    }

    pub fn deinit(self: Self) void {
        self.window.destroy();
        glfw.terminate();
    }

    pub fn update(self: Self) bool {
        if (glfw.windowShouldClose(self.window)) return true;
        glfw.pollEvents();

        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glClearColor(0.1, 0.4, 0.6, 1.0);
        glfw.swapBuffers(self.window);

        return false;
    }
};
