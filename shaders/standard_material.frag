#version 450

#include "pbr.glsl"
#include "camera.glsl"

layout(location = 0) in vec3 v_position;
layout(location = 1) in vec3 v_normal;
layout(location = 2) in vec3 v_tangent;
layout(location = 3) in vec3 v_bitangent;
layout(location = 4) in vec2 v_tex_coord;

layout(location = 0) out vec4 o_color;

layout(set = 0, binding = 0) uniform StandardMaterial {
    vec4 base_color;
    float metallic;
    float roughness;
    float reflectance;

    vec4 emissive;

    float clearcoat;
    float clearcoat_roughness;

    float thickness;
    float transmission;

    vec4 absorption;
    vec4 subsurface_color;

    float index_of_refraction;
    float subsurface_power;
} standard_material;

layout(set = 0, binding = 1) uniform sampler2D base_color_map;
layout(set = 0, binding = 2) uniform sampler2D roughness_map;
layout(set = 0, binding = 3) uniform sampler2D normal_map;

void main() {
    PbrMaterial material = default_pbr_material(
        gl_FragCoord,
        v_position,
        v_normal,
        camera.eye - v_position
    );

    vec4 base_color = texture(base_color_map, v_tex_coord);
    vec4 roughness = texture(roughness_map, v_tex_coord);

    material.albedo = standard_material.base_color.rgb * base_color.rgb;
    material.metallic = standard_material.metallic;
    material.roughness = standard_material.roughness * roughness.r;
    material.reflectance = standard_material.reflectance;

    material.emissive = standard_material.emissive.rgb;

    material.clearcoat = standard_material.clearcoat;
    material.clearcoat_roughness = standard_material.clearcoat_roughness;

    material.thickness = standard_material.thickness;

    material.transmission = standard_material.transmission;
    material.index_of_refraction = standard_material.index_of_refraction;
    material.absorption = standard_material.absorption.rgb;

    material.subsurface_color = standard_material.subsurface_color.rgb;
    material.subsurface_power = standard_material.subsurface_power;

    vec3 normal = texture(normal_map, v_tex_coord).xyz * 2.0 - 1.0;
    mat3 tbn = mat3(v_tangent, v_bitangent, v_normal);
    material.normal = normalize(tbn * normal);

    PbrPixel pixel = compute_pbr_pixel(material);

    DirectionalLight light;
    light.direction = normalize(vec3(1.0, -1.0, -1.0));
    light.color = vec3(1.0, 1.0, 1.0);
    light.intensity = 5.0;
    
    vec3 color = pbr_light_directional(pixel, light);
    color += pbr_refraction(pixel, vec3(0.5));
    color += material.emissive;

    vec3 sky_diffuse = max(dot(pixel.normal, vec3(0.0, 1.0, 0.0)), 0.4) * vec3(0.8, 0.9, 1.0);
    color += pixel.albedo * sky_diffuse * 0.8;

    vec3 bounce_diffuse = max(dot(pixel.normal, vec3(0.0, -1.0, 0.0)), 0.0) * vec3(1.0, 0.7, 0.6);
    color += pixel.albedo * bounce_diffuse * 0.1;

    o_color = vec4(color, 1.0);
}
