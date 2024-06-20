const std = @import("std");
const vk = @import("vulkan");

const Color = @import("../Color.zig");
const Mesh = @import("Mesh.zig");
const Image = @import("../Image.zig");
const PreparedImage = @import("PreparedImage.zig");

const material = @import("material.zig");
const math = @import("../math.zig");
const asset = @import("../asset.zig");

const StandardMaterial = @This();

color: Color = Color.WHITE,
color_texture: ?asset.AssetId(Image) = null,

metallic: f32 = 0.01,
roughness: f32 = 0.089,
reflectance: f32 = 0.5,

roughness_texture: ?asset.AssetId(Image) = null,

normal_map: ?asset.AssetId(Image) = null,

emissive: Color = Color.BLACK,
emissive_strength: f32 = 1.0,

clearcoat: f32 = 0.0,
clearcoat_roughness: f32 = 0.0,

thickness: f32 = 1.0,

transmission: f32 = 0.0,
index_of_refraction: f32 = 1.5,
absorption: Color = Color.BLACK,

subsurface: f32 = 0.0,
subsurface_color: Color = Color.WHITE,

pub fn vertexShader() vk.Spirv {
    return vk.embedSpirv(@embedFile("shaders/standard_material.vert"));
}

pub fn fragmentShader() vk.Spirv {
    return vk.embedSpirv(@embedFile("shaders/standard_material.frag"));
}

pub fn vertexAttributes() []const material.VertexAttribute {
    return &.{
        .{ .name = Mesh.POSITION, .format = .f32x3 },
        .{ .name = Mesh.NORMAL, .format = .f32x3 },
        .{ .name = Mesh.TANGENT, .format = .f32x4 },
        .{ .name = Mesh.TEX_COORD_0, .format = .f32x2 },
    };
}

pub fn bindGroupLayoutEntries() []const vk.BindGroupLayout.Entry {
    return &.{
        .{
            .binding = 0,
            .type = .UniformBuffer,
            .stages = .{ .fragment = true },
        },
        .{
            .binding = 1,
            .type = .CombinedImageSampler,
            .stages = .{ .fragment = true },
        },
        .{
            .binding = 2,
            .type = .CombinedImageSampler,
            .stages = .{ .fragment = true },
        },
        .{
            .binding = 3,
            .type = .CombinedImageSampler,
            .stages = .{ .fragment = true },
        },
    };
}

pub fn readsTransmissionImage(self: StandardMaterial) bool {
    return self.transmission > 0.0;
}

pub const Uniforms = extern struct {
    color: [4]f32,
    metallic: f32,
    roughness: f32,
    reflectance: f32,

    _padding0: [4]u8 = undefined,

    emissive: [4]f32,

    clearcoat: f32,
    clearcoat_roughness: f32,

    thickness: f32,
    transmission: f32,

    absorption: [4]f32,
    subsurface_color: [4]f32,

    index_of_refraction: f32,
    subsurface: f32,
};

pub const State = struct {
    uniform_buffer: vk.Buffer,
};

pub fn initState(
    device: vk.Device,
    bind_group: vk.BindGroup,
) !State {
    _ = bind_group;

    const uniform_buffer = try device.createBuffer(.{
        .size = @sizeOf(Uniforms),
        .usage = .{ .uniform_buffer = true, .transfer_dst = true },
        .memory = .{ .device_local = true },
    });

    return State{
        .uniform_buffer = uniform_buffer,
    };
}

pub fn deinitState(state: *State) void {
    state.uniform_buffer.deinit();
}

pub fn update(
    self: StandardMaterial,
    state: *State,
    bind_group: vk.BindGroup,
    cx: material.Context,
) !void {
    const uniforms = Uniforms{
        .color = self.color.asArray(),
        .metallic = self.metallic,
        .roughness = self.roughness,
        .reflectance = self.reflectance,

        .emissive = self.emissive.mul(self.emissive_strength).asArray(),

        .clearcoat = self.clearcoat,
        .clearcoat_roughness = self.clearcoat_roughness,

        .thickness = self.thickness,
        .transmission = self.transmission,

        .absorption = self.absorption.asArray(),
        .subsurface_color = self.subsurface_color.asArray(),

        .index_of_refraction = self.index_of_refraction,
        .subsurface = self.subsurface,
    };

    try cx.staging_buffer.write(&uniforms);
    try cx.staging_buffer.copyBuffer(.{
        .dst = state.uniform_buffer,
        .size = @sizeOf(Uniforms),
    });

    const color = cx.get_image(self.color_texture);
    const roughness = cx.get_image(self.roughness_texture);
    const normal = cx.get_normal_map(self.normal_map);

    cx.device.updateBindGroups(.{
        .writes = &.{
            .{
                .dst = bind_group,
                .binding = 0,
                .resource = .{ .buffer = .{
                    .buffer = state.uniform_buffer,
                    .size = @sizeOf(Uniforms),
                } },
            },
            .{
                .dst = bind_group,
                .binding = 1,
                .resource = .{ .combined_image = .{
                    .sampler = color.sampler,
                    .view = color.view,
                    .layout = .ShaderReadOnlyOptimal,
                } },
            },
            .{
                .dst = bind_group,
                .binding = 2,
                .resource = .{ .combined_image = .{
                    .sampler = roughness.sampler,
                    .view = roughness.view,
                    .layout = .ShaderReadOnlyOptimal,
                } },
            },
            .{
                .dst = bind_group,
                .binding = 3,
                .resource = .{ .combined_image = .{
                    .sampler = normal.sampler,
                    .view = normal.view,
                    .layout = .ShaderReadOnlyOptimal,
                } },
            },
        },
    });
}
