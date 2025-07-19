const std = @import("std");
const builtin = @import("builtin");
const App = @import("root.zig").App;
const glfw = @import("zglfw");
pub const wgpu = @import("wgpu");

pub const Context = struct {
    const Self = @This();

    instance: *wgpu.Instance,
    surface: *wgpu.Surface,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    config: wgpu.SurfaceConfiguration,

    pub fn init(app: App) !Self {
        const instance = wgpu.Instance.create(null) orelse return error.CreateInstance;

        const surface_descriptor: wgpu.SurfaceDescriptor = switch (builtin.os.tag) {
            .windows => wgpu.surfaceDescriptorFromWindowsHWND(wgpu.MergedSurfaceDescriptorFromWindowsHWND{
                .label = "win32_surface_descriptor",
                .hinstance = glfw.getWin32Window(app.window),
                .hwnd = glfw.getWin32Window(app.window),
            }),
            .linux, .freebsd, .openbsd, .dragonfly => blk: {
                const wayland_display = glfw.getWaylandDisplay();
                if (wayland_display != null) {
                    break :blk wgpu.surfaceDescriptorFromWaylandSurface(wgpu.MergedSurfaceDescriptorFromWaylandSurface{
                        .label = "wayland_surface_descriptor",
                        .display = @ptrCast(wayland_display),
                        .surface = @ptrCast(glfw.getWaylandWindow(app.window)),
                    });
                }

                const x11_display = glfw.getX11Display();
                if (x11_display != null) {
                    break :blk wgpu.surfaceDescriptorFromXlibWindow(wgpu.MergedSurfaceDescriptorFromXlibWindow{
                        .label = "x11_surface_descriptor",
                        .display = @ptrCast(x11_display),
                        .window = @intCast(glfw.getX11Window(app.window)),
                    });
                }

                @panic("No Wayland or X11 display found");
            },
            .macos => wgpu.surfaceDescriptorFromMetalLayer(wgpu.MergedSurfaceDescriptorFromMetalLayer{
                .label = "metal_surface_descriptor",
                .layer = glfw.getCocoaWindow(app.window),
            }),
            else => @panic("Unsupported platform for WebGPU-based context"),
        };

        const surface = instance.createSurface(&surface_descriptor) orelse return error.CreateSurface;

        const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{}, 0);
        const adapter: *wgpu.Adapter = switch (adapter_request.status) {
            .success => adapter_request.adapter.?,
            else => return error.NoAdapter,
        };

        const device_request = adapter.requestDeviceSync(instance, &wgpu.DeviceDescriptor{
            .required_limits = null,
        }, 0);
        const device: *wgpu.Device = switch (device_request.status) {
            .success => device_request.device.?,
            else => return error.NoDevice,
        };

        const queue = device.getQueue() orelse return error.GetQueue;

        const config = wgpu.SurfaceConfiguration{
            .device = device,
            .format = .rgba8_unorm_srgb,
            .width = @intCast(app.window.getSize()[0]),
            .height = @intCast(app.window.getSize()[1]),
            .present_mode = wgpu.PresentMode.fifo, // V-sync
            .alpha_mode = wgpu.CompositeAlphaMode.auto,
            .view_formats = &[_]wgpu.TextureFormat{},
        };

        surface.configure(&config);

        return .{
            .instance = instance,
            .surface = surface,
            .device = device,
            .queue = queue,
            .config = config,
        };
    }

    pub fn deinit(self: Self) void {
        self.queue.release();
        self.device.release();
        self.surface.release();
        self.instance.release();
    }
};

pub const RenderPass = struct {
    const Self = @This();

    context: Context,
    command_encoder: *wgpu.CommandEncoder,
    pass: *wgpu.RenderPassEncoder,

    pub const Config = struct {};

    pub fn acquire(context: Context, config: Config) !Self {
        _ = config;
        var swapchain: wgpu.SurfaceTexture = undefined;
        context.surface.getCurrentTexture(&swapchain);
        if (swapchain.texture == null) return error.AquireSwapchain;

        const view = swapchain.texture.?.createView(&wgpu.TextureViewDescriptor{
            .label = .fromSlice("frame view"),
            .dimension = .@"2d",
            .mip_level_count = 1,
            .array_layer_count = 1,
        }) orelse return error.SwapchainCreateView;
        defer view.release();

        const command_encoder = context.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = .fromSlice("frame encoder"),
        }) orelse return error.CreateCommandEncoder;

        const color_attachments = &[_]wgpu.ColorAttachment{
            wgpu.ColorAttachment{
                .view = view,
                .clear_value = wgpu.Color{ .r = 0.1, .g = 0.3, .b = 0.7, .a = 1.0 },
                .load_op = .clear,
                .store_op = .store,
            },
        };

        const pass = command_encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = color_attachments.len,
            .color_attachments = color_attachments.ptr,
        }) orelse return error.BeginRenderPass;

        return .{ .context = context, .command_encoder = command_encoder, .pass = pass };
    }

    pub fn setPipeline(self: Self, pipeline: Pipeline) void {
        self.pass.setPipeline(pipeline.handle);
    }

    pub fn draw(self: Self, model: Model) void {
        self.pass.setVertexBuffer(0, model.vertex_buffer, 0, model.vertex_buffer.getSize());
        self.pass.setIndexBuffer(model.index_buffer, .uint32, 0, model.index_buffer.getSize());

        self.pass.drawIndexed(@intCast(model.index_count), 1, 0, 0, 0);
    }

    pub fn submit(self: Self) !void {
        defer self.pass.release();
        defer self.command_encoder.release();

        self.pass.end();

        const command_buffer = self.command_encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = .fromSlice("frame command buffer"),
        }) orelse return error.CommandBufferFinishFailed;
        defer command_buffer.release();

        self.context.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});
        if (self.context.surface.present() != .success) return error.SwapchainPresent;
    }
};

pub const Pipeline = struct {
    const Self = @This();

    handle: *wgpu.RenderPipeline,
    shader_module: *wgpu.ShaderModule,

    pub fn init(context: Context, source: []const u8) !Pipeline {
        const shader_module = context.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .code = source,
        })) orelse return error.CreateShaderModule;

        const vertex_attributes = &[_]wgpu.VertexAttribute{
            wgpu.VertexAttribute{
                .format = .float32x3, // position: vec3<f32>
                .offset = 0,
                .shader_location = 0,
            },
            wgpu.VertexAttribute{
                .format = .float32x2, // uv: vec2<f32>
                .offset = 3 * @sizeOf(f32), // after position (12 bytes)
                .shader_location = 1,
            },
            wgpu.VertexAttribute{
                .format = .float32x3, // normal: vec3<f32>
                .offset = 5 * @sizeOf(f32), // after position + uv (20 bytes)
                .shader_location = 2,
            },
        };

        const vertex_buffer_layout = [_]wgpu.VertexBufferLayout{
            wgpu.VertexBufferLayout{
                .array_stride = 8 * @sizeOf(f32), // 8 floats per vertex (32 bytes)
                .step_mode = .vertex,
                .attribute_count = vertex_attributes.len,
                .attributes = vertex_attributes.ptr,
            },
        };

        const color_targets = &[_]wgpu.ColorTargetState{
            wgpu.ColorTargetState{
                .format = context.config.format,
                .blend = &wgpu.BlendState{
                    .color = wgpu.BlendComponent{
                        .operation = .add,
                        .src_factor = .src_alpha,
                        .dst_factor = .one_minus_src_alpha,
                    },
                    .alpha = wgpu.BlendComponent{
                        .operation = .add,
                        .src_factor = .zero,
                        .dst_factor = .one,
                    },
                },
                .write_mask = wgpu.ColorWriteMasks.all,
            },
        };

        const pipeline = context.device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
            .label = .fromSlice("pipeline"),
            .vertex = wgpu.VertexState{
                .module = shader_module,
                .entry_point = .fromSlice("vs_main"),
                .buffers = &vertex_buffer_layout,
                .buffer_count = vertex_buffer_layout.len,
            },
            .primitive = wgpu.PrimitiveState{
                .topology = .triangle_list,
                .strip_index_format = wgpu.IndexFormat.undefined,
                .front_face = wgpu.FrontFace.ccw,
                .cull_mode = wgpu.CullMode.none,
            },
            .fragment = &wgpu.FragmentState{
                .module = shader_module,
                .entry_point = .fromSlice("fs_main"),
                .target_count = color_targets.len,
                .targets = color_targets.ptr,
            },
            .multisample = wgpu.MultisampleState{
                .count = 1,
                .mask = 0xFFFFFFFF,
                .alpha_to_coverage_enabled = @intFromBool(false),
            },
            .depth_stencil = null,
        }) orelse return error.CreateRenderPipeline;

        return .{
            .shader_module = shader_module,
            .handle = pipeline,
        };
    }

    pub fn deinit(self: Self) void {
        self.handle.release();
        self.shader_module.release();
    }
};

pub const Model = struct {
    const Self = @This();

    vertex_buffer: *wgpu.Buffer,
    index_count: usize,
    index_buffer: *wgpu.Buffer,

    pub fn init(context: Context, vertices: []const f32, indices: []const u32) !Self {
        const vertex_buffer_size: u64 = @intCast(@sizeOf(f32) * vertices.len);
        const index_buffer_size: u64 = @intCast(@sizeOf(u32) * indices.len);

        const vertex_buffer = context.device.createBuffer(&wgpu.BufferDescriptor{
            .label = .fromSlice("vertex_buffer"),
            .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            .size = vertex_buffer_size,
            .mapped_at_creation = 1,
        }) orelse return error.CreateVertexBuffer;

        const vb_ptr: [*]u8 = @ptrCast(vertex_buffer.getMappedRange(0, vertex_buffer_size) orelse return error.MapVertexBuffer);
        @memcpy(vb_ptr[0..], std.mem.sliceAsBytes(vertices));
        vertex_buffer.unmap();

        const index_buffer = context.device.createBuffer(&wgpu.BufferDescriptor{
            .label = .fromSlice("index_buffer"),
            .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
            .size = index_buffer_size,
            .mapped_at_creation = 1,
        }) orelse return error.CreateIndexBuffer;

        const ib_ptr: [*]u8 = @ptrCast(index_buffer.getMappedRange(0, index_buffer_size) orelse return error.MapIndexBuffer);
        @memcpy(ib_ptr[0..], std.mem.sliceAsBytes(indices));
        index_buffer.unmap();

        return .{ .vertex_buffer = vertex_buffer, .index_count = indices.len, .index_buffer = index_buffer };
    }

    pub fn deinit(self: Self) void {
        self.vertex_buffer.release();
        self.index_buffer.release();
    }
};

const c = @cImport({
    @cInclude("SDL3_image/SDL_image.h");
});

pub const Texture = struct {
    const Self = @This();

    texture: *wgpu.Texture,
    view: *wgpu.TextureView,
    sampler: *wgpu.Sampler,

    pub fn init(context: Context, path: [:0]const u8) !Self {
        const image: *c.SDL_Surface = @ptrCast(c.IMG_Load(path) orelse return error.ImageLoad);

        const width: u32 = @intCast(image.w);
        const height: u32 = @intCast(image.h);
        const pixel_data: [*]u8 = @ptrCast(image.pixels);

        const size = width * height * 4;

        const staging_buffer = context.device.createBuffer(&wgpu.BufferDescriptor{
            .label = .fromSlice("staging buffer"),
            .usage = wgpu.BufferUsages.copy_src,
            .size = size,
            .mapped_at_creation = 1,
        }) orelse return error.CreateStagingBuffer;

        {
            const dest: [*]u8 = @ptrCast(staging_buffer.getMappedRange(0, size).?);
            @memcpy(dest[0..size], pixel_data[0..size]);
            staging_buffer.unmap();
        }

        const texture = context.device.createTexture(&wgpu.TextureDescriptor{
            .label = .fromSlice("my texture"),
            .size = wgpu.Extent3D{ .width = width, .height = height, .depth_or_array_layers = 1 },
            .mip_level_count = 1,
            .sample_count = 1,
            .dimension = .@"2d",
            .format = .rgba8_unorm_srgb,
            .usage = wgpu.TextureUsages.texture_binding | wgpu.TextureUsages.copy_dst,
        }) orelse return error.CreateTexture;

        const texture_view = texture.createView(&wgpu.TextureViewDescriptor{
            .label = .fromSlice("texture view"),
            .format = .rgba8_unorm_srgb,
            .dimension = .@"2d",
            .mip_level_count = 1,
            .array_layer_count = 1,
        }) orelse return error.CreateTextureView;

        const sampler = context.device.createSampler(&wgpu.SamplerDescriptor{
            .label = .fromSlice("texture sampler"),
            .min_filter = .linear,
            .mag_filter = .linear,
            .mipmap_filter = .nearest,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
        }) orelse return error.CreateSampler;

        const encoder = context.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = .fromSlice("texture copy encoder"),
        }) orelse return error.CreateCommandEncoder;
        defer encoder.release();

        const texture_copy = wgpu.TexelCopyTextureInfo{
            .texture = texture,
            .mip_level = 0,
            .origin = .{},
            .aspect = .all,
        };

        const buffer_copy = wgpu.TexelCopyBufferInfo{
            .buffer = staging_buffer,
            .layout = wgpu.TexelCopyBufferLayout{
                .bytes_per_row = width * 4,
                .rows_per_image = height,
            },
        };

        encoder.copyBufferToTexture(&buffer_copy, &texture_copy, &wgpu.Extent3D{
            .width = width,
            .height = height,
            .depth_or_array_layers = 1,
        });

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = .fromSlice("texture upload command buffer"),
        }) orelse return error.CommandBufferFinish;

        context.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});

        return .{
            .texture = texture,
            .view = texture_view,
            .sampler = sampler,
        };
    }

    pub fn deinit(self: Self) void {
        self.view.release();
        self.texture.release();
        self.sampler.release();
    }
};
