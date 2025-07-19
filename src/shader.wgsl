struct VertexInput {
    @location(0) a_pos: vec3<f32>,
    @location(1) a_uv: vec2<f32>,
    @location(2) a_normal: vec3<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) out_normal: vec3<f32>,
    @location(1) out_uv: vec2<f32>,
};

struct Uniforms {
    u_projection: mat4x4<f32>,
    u_view: mat4x4<f32>,
    u_model: mat4x4<f32>,
};

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
// @group(0) @binding(1) var texture0: texture_2d<f32>;
// @group(0) @binding(2) var sampler0: sampler;

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;

    // Create normal matrix from upper-left 3x3 of model matrix
    let normal_matrix = transpose(inverse(mat3x3<f32>(
        uniforms.u_model[0].xyz,
        uniforms.u_model[1].xyz,
        uniforms.u_model[2].xyz
    )));

    output.out_normal = normalize(normal_matrix * input.a_normal);
    output.out_uv = input.a_uv;

    output.position = uniforms.u_projection * uniforms.u_view * uniforms.u_model * vec4<f32>(input.a_pos, 1.0);

    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let normal = normalize(input.out_normal);
    let light_dir = normalize(vec3<f32>(0.0, 1.0, 0.0));

    var brightness = max(dot(normal, light_dir), 0.0);
    brightness = max(brightness, 0.1);

    // let tex_color = textureSample(texture0, sampler0, input.out_uv);

    // return vec4<f32>(tex_color.rgb * brightness, tex_color.a);
    return vec4<f32>(brightness, tex_color.a);
}
