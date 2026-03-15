#version 450

struct Vertex {
    float px, py;
    float r, g, b, a;
};

layout(set = 0, binding = 0) readonly buffer VertexBuffer {
    Vertex vertices[];
};

layout(push_constant) uniform PushConstants {
    mat4 view_proj;
};

layout(location = 0) out vec4 frag_color;

void main() {
    Vertex v = vertices[gl_VertexIndex];
    gl_Position = view_proj * vec4(v.px, v.py, 0.0, 1.0);
    frag_color = vec4(v.r, v.g, v.b, v.a);
}
