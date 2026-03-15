const std = @import("std");
const vk = @import("../platform/volk.zig");
const shaderc = @import("../platform/shaderc.zig");
const Renderer = @import("Renderer.zig");
const font = @import("font.zig");

const TextRenderer = @This();

const MAX_CHARS = 4096;
const VERTICES_PER_CHAR = 6;
const MAX_VERTICES = MAX_CHARS * VERTICES_PER_CHAR;

pub const TextVertex = extern struct {
    px: f32,
    py: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const Color = struct {
    r: f32 = 1.0,
    g: f32 = 1.0,
    b: f32 = 1.0,
    a: f32 = 1.0,
};

const VERTEX_SIZE = @sizeOf(TextVertex);
const BUFFER_SIZE = MAX_VERTICES * VERTEX_SIZE;

pipeline: vk.VkPipeline = null,
pipeline_layout: vk.VkPipelineLayout = null,
descriptor_set_layout: vk.VkDescriptorSetLayout = null,
descriptor_pool: vk.VkDescriptorPool = null,
descriptor_sets: [Renderer.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet = .{null} ** Renderer.MAX_FRAMES_IN_FLIGHT,

vertex_buffer: vk.VkBuffer = null,
vertex_memory: vk.VkDeviceMemory = null,
mapped_data: ?*anyopaque = null,
vertex_count: u32 = 0,

font_image: vk.VkImage = null,
font_image_view: vk.VkImageView = null,
font_memory: vk.VkDeviceMemory = null,
font_sampler: vk.VkSampler = null,

device: vk.VkDevice = null,
swapchain_format: vk.VkFormat = vk.VK_FORMAT_B8G8R8A8_SRGB,

pub fn init(renderer: *Renderer) !TextRenderer {
    var self = TextRenderer{};
    self.device = renderer.device;
    self.swapchain_format = renderer.swapchain_format;

    try self.createFontTexture(renderer);
    try self.createVertexBuffer(renderer);
    try self.createDescriptors();
    try self.createPipeline();

    return self;
}

pub fn deinit(self: *TextRenderer) void {
    if (self.descriptor_pool != null) vk.destroyDescriptorPool(self.device, self.descriptor_pool, null);
    if (self.descriptor_set_layout != null) vk.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
    if (self.pipeline != null) vk.destroyPipeline(self.device, self.pipeline, null);
    if (self.pipeline_layout != null) vk.destroyPipelineLayout(self.device, self.pipeline_layout, null);
    if (self.vertex_buffer != null) vk.destroyBuffer(self.device, self.vertex_buffer, null);
    if (self.vertex_memory != null) vk.freeMemory(self.device, self.vertex_memory, null);
    if (self.font_sampler != null) vk.destroySampler(self.device, self.font_sampler, null);
    if (self.font_image_view != null) vk.destroyImageView(self.device, self.font_image_view, null);
    if (self.font_image != null) vk.destroyImage(self.device, self.font_image, null);
    if (self.font_memory != null) vk.freeMemory(self.device, self.font_memory, null);
}

pub fn beginFrame(self: *TextRenderer) void {
    self.vertex_count = 0;
}

pub fn drawText(self: *TextRenderer, text: []const u8, x: f32, y: f32, scale: f32, color: Color) void {
    var cursor_x = x;
    const char_w = @as(f32, font.GLYPH_WIDTH) * scale;
    const char_h = @as(f32, font.GLYPH_HEIGHT) * scale;

    for (text) |ch| {
        if (self.vertex_count + VERTICES_PER_CHAR > MAX_VERTICES) return;

        const col: f32 = @floatFromInt(ch % font.ATLAS_COLS);
        const row: f32 = @floatFromInt(ch / font.ATLAS_COLS);

        const tex_u0 = col / @as(f32, font.ATLAS_COLS);
        const tex_v0 = row / @as(f32, font.ATLAS_ROWS);
        const tex_u1 = (col + 1.0) / @as(f32, font.ATLAS_COLS);
        const tex_v1 = (row + 1.0) / @as(f32, font.ATLAS_ROWS);

        const base: [*]TextVertex = @ptrCast(@alignCast(self.mapped_data orelse return));
        const verts = base[self.vertex_count..][0..6];

        verts[0] = .{ .px = cursor_x, .py = y, .u = tex_u0, .v = tex_v0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[1] = .{ .px = cursor_x + char_w, .py = y, .u = tex_u1, .v = tex_v0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[2] = .{ .px = cursor_x, .py = y + char_h, .u = tex_u0, .v = tex_v1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[3] = .{ .px = cursor_x + char_w, .py = y, .u = tex_u1, .v = tex_v0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[4] = .{ .px = cursor_x + char_w, .py = y + char_h, .u = tex_u1, .v = tex_v1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        verts[5] = .{ .px = cursor_x, .py = y + char_h, .u = tex_u0, .v = tex_v1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };

        self.vertex_count += VERTICES_PER_CHAR;
        cursor_x += char_w;
    }
}

pub fn drawFmt(self: *TextRenderer, x: f32, y: f32, scale: f32, color: Color, comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
    self.drawText(text, x, y, scale, color);
}

pub fn flush(self: *TextRenderer, cmd: vk.VkCommandBuffer, screen_proj: *const [16]f32, frame_index: u32) void {
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
        screen_proj,
    );

    vk.cmdDraw(cmd, self.vertex_count, 1, 0, 0);
}

pub fn textWidth(text: []const u8, scale: f32) f32 {
    return @as(f32, @floatFromInt(text.len)) * @as(f32, font.GLYPH_WIDTH) * scale;
}

fn createFontTexture(self: *TextRenderer, renderer: *Renderer) !void {
    const atlas_data = font.generateAtlas();
    const atlas_size: u64 = font.ATLAS_WIDTH * font.ATLAS_HEIGHT;

    // Create staging buffer
    const staging_buffer_info: vk.VkBufferCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .size = atlas_size,
        .usage = vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
    };

    const staging_buffer = try vk.createBuffer(self.device, &staging_buffer_info, null);
    defer vk.destroyBuffer(self.device, staging_buffer, null);

    var staging_mem_req: vk.VkMemoryRequirements = undefined;
    vk.getBufferMemoryRequirements(self.device, staging_buffer, &staging_mem_req);

    var mem_properties: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.getPhysicalDeviceMemoryProperties(renderer.physical_device, &mem_properties);

    const staging_mem_type = findMemoryType(mem_properties, staging_mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.NoSuitableDevice;

    const staging_alloc: vk.VkMemoryAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = staging_mem_req.size,
        .memoryTypeIndex = staging_mem_type,
    };

    const staging_memory = try vk.allocateMemory(self.device, &staging_alloc, null);
    defer vk.freeMemory(self.device, staging_memory, null);

    try vk.bindBufferMemory(self.device, staging_buffer, staging_memory, 0);

    // Copy atlas data to staging buffer
    var staging_mapped: ?*anyopaque = null;
    try vk.mapMemory(self.device, staging_memory, 0, atlas_size, 0, &staging_mapped);
    const dst: [*]u8 = @ptrCast(staging_mapped orelse return error.MemoryMapFailed);
    @memcpy(dst[0..atlas_size], &atlas_data);

    // Create font image
    const image_info: vk.VkImageCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = vk.VK_FORMAT_R8_UNORM,
        .extent = .{ .width = font.ATLAS_WIDTH, .height = font.ATLAS_HEIGHT, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
        .usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    };

    self.font_image = try vk.createImage(self.device, &image_info, null);

    var img_mem_req: vk.VkMemoryRequirements = undefined;
    vk.getImageMemoryRequirements(self.device, self.font_image, &img_mem_req);

    const img_mem_type = findMemoryType(mem_properties, img_mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.NoSuitableDevice;

    const img_alloc: vk.VkMemoryAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = img_mem_req.size,
        .memoryTypeIndex = img_mem_type,
    };

    self.font_memory = try vk.allocateMemory(self.device, &img_alloc, null);
    try vk.bindImageMemory(self.device, self.font_image, self.font_memory, 0);

    // Upload via one-shot command buffer
    try self.uploadTexture(renderer, staging_buffer);

    // Create image view
    const view_info: vk.VkImageViewCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = self.font_image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .format = vk.VK_FORMAT_R8_UNORM,
        .components = .{
            .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    self.font_image_view = try vk.createImageView(self.device, &view_info, null);

    // Create sampler
    const sampler_info: vk.VkSamplerCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .magFilter = vk.VK_FILTER_NEAREST,
        .minFilter = vk.VK_FILTER_NEAREST,
        .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .mipLodBias = 0,
        .anisotropyEnable = vk.VK_FALSE,
        .maxAnisotropy = 1,
        .compareEnable = vk.VK_FALSE,
        .compareOp = 0,
        .minLod = 0,
        .maxLod = 0,
        .borderColor = vk.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = vk.VK_FALSE,
    };
    self.font_sampler = try vk.createSampler(self.device, &sampler_info, null);

    std.log.info("Font texture created: {}x{}", .{ font.ATLAS_WIDTH, font.ATLAS_HEIGHT });
}

fn uploadTexture(self: *TextRenderer, renderer: *Renderer, staging_buffer: vk.VkBuffer) !void {
    // Allocate one-shot command buffer
    const alloc_info: vk.VkCommandBufferAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = renderer.command_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var cmd: vk.VkCommandBuffer = null;
    try vk.allocateCommandBuffers(self.device, &alloc_info, @ptrCast(&cmd));

    const begin_info: vk.VkCommandBufferBeginInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    };
    try vk.beginCommandBuffer(cmd, &begin_info);

    const subresource_range: vk.VkImageSubresourceRange = .{
        .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
        .baseMipLevel = 0,
        .levelCount = 1,
        .baseArrayLayer = 0,
        .layerCount = 1,
    };

    // Transition: UNDEFINED → TRANSFER_DST_OPTIMAL
    const barrier_to_transfer: vk.VkImageMemoryBarrier = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        .oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = self.font_image,
        .subresourceRange = subresource_range,
    };

    vk.cmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, @ptrCast(&barrier_to_transfer));

    // Copy buffer to image
    const region: vk.VkBufferImageCopy = .{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = font.ATLAS_WIDTH, .height = font.ATLAS_HEIGHT, .depth = 1 },
    };

    vk.cmdCopyBufferToImage(cmd, staging_buffer, self.font_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, @ptrCast(&region));

    // Transition: TRANSFER_DST_OPTIMAL → SHADER_READ_ONLY_OPTIMAL
    const barrier_to_shader: vk.VkImageMemoryBarrier = .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT,
        .oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = self.font_image,
        .subresourceRange = subresource_range,
    };

    vk.cmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, @ptrCast(&barrier_to_shader));

    try vk.endCommandBuffer(cmd);

    // Submit and wait
    const submit_info: vk.VkSubmitInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 0,
        .pWaitSemaphores = null,
        .pWaitDstStageMask = null,
        .commandBufferCount = 1,
        .pCommandBuffers = @ptrCast(&cmd),
        .signalSemaphoreCount = 0,
        .pSignalSemaphores = null,
    };

    try vk.queueSubmit(renderer.graphics_queue, 1, @ptrCast(&submit_info), null);
    try vk.deviceWaitIdle(self.device);
}

fn createVertexBuffer(self: *TextRenderer, renderer: *Renderer) !void {
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

    const mem_type_index = findMemoryType(mem_properties, mem_requirements.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.NoSuitableDevice;

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

fn createDescriptors(self: *TextRenderer) !void {
    const bindings = [2]vk.VkDescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .pImmutableSamplers = null,
        },
        .{
            .binding = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = null,
        },
    };

    const layout_info: vk.VkDescriptorSetLayoutCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .bindingCount = 2,
        .pBindings = &bindings,
    };

    self.descriptor_set_layout = try vk.createDescriptorSetLayout(self.device, &layout_info, null);

    const pool_sizes = [2]vk.VkDescriptorPoolSize{
        .{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = Renderer.MAX_FRAMES_IN_FLIGHT },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = Renderer.MAX_FRAMES_IN_FLIGHT },
    };

    const pool_info: vk.VkDescriptorPoolCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .maxSets = Renderer.MAX_FRAMES_IN_FLIGHT,
        .poolSizeCount = 2,
        .pPoolSizes = &pool_sizes,
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

    for (0..Renderer.MAX_FRAMES_IN_FLIGHT) |i| {
        const buffer_desc: vk.VkDescriptorBufferInfo = .{
            .buffer = self.vertex_buffer,
            .offset = 0,
            .range = vk.VK_WHOLE_SIZE,
        };

        const image_desc: vk.VkDescriptorImageInfo = .{
            .sampler = self.font_sampler,
            .imageView = self.font_image_view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        };

        const writes = [2]vk.VkWriteDescriptorSet{
            .{
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
            },
            .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = null,
                .dstSet = self.descriptor_sets[i],
                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = @ptrCast(&image_desc),
                .pBufferInfo = null,
                .pTexelBufferView = null,
            },
        };

        vk.updateDescriptorSets(self.device, 2, &writes, 0, null);
    }
}

fn createPipeline(self: *TextRenderer) !void {
    const vert_source = @embedFile("shaders/text.vert");
    const frag_source = @embedFile("shaders/text.frag");

    const compiler = shaderc.compiler_initialize();
    if (compiler == null) return error.InitializationFailed;
    defer shaderc.compiler_release(compiler);

    const vert_result = shaderc.compile_into_spv(compiler, @ptrCast(vert_source.ptr), vert_source.len, shaderc.shaderc_vertex_shader, "text.vert", "main", null);
    defer shaderc.result_release(vert_result);
    if (shaderc.result_get_compilation_status(vert_result) != shaderc.shaderc_compilation_status_success) {
        std.log.err("Text vertex shader failed: {s}", .{shaderc.result_get_error_message(vert_result)});
        return error.InitializationFailed;
    }

    const frag_result = shaderc.compile_into_spv(compiler, @ptrCast(frag_source.ptr), frag_source.len, shaderc.shaderc_fragment_shader, "text.frag", "main", null);
    defer shaderc.result_release(frag_result);
    if (shaderc.result_get_compilation_status(frag_result) != shaderc.shaderc_compilation_status_success) {
        std.log.err("Text fragment shader failed: {s}", .{shaderc.result_get_error_message(frag_result)});
        return error.InitializationFailed;
    }

    const vert_module = try vk.createShaderModule(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = shaderc.result_get_length(vert_result),
        .pCode = @ptrCast(@alignCast(shaderc.result_get_bytes(vert_result))),
    }, null);
    defer vk.destroyShaderModule(self.device, vert_module, null);

    const frag_module = try vk.createShaderModule(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = shaderc.result_get_length(frag_result),
        .pCode = @ptrCast(@alignCast(shaderc.result_get_bytes(frag_result))),
    }, null);
    defer vk.destroyShaderModule(self.device, frag_module, null);

    const shader_stages = [2]vk.VkPipelineShaderStageCreateInfo{
        .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .pNext = null, .flags = 0, .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = vert_module, .pName = "main", .pSpecializationInfo = null },
        .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .pNext = null, .flags = 0, .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = frag_module, .pName = "main", .pSpecializationInfo = null },
    };

    const vertex_input: vk.VkPipelineVertexInputStateCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, .pNext = null, .flags = 0, .vertexBindingDescriptionCount = 0, .pVertexBindingDescriptions = null, .vertexAttributeDescriptionCount = 0, .pVertexAttributeDescriptions = null };
    const input_assembly: vk.VkPipelineInputAssemblyStateCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .pNext = null, .flags = 0, .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, .primitiveRestartEnable = vk.VK_FALSE };
    const viewport_state: vk.VkPipelineViewportStateCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .pNext = null, .flags = 0, .viewportCount = 1, .pViewports = null, .scissorCount = 1, .pScissors = null };
    const rasterizer: vk.VkPipelineRasterizationStateCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .pNext = null, .flags = 0, .depthClampEnable = vk.VK_FALSE, .rasterizerDiscardEnable = vk.VK_FALSE, .polygonMode = vk.VK_POLYGON_MODE_FILL, .cullMode = vk.VK_CULL_MODE_NONE, .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE, .depthBiasEnable = vk.VK_FALSE, .depthBiasConstantFactor = 0, .depthBiasClamp = 0, .depthBiasSlopeFactor = 0, .lineWidth = 1.0 };
    const multisampling: vk.VkPipelineMultisampleStateCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .pNext = null, .flags = 0, .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT, .sampleShadingEnable = vk.VK_FALSE, .minSampleShading = 1.0, .pSampleMask = null, .alphaToCoverageEnable = vk.VK_FALSE, .alphaToOneEnable = vk.VK_FALSE };

    const color_blend_attachment: vk.VkPipelineColorBlendAttachmentState = .{
        .blendEnable = vk.VK_TRUE,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
    };
    const color_blending: vk.VkPipelineColorBlendStateCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .pNext = null, .flags = 0, .logicOpEnable = vk.VK_FALSE, .logicOp = 0, .attachmentCount = 1, .pAttachments = @ptrCast(&color_blend_attachment), .blendConstants = .{ 0, 0, 0, 0 } };

    const dynamic_states = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
    const dynamic_state: vk.VkPipelineDynamicStateCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .pNext = null, .flags = 0, .dynamicStateCount = dynamic_states.len, .pDynamicStates = &dynamic_states };

    const push_constant_range: vk.VkPushConstantRange = .{ .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, .offset = 0, .size = 64 };

    const layout_info: vk.VkPipelineLayoutCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .pNext = null, .flags = 0, .setLayoutCount = 1, .pSetLayouts = @ptrCast(&self.descriptor_set_layout), .pushConstantRangeCount = 1, .pPushConstantRanges = @ptrCast(&push_constant_range) };
    self.pipeline_layout = try vk.createPipelineLayout(self.device, &layout_info, null);

    const rendering_create_info: vk.VkPipelineRenderingCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO, .pNext = null, .viewMask = 0, .colorAttachmentCount = 1, .pColorAttachmentFormats = @ptrCast(&self.swapchain_format), .depthAttachmentFormat = 0, .stencilAttachmentFormat = 0 };

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
    std.log.info("TextRenderer pipeline created", .{});
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
