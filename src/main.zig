const std = @import("std");
const eng = @import("engine_lib");
const gpu = @import("engine_lib").gpu;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const app = try eng.App.init("title: [:0]const u8", 800, 640);
    defer app.deinit();

    var context = try gpu.Context.init(app);
    defer context.deinit();

    const pipeline = try gpu.Pipeline.init(context, @embedFile("shader.wgsl"));
    defer pipeline.deinit();

    const obj = try eng.Obj.init(allocator, "assets/models/basket.obj");
    defer obj.deinit(allocator);

    const model = try eng.gpu.Model.init(context, obj.vertices, obj.indices);
    defer model.deinit();

    const texture = try eng.gpu.Texture.init(context, "assets/textures/basket_diff.jpg");
    defer texture.deinit();

    while (!app.update()) {
        const pass = try gpu.RenderPass.acquire(context, .{});

        pass.setPipeline(pipeline);
        pass.draw(model);

        try pass.submit();
    }
}
