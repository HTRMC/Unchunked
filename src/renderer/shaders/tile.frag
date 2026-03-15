#version 450

layout(set = 0, binding = 1) uniform sampler2D tile_atlas;

layout(location = 0) in vec2 frag_uv;
layout(location = 0) out vec4 out_color;

void main() {
    vec4 c = texture(tile_atlas, frag_uv);
    if (c.a < 0.01) discard;
    out_color = c;
}
