#version 450
#extension GL_EXT_nonuniform_qualifier : require

layout(set = 0, binding = 1) uniform sampler2D textures[];

layout(location = 0) in vec2 frag_uv;
layout(location = 1) flat in int frag_tex_index;
layout(location = 0) out vec4 out_color;

void main() {
    vec4 c = texture(textures[nonuniformEXT(frag_tex_index)], frag_uv);
    if (c.a < 0.01) discard;
    out_color = c;
}
