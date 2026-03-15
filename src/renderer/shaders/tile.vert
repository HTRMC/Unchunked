#version 450

struct Vertex {
    float px, py;
    float u, v;
};

layout(set = 0, binding = 0) readonly buffer VertexBuffer {
    Vertex vertices[];
};

layout(push_constant) uniform PushConstants {
    mat4 view_proj;
};

layout(location = 0) out vec2 frag_uv;

void main() {
    Vertex v = vertices[gl_VertexIndex];
    gl_Position = view_proj * vec4(v.px, v.py, 0.0, 1.0);
    frag_uv = vec2(v.u, v.v);
}
