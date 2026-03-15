#version 450

struct Vertex {
    float px, py;
    float u, v;
    float r, g, b, a;
};

layout(set = 0, binding = 0) readonly buffer VertexBuffer {
    Vertex vertices[];
};

layout(push_constant) uniform PushConstants {
    mat4 projection;
};

layout(location = 0) out vec2 frag_uv;
layout(location = 1) out vec4 frag_color;

void main() {
    Vertex v = vertices[gl_VertexIndex];
    gl_Position = projection * vec4(v.px, v.py, 0.0, 1.0);
    frag_uv = vec2(v.u, v.v);
    frag_color = vec4(v.r, v.g, v.b, v.a);
}
