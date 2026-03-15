const std = @import("std");
const vk = @import("../platform/volk.zig");
const shaderc = @import("../platform/shaderc.zig");
const Renderer = @import("Renderer.zig");

const QuadRenderer = @This();

const MAX_QUADS = 16384;
const VERTICES_PER_QUAD = 6;
const MAX_VERTICES = MAX_QUADS * VERTICES_PER_QUAD;

pub const MapVertex = extern struct {
    px: f32,
    py: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1.0,
};

const VERTEX_SIZE = @sizeOf(MapVertex);
const BUFFER_SIZE = MAX_VERTICES * VERTEX_SIZE * Renderer.MAX_FRAMES_IN_FLIGHT;

pipeline: vk.VkPipeline = null,
pipeline_layout: vk.VkPipelineLayout = null,
descriptor_set_layout: vk.VkDescriptorSetLayout = null,
descriptor_pool: vk.VkDescriptorPool = null,
descriptor_sets: [Renderer.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet = .{null} ** Renderer.MAX_FRAMES_IN_FLIGHT,
vertex_buffer: vk.VkBuffer = null,
vertex_memory: vk.VkDeviceMemory = null,
mapped_data: ?*anyopaque = null,
vertex_count: u32 = 0,
vertex_offset: u32 = 0, // offset into SSBO for current batch
device: vk.VkDevice = null,
swapchain_format: vk.VkFormat = vk.VK_FORMAT_B8G8R8A8_SRGB,

pub fn init(renderer: *Renderer) !QuadRenderer {
    var self = QuadRenderer{};
    self.device = renderer.device;
    self.swapchain_format = renderer.swapchain_format;

    try self.createVertexBuffer(renderer);
    try self.createDescriptors(renderer);
    try self.createPipeline(renderer);

    return self;
}

pub fn deinit(self: *QuadRenderer) void {
    if (self.descriptor_pool != null) vk.destroyDescriptorPool(self.device, self.descriptor_pool, null);
    if (self.descriptor_set_layout != null) vk.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
    if (self.pipeline != null) vk.destroyPipeline(self.device, self.pipeline, null);
    if (self.pipeline_layout != null) vk.destroyPipelineLayout(self.device, self.pipeline_layout, null);
    if (self.vertex_buffer != null) vk.destroyBuffer(self.device, self.vertex_buffer, null);
    if (self.vertex_memory != null) vk.freeMemory(self.device, self.vertex_memory, null);
}

pub fn resetFrame(self: *QuadRenderer, frame_index: u32) void {
    self.vertex_offset = frame_index * MAX_VERTICES;
    self.vertex_count = 0;
}

pub fn beginFrame(self: *QuadRenderer) void {
    self.vertex_count = 0;
}

pub fn drawQuad(self: *QuadRenderer, x: f32, y: f32, w: f32, h: f32, color: Color) void {
    if (self.vertex_count + VERTICES_PER_QUAD > MAX_VERTICES) return;

    const base: [*]MapVertex = @ptrCast(@alignCast(self.mapped_data orelse return));
    const verts = base[self.vertex_offset + self.vertex_count ..][0..6];

    // Two triangles forming a quad
    verts[0] = .{ .px = x, .py = y, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    verts[1] = .{ .px = x + w, .py = y, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    verts[2] = .{ .px = x, .py = y + h, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    verts[3] = .{ .px = x + w, .py = y, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    verts[4] = .{ .px = x + w, .py = y + h, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    verts[5] = .{ .px = x, .py = y + h, .r = color.r, .g = color.g, .b = color.b, .a = color.a };

    self.vertex_count += VERTICES_PER_QUAD;
}

pub fn flush(self: *QuadRenderer, cmd: vk.VkCommandBuffer, view_proj: *const [16]f32, frame_index: u32) void {
    if (self.vertex_count == 0) return;

    vk.cmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);

    vk.cmdBindDescriptorSets(
        cmd,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        self.pipeline_layout,
        0,
        1,
        @ptrCast(&self.descriptor_sets[frame_index]),
        0,
        null,
    );

    vk.cmdPushConstants(
        cmd,
        self.pipeline_layout,
        vk.VK_SHADER_STAGE_VERTEX_BIT,
        0,
        64,
        view_proj,
    );

    vk.cmdDraw(cmd, self.vertex_count, 1, self.vertex_offset, 0);

    // Advance offset so next batch doesn't overwrite this one
    self.vertex_offset += self.vertex_count;
    self.vertex_count = 0;
}

fn createVertexBuffer(self: *QuadRenderer, renderer: *Renderer) !void {
    const buffer_info: vk.VkBufferCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .size = BUFFER_SIZE,
        .usage = vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
    };

    self.vertex_buffer = try vk.createBuffer(self.device, &buffer_info, null);

    var mem_requirements: vk.VkMemoryRequirements = undefined;
    vk.getBufferMemoryRequirements(self.device, self.vertex_buffer, &mem_requirements);

    var mem_properties: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.getPhysicalDeviceMemoryProperties(renderer.physical_device, &mem_properties);

    const mem_type_index = findMemoryType(
        mem_properties,
        mem_requirements.memoryTypeBits,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    ) orelse return error.NoSuitableDevice;

    const alloc_info: vk.VkMemoryAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = mem_type_index,
    };

    self.vertex_memory = try vk.allocateMemory(self.device, &alloc_info, null);
    try vk.bindBufferMemory(self.device, self.vertex_buffer, self.vertex_memory, 0);

    try vk.mapMemory(self.device, self.vertex_memory, 0, vk.VK_WHOLE_SIZE, 0, &self.mapped_data);
}

fn createDescriptors(self: *QuadRenderer, renderer: *Renderer) !void {
    _ = renderer;

    const binding: vk.VkDescriptorSetLayoutBinding = .{
        .binding = 0,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 1,
        .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        .pImmutableSamplers = null,
    };

    const layout_info: vk.VkDescriptorSetLayoutCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .bindingCount = 1,
        .pBindings = @ptrCast(&binding),
    };

    self.descriptor_set_layout = try vk.createDescriptorSetLayout(self.device, &layout_info, null);

    const pool_size: vk.VkDescriptorPoolSize = .{
        .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = Renderer.MAX_FRAMES_IN_FLIGHT,
    };

    const pool_info: vk.VkDescriptorPoolCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .maxSets = Renderer.MAX_FRAMES_IN_FLIGHT,
        .poolSizeCount = 1,
        .pPoolSizes = @ptrCast(&pool_size),
    };

    self.descriptor_pool = try vk.createDescriptorPool(self.device, &pool_info, null);

    var layouts: [Renderer.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSetLayout = undefined;
    for (&layouts) |*l| l.* = self.descriptor_set_layout;

    const alloc_info: vk.VkDescriptorSetAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = self.descriptor_pool,
        .descriptorSetCount = Renderer.MAX_FRAMES_IN_FLIGHT,
        .pSetLayouts = &layouts,
    };

    try vk.allocateDescriptorSets(self.device, &alloc_info, &self.descriptor_sets);

    // Update all descriptor sets to point to the same vertex buffer
    for (0..Renderer.MAX_FRAMES_IN_FLIGHT) |i| {
        const buffer_desc: vk.VkDescriptorBufferInfo = .{
            .buffer = self.vertex_buffer,
            .offset = 0,
            .range = vk.VK_WHOLE_SIZE,
        };

        const write: vk.VkWriteDescriptorSet = .{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = self.descriptor_sets[i],
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pImageInfo = null,
            .pBufferInfo = @ptrCast(&buffer_desc),
            .pTexelBufferView = null,
        };

        vk.updateDescriptorSets(self.device, 1, @ptrCast(&write), 0, null);
    }
}

fn createPipeline(self: *QuadRenderer, renderer: *Renderer) !void {
    _ = renderer;

    // Compile shaders at startup
    const vert_source = @embedFile("shaders/quad.vert");
    const frag_source = @embedFile("shaders/quad.frag");

    const compiler = shaderc.compiler_initialize();
    if (compiler == null) return error.InitializationFailed;
    defer shaderc.compiler_release(compiler);

    const vert_result = shaderc.compile_into_spv(
        compiler,
        @ptrCast(vert_source.ptr),
        vert_source.len,
        shaderc.shaderc_vertex_shader,
        "quad.vert",
        "main",
        null,
    );
    defer shaderc.result_release(vert_result);

    if (shaderc.result_get_compilation_status(vert_result) != shaderc.shaderc_compilation_status_success) {
        const err_msg = shaderc.result_get_error_message(vert_result);
        std.log.err("Vertex shader compilation failed: {s}", .{err_msg});
        return error.InitializationFailed;
    }

    const frag_result = shaderc.compile_into_spv(
        compiler,
        @ptrCast(frag_source.ptr),
        frag_source.len,
        shaderc.shaderc_fragment_shader,
        "quad.frag",
        "main",
        null,
    );
    defer shaderc.result_release(frag_result);

    if (shaderc.result_get_compilation_status(frag_result) != shaderc.shaderc_compilation_status_success) {
        const err_msg = shaderc.result_get_error_message(frag_result);
        std.log.err("Fragment shader compilation failed: {s}", .{err_msg});
        return error.InitializationFailed;
    }

    // Create shader modules
    const vert_module_info: vk.VkShaderModuleCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = shaderc.result_get_length(vert_result),
        .pCode = @ptrCast(@alignCast(shaderc.result_get_bytes(vert_result))),
    };
    const vert_module = try vk.createShaderModule(self.device, &vert_module_info, null);
    defer vk.destroyShaderModule(self.device, vert_module, null);

    const frag_module_info: vk.VkShaderModuleCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = shaderc.result_get_length(frag_result),
        .pCode = @ptrCast(@alignCast(shaderc.result_get_bytes(frag_result))),
    };
    const frag_module = try vk.createShaderModule(self.device, &frag_module_info, null);
    defer vk.destroyShaderModule(self.device, frag_module, null);

    const shader_stages = [2]vk.VkPipelineShaderStageCreateInfo{
        .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
        .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_module,
            .pName = "main",
            .pSpecializationInfo = null,
        },
    };

    const vertex_input: vk.VkPipelineVertexInputStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    const input_assembly: vk.VkPipelineInputAssemblyStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = vk.VK_FALSE,
    };

    const viewport_state: vk.VkPipelineViewportStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    const rasterizer: vk.VkPipelineRasterizationStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = vk.VK_FALSE,
        .rasterizerDiscardEnable = vk.VK_FALSE,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .cullMode = vk.VK_CULL_MODE_NONE,
        .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .depthBiasEnable = vk.VK_FALSE,
        .depthBiasConstantFactor = 0,
        .depthBiasClamp = 0,
        .depthBiasSlopeFactor = 0,
        .lineWidth = 1.0,
    };

    const multisampling: vk.VkPipelineMultisampleStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = vk.VK_FALSE,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = vk.VK_FALSE,
        .alphaToOneEnable = vk.VK_FALSE,
    };

    const color_blend_attachment: vk.VkPipelineColorBlendAttachmentState = .{
        .blendEnable = vk.VK_TRUE,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT |
            vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
    };

    const color_blending: vk.VkPipelineColorBlendStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = vk.VK_FALSE,
        .logicOp = 0,
        .attachmentCount = 1,
        .pAttachments = @ptrCast(&color_blend_attachment),
        .blendConstants = .{ 0, 0, 0, 0 },
    };

    const dynamic_states = [_]vk.VkDynamicState{
        vk.VK_DYNAMIC_STATE_VIEWPORT,
        vk.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynamic_state: vk.VkPipelineDynamicStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = &dynamic_states,
    };

    // Push constant for view_proj mat4
    const push_constant_range: vk.VkPushConstantRange = .{
        .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 0,
        .size = 64,
    };

    const layout_info: vk.VkPipelineLayoutCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = 1,
        .pSetLayouts = @ptrCast(&self.descriptor_set_layout),
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = @ptrCast(&push_constant_range),
    };

    self.pipeline_layout = try vk.createPipelineLayout(self.device, &layout_info, null);

    // Dynamic rendering info (no VkRenderPass)
    const rendering_create_info: vk.VkPipelineRenderingCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .pNext = null,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = @ptrCast(&self.swapchain_format),
        .depthAttachmentFormat = 0,
        .stencilAttachmentFormat = 0,
    };

    const pipeline_info: vk.VkGraphicsPipelineCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &rendering_create_info,
        .flags = 0,
        .stageCount = 2,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &input_assembly,
        .pTessellationState = null,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,
        .layout = self.pipeline_layout,
        .renderPass = null,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    try vk.createGraphicsPipelines(self.device, null, 1, @ptrCast(&pipeline_info), null, @ptrCast(&self.pipeline));

    std.log.info("QuadRenderer pipeline created", .{});
}

fn findMemoryType(
    mem_properties: vk.VkPhysicalDeviceMemoryProperties,
    type_filter: u32,
    properties: u32,
) ?u32 {
    for (0..mem_properties.memoryTypeCount) |i| {
        const idx: u5 = @intCast(i);
        if ((type_filter & (@as(u32, 1) << idx)) != 0 and
            (mem_properties.memoryTypes[i].propertyFlags & properties) == properties)
        {
            return @intCast(i);
        }
    }
    return null;
}
