const std = @import("std");
const vk = @import("../platform/volk.zig");
const shaderc = @import("../platform/shaderc.zig");
const Renderer = @import("Renderer.zig");
const Region = @import("../world/Region.zig");

const TileRenderer = @This();

const MAX_DRAW = 4096;
const VERTICES_PER_TILE = 6;
const MAX_VERTICES = MAX_DRAW * VERTICES_PER_TILE;
const MAX_TEXTURES = 4096;
const MAX_UPLOADS_PER_FRAME = 8;
const TILE_PX = Region.REGION_PX;

const TileVertex = extern struct {
    px: f32,
    py: f32,
    u: f32,
    v: f32,
    tex_index: i32,
    _pad: i32 = 0,
};

const VERTEX_SIZE = @sizeOf(TileVertex);
const BUFFER_SIZE = MAX_VERTICES * VERTEX_SIZE;

const RegionKey = struct { rx: i32, rz: i32 };
const RegionKeyContext = struct {
    pub fn hash(_: @This(), key: RegionKey) u64 {
        var h: u64 = 0;
        h = std.hash.Wyhash.hash(h, std.mem.asBytes(&key.rx));
        h = std.hash.Wyhash.hash(h, std.mem.asBytes(&key.rz));
        return h;
    }
    pub fn eql(_: @This(), a: RegionKey, b: RegionKey) bool {
        return a.rx == b.rx and a.rz == b.rz;
    }
};

const RegionTexture = struct {
    image: vk.VkImage,
    image_view: vk.VkImageView,
    memory: vk.VkDeviceMemory,
    index: u32,
};

// Pending upload: image created but not yet copied from staging
const PendingUpload = struct {
    image: vk.VkImage,
    image_view: vk.VkImageView,
    memory: vk.VkDeviceMemory,
    staging_offset: u64,
    key: RegionKey,
    tex_index: u32,
};

pipeline: vk.VkPipeline = null,
pipeline_layout: vk.VkPipelineLayout = null,
descriptor_set_layout: vk.VkDescriptorSetLayout = null,
descriptor_pool: vk.VkDescriptorPool = null,
descriptor_sets: [Renderer.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet = .{null} ** Renderer.MAX_FRAMES_IN_FLIGHT,
vertex_buffer: vk.VkBuffer = null,
vertex_memory: vk.VkDeviceMemory = null,
mapped_data: ?*anyopaque = null,
vertex_count: u32 = 0,
sampler: vk.VkSampler = null,
staging_buffer: vk.VkBuffer = null,
staging_memory: vk.VkDeviceMemory = null,
staging_mapped: ?*anyopaque = null,
device: vk.VkDevice = null,
physical_device: vk.VkPhysicalDevice = null,
swapchain_format: vk.VkFormat = vk.VK_FORMAT_B8G8R8A8_SRGB,
command_pool: vk.VkCommandPool = null,
graphics_queue: vk.VkQueue = null,
allocator: std.mem.Allocator = undefined,
region_textures: std.HashMap(RegionKey, RegionTexture, RegionKeyContext, std.hash_map.default_max_load_percentage) = undefined,
next_texture_index: u32 = 0,
pending_uploads: [MAX_UPLOADS_PER_FRAME]?PendingUpload = .{null} ** MAX_UPLOADS_PER_FRAME,
pending_count: u32 = 0,

pub fn init(renderer: *Renderer, allocator: std.mem.Allocator) !TileRenderer {
    var self = TileRenderer{};
    self.device = renderer.device;
    self.physical_device = renderer.physical_device;
    self.swapchain_format = renderer.swapchain_format;
    self.command_pool = renderer.command_pool;
    self.graphics_queue = renderer.graphics_queue;
    self.allocator = allocator;
    self.region_textures = @TypeOf(self.region_textures).init(allocator);

    try self.createSampler();
    try self.createStagingBuffer();
    try self.createVertexBuffer();
    try self.createDescriptors();
    try self.createPipeline();

    return self;
}

pub fn deinit(self: *TileRenderer) void {
    vk.deviceWaitIdle(self.device) catch {};

    var it = self.region_textures.valueIterator();
    while (it.next()) |tex| {
        vk.destroyImageView(self.device, tex.image_view, null);
        vk.destroyImage(self.device, tex.image, null);
        vk.freeMemory(self.device, tex.memory, null);
    }
    self.region_textures.deinit();

    if (self.descriptor_pool != null) vk.destroyDescriptorPool(self.device, self.descriptor_pool, null);
    if (self.descriptor_set_layout != null) vk.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
    if (self.pipeline != null) vk.destroyPipeline(self.device, self.pipeline, null);
    if (self.pipeline_layout != null) vk.destroyPipelineLayout(self.device, self.pipeline_layout, null);
    if (self.vertex_buffer != null) vk.destroyBuffer(self.device, self.vertex_buffer, null);
    if (self.vertex_memory != null) vk.freeMemory(self.device, self.vertex_memory, null);
    if (self.staging_buffer != null) vk.destroyBuffer(self.device, self.staging_buffer, null);
    if (self.staging_memory != null) vk.freeMemory(self.device, self.staging_memory, null);
    if (self.sampler != null) vk.destroySampler(self.device, self.sampler, null);
}

/// Stage a region for upload. Copies pixels to staging buffer and creates VkImage.
/// The actual GPU copy happens in recordUploads().
pub fn uploadRegion(self: *TileRenderer, rx: i32, rz: i32, pixels: []const u8, frame_index: u32) bool {
    const key = RegionKey{ .rx = rx, .rz = rz };
    if (self.region_textures.contains(key)) return true;
    if (self.next_texture_index >= MAX_TEXTURES) return false;
    if (self.pending_count >= MAX_UPLOADS_PER_FRAME) return false;

    // Copy pixels into this frame's staging region (double-buffered to avoid GPU race)
    const frame_base = @as(u64, frame_index) * MAX_UPLOADS_PER_FRAME * Region.PIXEL_DATA_SIZE;
    const staging_offset = frame_base + @as(u64, self.pending_count) * Region.PIXEL_DATA_SIZE;
    const dst: [*]u8 = @ptrCast(self.staging_mapped orelse return false);
    @memcpy(dst[staging_offset..][0..Region.PIXEL_DATA_SIZE], pixels[0..Region.PIXEL_DATA_SIZE]);

    // Create VkImage (no GPU commands yet)
    const image = vk.createImage(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .pNext = null, .flags = 0,
        .imageType = vk.VK_IMAGE_TYPE_2D, .format = vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .extent = .{ .width = TILE_PX, .height = TILE_PX, .depth = 1 },
        .mipLevels = 1, .arrayLayers = 1, .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
        .usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE, .queueFamilyIndexCount = 0, .pQueueFamilyIndices = null,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    }, null) catch return false;

    var mem_req: vk.VkMemoryRequirements = undefined;
    vk.getImageMemoryRequirements(self.device, image, &mem_req);
    var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.getPhysicalDeviceMemoryProperties(self.physical_device, &mem_props);

    const memory = vk.allocateMemory(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = null,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = findMemoryType(mem_props, mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return false,
    }, null) catch return false;
    vk.bindImageMemory(self.device, image, memory, 0) catch return false;

    const image_view = vk.createImageView(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .pNext = null, .flags = 0,
        .image = image, .viewType = vk.VK_IMAGE_VIEW_TYPE_2D, .format = vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .components = .{ .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY, .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY },
        .subresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
    }, null) catch return false;

    const tex_index = self.next_texture_index;

    self.pending_uploads[self.pending_count] = .{
        .image = image,
        .image_view = image_view,
        .memory = memory,
        .staging_offset = staging_offset,
        .key = key,
        .tex_index = tex_index,
    };
    self.pending_count += 1;
    self.next_texture_index += 1;

    return true;
}

/// Record all pending uploads into the given command buffer.
/// Call this BEFORE beginRendering in the frame's command buffer.
pub fn recordUploads(self: *TileRenderer, cmd: vk.VkCommandBuffer) void {
    if (self.pending_count == 0) return;

    const subresource_range: vk.VkImageSubresourceRange = .{
        .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1,
    };

    for (self.pending_uploads[0..self.pending_count]) |maybe_upload| {
        const upload = maybe_upload orelse continue;

        // UNDEFINED → TRANSFER_DST
        vk.cmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, @ptrCast(&vk.VkImageMemoryBarrier{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .pNext = null,
            .srcAccessMask = 0, .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
            .oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .image = upload.image, .subresourceRange = subresource_range,
        }));

        vk.cmdCopyBufferToImage(cmd, self.staging_buffer, upload.image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, @ptrCast(&vk.VkBufferImageCopy{
            .bufferOffset = upload.staging_offset, .bufferRowLength = 0, .bufferImageHeight = 0,
            .imageSubresource = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
            .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
            .imageExtent = .{ .width = TILE_PX, .height = TILE_PX, .depth = 1 },
        }));

        // TRANSFER_DST → SHADER_READ_ONLY
        vk.cmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, @ptrCast(&vk.VkImageMemoryBarrier{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .pNext = null,
            .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT, .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT,
            .oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, .newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .image = upload.image, .subresourceRange = subresource_range,
        }));

        // Register in texture map and update descriptors
        self.region_textures.put(upload.key, .{
            .image = upload.image,
            .image_view = upload.image_view,
            .memory = upload.memory,
            .index = upload.tex_index,
        }) catch continue;

        const image_desc: vk.VkDescriptorImageInfo = .{
            .sampler = self.sampler,
            .imageView = upload.image_view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        };

        for (0..Renderer.MAX_FRAMES_IN_FLIGHT) |i| {
            const write: vk.VkWriteDescriptorSet = .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .pNext = null,
                .dstSet = self.descriptor_sets[i], .dstBinding = 1, .dstArrayElement = upload.tex_index,
                .descriptorCount = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = @ptrCast(&image_desc), .pBufferInfo = null, .pTexelBufferView = null,
            };
            vk.updateDescriptorSets(self.device, 1, @ptrCast(&write), 0, null);
        }
    }

    // Reset pending uploads
    for (&self.pending_uploads) |*u| u.* = null;
    self.pending_count = 0;
}

pub fn clearSlots(self: *TileRenderer) void {
    vk.deviceWaitIdle(self.device) catch {};
    var it = self.region_textures.valueIterator();
    while (it.next()) |tex| {
        vk.destroyImageView(self.device, tex.image_view, null);
        vk.destroyImage(self.device, tex.image, null);
        vk.freeMemory(self.device, tex.memory, null);
    }
    self.region_textures.clearRetainingCapacity();
    self.next_texture_index = 0;
    self.pending_count = 0;
}

pub fn beginFrame(self: *TileRenderer) void {
    self.vertex_count = 0;
}

pub fn drawRegion(self: *TileRenderer, rx: i32, rz: i32) void {
    if (self.vertex_count + VERTICES_PER_TILE > MAX_VERTICES) return;

    const key = RegionKey{ .rx = rx, .rz = rz };
    const tex = self.region_textures.get(key) orelse return;
    const tex_idx: i32 = @intCast(tex.index);

    const wx: f32 = @floatFromInt(@as(i32, rx) * 32);
    const wz: f32 = @floatFromInt(@as(i32, rz) * 32);

    const base: [*]TileVertex = @ptrCast(@alignCast(self.mapped_data orelse return));
    const verts = base[self.vertex_count..][0..6];

    verts[0] = .{ .px = wx, .py = wz, .u = 0, .v = 0, .tex_index = tex_idx };
    verts[1] = .{ .px = wx + 32, .py = wz, .u = 1, .v = 0, .tex_index = tex_idx };
    verts[2] = .{ .px = wx, .py = wz + 32, .u = 0, .v = 1, .tex_index = tex_idx };
    verts[3] = .{ .px = wx + 32, .py = wz, .u = 1, .v = 0, .tex_index = tex_idx };
    verts[4] = .{ .px = wx + 32, .py = wz + 32, .u = 1, .v = 1, .tex_index = tex_idx };
    verts[5] = .{ .px = wx, .py = wz + 32, .u = 0, .v = 1, .tex_index = tex_idx };

    self.vertex_count += VERTICES_PER_TILE;
}

pub fn flush(self: *TileRenderer, cmd: vk.VkCommandBuffer, view_proj: *const [16]f32, frame_index: u32) void {
    if (self.vertex_count == 0) return;

    vk.cmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);
    vk.cmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, @ptrCast(&self.descriptor_sets[frame_index]), 0, null);
    vk.cmdPushConstants(cmd, self.pipeline_layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, view_proj);
    vk.cmdDraw(cmd, self.vertex_count, 1, 0, 0);
}

fn createSampler(self: *TileRenderer) !void {
    self.sampler = try vk.createSampler(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, .pNext = null, .flags = 0,
        .magFilter = vk.VK_FILTER_NEAREST, .minFilter = vk.c.VK_FILTER_LINEAR,
        .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .mipLodBias = 0, .anisotropyEnable = vk.VK_FALSE, .maxAnisotropy = 1,
        .compareEnable = vk.VK_FALSE, .compareOp = 0, .minLod = 0, .maxLod = 0,
        .borderColor = vk.VK_BORDER_COLOR_INT_OPAQUE_BLACK, .unnormalizedCoordinates = vk.VK_FALSE,
    }, null);
}

fn createStagingBuffer(self: *TileRenderer) !void {
    // Double-buffered: each frame slot gets its own staging region
    const staging_size = Region.PIXEL_DATA_SIZE * MAX_UPLOADS_PER_FRAME * Renderer.MAX_FRAMES_IN_FLIGHT;
    self.staging_buffer = try vk.createBuffer(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .pNext = null, .flags = 0,
        .size = staging_size, .usage = vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE, .queueFamilyIndexCount = 0, .pQueueFamilyIndices = null,
    }, null);

    var mem_req: vk.VkMemoryRequirements = undefined;
    vk.getBufferMemoryRequirements(self.device, self.staging_buffer, &mem_req);
    var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.getPhysicalDeviceMemoryProperties(self.physical_device, &mem_props);

    self.staging_memory = try vk.allocateMemory(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = null,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = findMemoryType(mem_props, mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.NoSuitableDevice,
    }, null);
    try vk.bindBufferMemory(self.device, self.staging_buffer, self.staging_memory, 0);
    try vk.mapMemory(self.device, self.staging_memory, 0, staging_size, 0, &self.staging_mapped);
}

fn createVertexBuffer(self: *TileRenderer) !void {
    self.vertex_buffer = try vk.createBuffer(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .pNext = null, .flags = 0,
        .size = BUFFER_SIZE, .usage = vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE, .queueFamilyIndexCount = 0, .pQueueFamilyIndices = null,
    }, null);

    var mem_req: vk.VkMemoryRequirements = undefined;
    vk.getBufferMemoryRequirements(self.device, self.vertex_buffer, &mem_req);
    var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.getPhysicalDeviceMemoryProperties(self.physical_device, &mem_props);

    self.vertex_memory = try vk.allocateMemory(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = null,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = findMemoryType(mem_props, mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.NoSuitableDevice,
    }, null);
    try vk.bindBufferMemory(self.device, self.vertex_buffer, self.vertex_memory, 0);
    try vk.mapMemory(self.device, self.vertex_memory, 0, vk.VK_WHOLE_SIZE, 0, &self.mapped_data);
}

fn createDescriptors(self: *TileRenderer) !void {
    const bindings = [2]vk.VkDescriptorSetLayoutBinding{
        .{ .binding = 0, .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, .pImmutableSamplers = null },
        .{ .binding = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = MAX_TEXTURES, .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .pImmutableSamplers = null },
    };

    const binding_flags = [2]vk.VkDescriptorBindingFlags{
        0,
        vk.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT | vk.VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT | vk.VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT,
    };

    const flags_info: vk.VkDescriptorSetLayoutBindingFlagsCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO, .pNext = null,
        .bindingCount = 2, .pBindingFlags = &binding_flags,
    };

    self.descriptor_set_layout = try vk.createDescriptorSetLayout(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = &flags_info,
        .flags = vk.VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT,
        .bindingCount = 2, .pBindings = &bindings,
    }, null);

    const pool_sizes = [2]vk.VkDescriptorPoolSize{
        .{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = Renderer.MAX_FRAMES_IN_FLIGHT },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = MAX_TEXTURES * Renderer.MAX_FRAMES_IN_FLIGHT },
    };

    self.descriptor_pool = try vk.createDescriptorPool(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .pNext = null,
        .flags = vk.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
        .maxSets = Renderer.MAX_FRAMES_IN_FLIGHT, .poolSizeCount = 2, .pPoolSizes = &pool_sizes,
    }, null);

    var layouts: [Renderer.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSetLayout = undefined;
    for (&layouts) |*l| l.* = self.descriptor_set_layout;

    const variable_counts = [Renderer.MAX_FRAMES_IN_FLIGHT]u32{ MAX_TEXTURES, MAX_TEXTURES };
    const variable_count_info: vk.VkDescriptorSetVariableDescriptorCountAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO, .pNext = null,
        .descriptorSetCount = Renderer.MAX_FRAMES_IN_FLIGHT, .pDescriptorCounts = &variable_counts,
    };

    try vk.allocateDescriptorSets(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = &variable_count_info,
        .descriptorPool = self.descriptor_pool,
        .descriptorSetCount = Renderer.MAX_FRAMES_IN_FLIGHT, .pSetLayouts = &layouts,
    }, &self.descriptor_sets);

    for (0..Renderer.MAX_FRAMES_IN_FLIGHT) |i| {
        const buffer_desc: vk.VkDescriptorBufferInfo = .{ .buffer = self.vertex_buffer, .offset = 0, .range = vk.VK_WHOLE_SIZE };
        const write: vk.VkWriteDescriptorSet = .{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .pNext = null,
            .dstSet = self.descriptor_sets[i], .dstBinding = 0, .dstArrayElement = 0,
            .descriptorCount = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pImageInfo = null, .pBufferInfo = @ptrCast(&buffer_desc), .pTexelBufferView = null,
        };
        vk.updateDescriptorSets(self.device, 1, @ptrCast(&write), 0, null);
    }

    std.log.info("TileRenderer: bindless descriptors (max {} textures)", .{MAX_TEXTURES});
}

fn createPipeline(self: *TileRenderer) !void {
    const vert_source = @embedFile("shaders/tile.vert");
    const frag_source = @embedFile("shaders/tile.frag");

    const compiler = shaderc.compiler_initialize();
    if (compiler == null) return error.InitializationFailed;
    defer shaderc.compiler_release(compiler);

    const vert_result = shaderc.compile_into_spv(compiler, @ptrCast(vert_source.ptr), vert_source.len, shaderc.shaderc_vertex_shader, "tile.vert", "main", null);
    defer shaderc.result_release(vert_result);
    if (shaderc.result_get_compilation_status(vert_result) != shaderc.shaderc_compilation_status_success) {
        std.log.err("Tile vertex shader: {s}", .{shaderc.result_get_error_message(vert_result)});
        return error.InitializationFailed;
    }

    const frag_result = shaderc.compile_into_spv(compiler, @ptrCast(frag_source.ptr), frag_source.len, shaderc.shaderc_fragment_shader, "tile.frag", "main", null);
    defer shaderc.result_release(frag_result);
    if (shaderc.result_get_compilation_status(frag_result) != shaderc.shaderc_compilation_status_success) {
        std.log.err("Tile fragment shader: {s}", .{shaderc.result_get_error_message(frag_result)});
        return error.InitializationFailed;
    }

    const vert_module = try vk.createShaderModule(self.device, &.{ .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .pNext = null, .flags = 0, .codeSize = shaderc.result_get_length(vert_result), .pCode = @ptrCast(@alignCast(shaderc.result_get_bytes(vert_result))) }, null);
    defer vk.destroyShaderModule(self.device, vert_module, null);
    const frag_module = try vk.createShaderModule(self.device, &.{ .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .pNext = null, .flags = 0, .codeSize = shaderc.result_get_length(frag_result), .pCode = @ptrCast(@alignCast(shaderc.result_get_bytes(frag_result))) }, null);
    defer vk.destroyShaderModule(self.device, frag_module, null);

    const shader_stages = [2]vk.VkPipelineShaderStageCreateInfo{
        .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .pNext = null, .flags = 0, .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = vert_module, .pName = "main", .pSpecializationInfo = null },
        .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .pNext = null, .flags = 0, .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = frag_module, .pName = "main", .pSpecializationInfo = null },
    };

    const dynamic_states = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
    const push_constant_range: vk.VkPushConstantRange = .{ .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, .offset = 0, .size = 64 };

    self.pipeline_layout = try vk.createPipelineLayout(self.device, &.{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .pNext = null, .flags = 0,
        .setLayoutCount = 1, .pSetLayouts = @ptrCast(&self.descriptor_set_layout),
        .pushConstantRangeCount = 1, .pPushConstantRanges = @ptrCast(&push_constant_range),
    }, null);

    const rendering_info: vk.VkPipelineRenderingCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO, .pNext = null, .viewMask = 0, .colorAttachmentCount = 1, .pColorAttachmentFormats = @ptrCast(&self.swapchain_format), .depthAttachmentFormat = 0, .stencilAttachmentFormat = 0 };

    try vk.createGraphicsPipelines(self.device, null, 1, @ptrCast(&vk.VkGraphicsPipelineCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, .pNext = &rendering_info, .flags = 0,
        .stageCount = 2, .pStages = &shader_stages,
        .pVertexInputState = &vk.VkPipelineVertexInputStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, .pNext = null, .flags = 0, .vertexBindingDescriptionCount = 0, .pVertexBindingDescriptions = null, .vertexAttributeDescriptionCount = 0, .pVertexAttributeDescriptions = null },
        .pInputAssemblyState = &vk.VkPipelineInputAssemblyStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .pNext = null, .flags = 0, .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, .primitiveRestartEnable = vk.VK_FALSE },
        .pTessellationState = null,
        .pViewportState = &vk.VkPipelineViewportStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .pNext = null, .flags = 0, .viewportCount = 1, .pViewports = null, .scissorCount = 1, .pScissors = null },
        .pRasterizationState = &vk.VkPipelineRasterizationStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .pNext = null, .flags = 0, .depthClampEnable = vk.VK_FALSE, .rasterizerDiscardEnable = vk.VK_FALSE, .polygonMode = vk.VK_POLYGON_MODE_FILL, .cullMode = vk.VK_CULL_MODE_NONE, .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE, .depthBiasEnable = vk.VK_FALSE, .depthBiasConstantFactor = 0, .depthBiasClamp = 0, .depthBiasSlopeFactor = 0, .lineWidth = 1.0 },
        .pMultisampleState = &vk.VkPipelineMultisampleStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .pNext = null, .flags = 0, .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT, .sampleShadingEnable = vk.VK_FALSE, .minSampleShading = 1.0, .pSampleMask = null, .alphaToCoverageEnable = vk.VK_FALSE, .alphaToOneEnable = vk.VK_FALSE },
        .pDepthStencilState = null,
        .pColorBlendState = &vk.VkPipelineColorBlendStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .pNext = null, .flags = 0, .logicOpEnable = vk.VK_FALSE, .logicOp = 0, .attachmentCount = 1, .pAttachments = @ptrCast(&vk.VkPipelineColorBlendAttachmentState{
            .blendEnable = vk.VK_FALSE, .srcColorBlendFactor = vk.VK_BLEND_FACTOR_ONE, .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ZERO, .colorBlendOp = vk.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE, .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO, .alphaBlendOp = vk.VK_BLEND_OP_ADD,
            .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
        }), .blendConstants = .{ 0, 0, 0, 0 } },
        .pDynamicState = &vk.VkPipelineDynamicStateCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .pNext = null, .flags = 0, .dynamicStateCount = dynamic_states.len, .pDynamicStates = &dynamic_states },
        .layout = self.pipeline_layout, .renderPass = null, .subpass = 0, .basePipelineHandle = null, .basePipelineIndex = -1,
    }), null, @ptrCast(&self.pipeline));

    std.log.info("TileRenderer pipeline created (bindless)", .{});
}

fn findMemoryType(mem_properties: vk.VkPhysicalDeviceMemoryProperties, type_filter: u32, properties: u32) ?u32 {
    for (0..mem_properties.memoryTypeCount) |i| {
        const idx: u5 = @intCast(i);
        if ((type_filter & (@as(u32, 1) << idx)) != 0 and
            (mem_properties.memoryTypes[i].propertyFlags & properties) == properties)
            return @intCast(i);
    }
    return null;
}
