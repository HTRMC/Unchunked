const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../platform/Window.zig").Window;
const glfw = @import("../platform/glfw.zig");
const vk = @import("../platform/volk.zig");

const Renderer = @This();

pub const MAX_FRAMES_IN_FLIGHT = 2;

pub const FrameContext = struct {
    cmd: vk.VkCommandBuffer,
    image_index: u32,
    extent: vk.VkExtent2D,
    swapchain_image: vk.VkImage,
    swapchain_image_view: vk.VkImageView,
    swapchain_format: vk.VkFormat,
};

// Vulkan state
instance: vk.VkInstance = null,
debug_messenger: vk.VkDebugUtilsMessengerEXT = null,
surface: vk.VkSurfaceKHR = null,
physical_device: vk.VkPhysicalDevice = null,
device: vk.VkDevice = null,
graphics_queue: vk.VkQueue = null,
present_queue: vk.VkQueue = null,
graphics_family: u32 = 0,
present_family: u32 = 0,
swapchain: vk.VkSwapchainKHR = null,
swapchain_format: vk.VkFormat = vk.VK_FORMAT_B8G8R8A8_SRGB,
swapchain_extent: vk.VkExtent2D = .{ .width = 0, .height = 0 },
swapchain_images: [8]vk.VkImage = .{null} ** 8,
swapchain_image_views: [8]vk.VkImageView = .{null} ** 8,
swapchain_image_count: u32 = 0,
command_pool: vk.VkCommandPool = null,
command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.VkCommandBuffer = .{null} ** MAX_FRAMES_IN_FLIGHT,
// Per-swapchain-image semaphores to avoid reuse while presentation is pending
image_available_semaphores: [8]vk.VkSemaphore = .{null} ** 8,
render_finished_semaphores: [8]vk.VkSemaphore = .{null} ** 8,
in_flight_fences: [MAX_FRAMES_IN_FLIGHT]vk.VkFence = .{null} ** MAX_FRAMES_IN_FLIGHT,
current_frame: u32 = 0,
// Tracks which fence each swapchain image is associated with (for waiting before reuse)
image_in_flight: [8]?u32 = .{null} ** 8,
framebuffer_resized: bool = false,
window: *Window = undefined,

fn debugCallback(
    severity: vk.VkDebugUtilsMessageSeverityFlagBitsEXT,
    _: vk.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: ?*const vk.VkDebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.c) vk.VkBool32 {
    const data = callback_data orelse return vk.VK_FALSE;
    const msg: [*:0]const u8 = data.pMessage orelse "unknown";
    if (severity >= vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) {
        std.log.err("Vulkan: {s}", .{msg});
    } else if (severity >= vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        std.log.warn("Vulkan: {s}", .{msg});
    }
    return vk.VK_FALSE;
}

pub fn init(window: *Window) !Renderer {
    var self = Renderer{};
    self.window = window;

    const enable_validation = (builtin.mode == .Debug);

    try vk.initialize();

    // Create instance
    self.instance = try createVulkanInstance(enable_validation);
    vk.loadInstance(self.instance);

    if (enable_validation) {
        self.debug_messenger = setupDebugMessenger(self.instance) catch null;
    }

    self.surface = try window.createSurface(self.instance, null);

    try self.selectPhysicalDevice();
    try self.createLogicalDevice();

    const fb = window.getFramebufferSize();
    try self.createSwapchain(fb.width, fb.height);
    try self.createCommandResources();
    try self.createSyncObjects();

    return self;
}

pub fn deinit(self: *Renderer) void {
    vk.deviceWaitIdle(self.device) catch {};

    for (0..self.swapchain_image_count) |i| {
        vk.destroySemaphore(self.device, self.image_available_semaphores[i], null);
        vk.destroySemaphore(self.device, self.render_finished_semaphores[i], null);
    }
    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        vk.destroyFence(self.device, self.in_flight_fences[i], null);
    }

    vk.destroyCommandPool(self.device, self.command_pool, null);
    self.cleanupSwapchain();
    vk.destroyDevice(self.device, null);

    if (self.debug_messenger != null) {
        vk.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
    }

    vk.destroySurfaceKHR(self.instance, self.surface, null);
    vk.destroyInstance(self.instance, null);
}

pub fn beginFrame(self: *Renderer) !?FrameContext {
    const frame = self.current_frame;

    try vk.waitForFences(self.device, 1, @ptrCast(&self.in_flight_fences[frame]), vk.VK_TRUE, std.math.maxInt(u64));

    var image_index: u32 = 0;
    _ = vk.acquireNextImageKHR(
        self.device,
        self.swapchain,
        std.math.maxInt(u64),
        self.image_available_semaphores[frame],
        null,
        &image_index,
    ) catch |err| {
        if (err == error.OutOfDateKHR) {
            try self.recreateSwapchain();
            return null;
        }
        return err;
    };

    // Wait for any previous frame that was using this swapchain image
    if (self.image_in_flight[image_index]) |prev_frame| {
        try vk.waitForFences(self.device, 1, @ptrCast(&self.in_flight_fences[prev_frame]), vk.VK_TRUE, std.math.maxInt(u64));
    }
    self.image_in_flight[image_index] = frame;

    try vk.resetFences(self.device, 1, @ptrCast(&self.in_flight_fences[frame]));

    const cmd = self.command_buffers[frame];
    try vk.resetCommandBuffer(cmd, 0);

    const begin_info: vk.VkCommandBufferBeginInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    };
    try vk.beginCommandBuffer(cmd, &begin_info);

    return FrameContext{
        .cmd = cmd,
        .image_index = image_index,
        .extent = self.swapchain_extent,
        .swapchain_image = self.swapchain_images[image_index],
        .swapchain_image_view = self.swapchain_image_views[image_index],
        .swapchain_format = self.swapchain_format,
    };
}

pub fn endFrame(self: *Renderer, ctx: FrameContext) !void {
    const frame = self.current_frame;

    try vk.endCommandBuffer(ctx.cmd);

    const wait_stage: u32 = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    const submit_info: vk.VkSubmitInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = @ptrCast(&self.image_available_semaphores[frame]),
        .pWaitDstStageMask = @ptrCast(&wait_stage),
        .commandBufferCount = 1,
        .pCommandBuffers = @ptrCast(&ctx.cmd),
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = @ptrCast(&self.render_finished_semaphores[ctx.image_index]),
    };

    try vk.queueSubmit(self.graphics_queue, 1, @ptrCast(&submit_info), self.in_flight_fences[frame]);

    const present_info: vk.VkPresentInfoKHR = .{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = @ptrCast(&self.render_finished_semaphores[ctx.image_index]),
        .swapchainCount = 1,
        .pSwapchains = @ptrCast(&self.swapchain),
        .pImageIndices = @ptrCast(&ctx.image_index),
        .pResults = null,
    };

    const present_result = vk.queuePresentKHR(self.present_queue, &present_info) catch |err| {
        if (err == error.OutOfDateKHR) {
            try self.recreateSwapchain();
            self.current_frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT;
            return;
        }
        return err;
    };

    if (present_result == vk.VK_SUBOPTIMAL_KHR or self.framebuffer_resized) {
        self.framebuffer_resized = false;
        try self.recreateSwapchain();
    }

    self.current_frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT;
}

fn createVulkanInstance(enable_validation: bool) !vk.VkInstance {
    const app_info: vk.VkApplicationInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "Unchunked",
        .applicationVersion = vk.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "Unchunked",
        .engineVersion = vk.VK_MAKE_VERSION(0, 1, 0),
        .apiVersion = vk.VK_API_VERSION_1_3,
    };

    const glfw_extensions = Window.getRequiredExtensions();

    var extensions: [16][*:0]const u8 = undefined;
    var ext_count: u32 = 0;

    for (0..glfw_extensions.count) |i| {
        extensions[ext_count] = glfw_extensions.names[i];
        ext_count += 1;
    }

    if (enable_validation) {
        extensions[ext_count] = vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
        ext_count += 1;
    }

    const validation_layer: [*:0]const u8 = "VK_LAYER_KHRONOS_validation";

    const create_info: vk.VkInstanceCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = if (enable_validation) 1 else 0,
        .ppEnabledLayerNames = if (enable_validation) @ptrCast(&validation_layer) else null,
        .enabledExtensionCount = ext_count,
        .ppEnabledExtensionNames = &extensions,
    };

    return try vk.createInstance(&create_info, null);
}

fn setupDebugMessenger(instance: vk.VkInstance) !vk.VkDebugUtilsMessengerEXT {
    const create_info: vk.VkDebugUtilsMessengerCreateInfoEXT = .{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .pNext = null,
        .flags = 0,
        .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = debugCallback,
        .pUserData = null,
    };

    return try vk.createDebugUtilsMessengerEXT(instance, &create_info, null);
}

fn selectPhysicalDevice(self: *Renderer) !void {
    var device_count: u32 = 0;
    try vk.enumeratePhysicalDevices(self.instance, &device_count, null);
    if (device_count == 0) return error.NoVulkanDevices;

    var devices: [16]vk.VkPhysicalDevice = .{null} ** 16;
    var count: u32 = @min(device_count, 16);
    try vk.enumeratePhysicalDevices(self.instance, &count, &devices);

    var best: ?vk.VkPhysicalDevice = null;
    var best_discrete = false;

    for (devices[0..count]) |dev| {
        if (dev == null) continue;

        var props: vk.VkPhysicalDeviceProperties = undefined;
        try vk.getPhysicalDeviceProperties(dev, &props);

        var queue_count: u32 = 0;
        try vk.getPhysicalDeviceQueueFamilyProperties(dev, &queue_count, null);
        var queue_props: [32]vk.VkQueueFamilyProperties = undefined;
        var qc: u32 = @min(queue_count, 32);
        try vk.getPhysicalDeviceQueueFamilyProperties(dev, &qc, &queue_props);

        var has_graphics = false;
        var has_present = false;
        var gfx_family: u32 = 0;
        var prs_family: u32 = 0;

        for (0..qc) |i| {
            const idx: u32 = @intCast(i);
            if (queue_props[i].queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
                has_graphics = true;
                gfx_family = idx;
            }
            var present_support: vk.VkBool32 = vk.VK_FALSE;
            vk.getPhysicalDeviceSurfaceSupportKHR(dev, idx, self.surface, &present_support) catch continue;
            if (present_support == vk.VK_TRUE) {
                has_present = true;
                prs_family = idx;
            }
        }

        if (!has_graphics or !has_present) continue;

        const is_discrete = props.deviceType == vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU;
        if (best == null or (is_discrete and !best_discrete)) {
            best = dev;
            best_discrete = is_discrete;
            self.graphics_family = gfx_family;
            self.present_family = prs_family;
        }
    }

    self.physical_device = best orelse return error.NoSuitableDevice;

    var props: vk.VkPhysicalDeviceProperties = undefined;
    try vk.getPhysicalDeviceProperties(self.physical_device, &props);
    const name: [*:0]const u8 = @ptrCast(&props.deviceName);
    std.log.info("Selected GPU: {s}", .{name});
}

fn createLogicalDevice(self: *Renderer) !void {
    const queue_priority: f32 = 1.0;
    var queue_create_infos: [2]vk.VkDeviceQueueCreateInfo = undefined;
    var queue_create_count: u32 = 1;

    queue_create_infos[0] = .{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = self.graphics_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    if (self.present_family != self.graphics_family) {
        queue_create_infos[1] = .{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = self.present_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
        queue_create_count = 2;
    }

    const swapchain_ext = vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME;

    // Enable Vulkan 1.2 features (descriptor indexing)
    var vk12_features: vk.VkPhysicalDeviceVulkan12Features = std.mem.zeroes(vk.VkPhysicalDeviceVulkan12Features);
    vk12_features.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
    vk12_features.descriptorIndexing = vk.VK_TRUE;
    vk12_features.descriptorBindingPartiallyBound = vk.VK_TRUE;
    vk12_features.descriptorBindingVariableDescriptorCount = vk.VK_TRUE;
    vk12_features.runtimeDescriptorArray = vk.VK_TRUE;
    vk12_features.shaderSampledImageArrayNonUniformIndexing = vk.VK_TRUE;
    vk12_features.descriptorBindingUpdateUnusedWhilePending = vk.VK_TRUE;
    vk12_features.descriptorBindingSampledImageUpdateAfterBind = vk.VK_TRUE;

    // Enable Vulkan 1.3 features (dynamic rendering)
    var vk13_features: vk.VkPhysicalDeviceVulkan13Features = std.mem.zeroes(vk.VkPhysicalDeviceVulkan13Features);
    vk13_features.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;
    vk13_features.pNext = &vk12_features;
    vk13_features.dynamicRendering = vk.VK_TRUE;

    const device_create_info: vk.VkDeviceCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &vk13_features,
        .flags = 0,
        .queueCreateInfoCount = queue_create_count,
        .pQueueCreateInfos = &queue_create_infos,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = @ptrCast(&swapchain_ext),
        .pEnabledFeatures = null,
    };

    self.device = try vk.createDevice(self.physical_device, &device_create_info, null);
    vk.loadDevice(self.device);

    vk.getDeviceQueue(self.device, self.graphics_family, 0, &self.graphics_queue);
    vk.getDeviceQueue(self.device, self.present_family, 0, &self.present_queue);

    std.log.info("Logical device created (Vulkan 1.3 dynamic rendering enabled)", .{});
}

fn createSwapchain(self: *Renderer, width: u32, height: u32) !void {
    var caps: vk.VkSurfaceCapabilitiesKHR = undefined;
    try vk.getPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface, &caps);

    var format_count: u32 = 0;
    try vk.getPhysicalDeviceSurfaceFormatsKHR(self.physical_device, self.surface, &format_count, null);
    var formats: [32]vk.VkSurfaceFormatKHR = undefined;
    var fc: u32 = @min(format_count, 32);
    try vk.getPhysicalDeviceSurfaceFormatsKHR(self.physical_device, self.surface, &fc, &formats);

    var chosen_format = formats[0];
    for (formats[0..fc]) |fmt| {
        if (fmt.format == vk.VK_FORMAT_B8G8R8A8_UNORM and fmt.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            chosen_format = fmt;
            break;
        }
    }

    self.swapchain_format = chosen_format.format;

    if (caps.currentExtent.width != 0xFFFFFFFF) {
        self.swapchain_extent = caps.currentExtent;
    } else {
        self.swapchain_extent = .{
            .width = std.math.clamp(width, caps.minImageExtent.width, caps.maxImageExtent.width),
            .height = std.math.clamp(height, caps.minImageExtent.height, caps.maxImageExtent.height),
        };
    }

    var image_count: u32 = MAX_FRAMES_IN_FLIGHT;
    if (image_count < caps.minImageCount) image_count = caps.minImageCount;
    if (caps.maxImageCount > 0 and image_count > caps.maxImageCount) image_count = caps.maxImageCount;

    const same_family = self.graphics_family == self.present_family;
    const family_indices = [2]u32{ self.graphics_family, self.present_family };

    const create_info: vk.VkSwapchainCreateInfoKHR = .{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = self.surface,
        .minImageCount = image_count,
        .imageFormat = chosen_format.format,
        .imageColorSpace = chosen_format.colorSpace,
        .imageExtent = self.swapchain_extent,
        .imageArrayLayers = 1,
        .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .imageSharingMode = if (same_family) vk.VK_SHARING_MODE_EXCLUSIVE else vk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = if (same_family) 0 else 2,
        .pQueueFamilyIndices = if (same_family) null else &family_indices,
        .preTransform = caps.currentTransform,
        .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = vk.VK_PRESENT_MODE_FIFO_KHR,
        .clipped = vk.VK_TRUE,
        .oldSwapchain = null,
    };

    self.swapchain = try vk.createSwapchainKHR(self.device, &create_info, null);

    try vk.getSwapchainImagesKHR(self.device, self.swapchain, &self.swapchain_image_count, null);
    self.swapchain_image_count = @min(self.swapchain_image_count, 8);
    try vk.getSwapchainImagesKHR(self.device, self.swapchain, &self.swapchain_image_count, &self.swapchain_images);

    for (0..self.swapchain_image_count) |i| {
        const view_info: vk.VkImageViewCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = self.swapchain_images[i],
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = self.swapchain_format,
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
        self.swapchain_image_views[i] = try vk.createImageView(self.device, &view_info, null);
    }

    std.log.info("Swapchain created: {}x{}, {} images", .{ self.swapchain_extent.width, self.swapchain_extent.height, self.swapchain_image_count });
}

fn cleanupSwapchain(self: *Renderer) void {
    for (0..self.swapchain_image_count) |i| {
        if (self.swapchain_image_views[i] != null) {
            vk.destroyImageView(self.device, self.swapchain_image_views[i], null);
            self.swapchain_image_views[i] = null;
        }
    }
    if (self.swapchain != null) {
        vk.destroySwapchainKHR(self.device, self.swapchain, null);
        self.swapchain = null;
    }
}

fn recreateSwapchain(self: *Renderer) !void {
    const size = self.window.getFramebufferSize();
    if (size.width == 0 or size.height == 0) return;

    try vk.deviceWaitIdle(self.device);

    // Destroy old per-image semaphores
    for (0..self.swapchain_image_count) |i| {
        if (self.image_available_semaphores[i] != null) {
            vk.destroySemaphore(self.device, self.image_available_semaphores[i], null);
            self.image_available_semaphores[i] = null;
        }
        if (self.render_finished_semaphores[i] != null) {
            vk.destroySemaphore(self.device, self.render_finished_semaphores[i], null);
            self.render_finished_semaphores[i] = null;
        }
    }

    self.cleanupSwapchain();
    try self.createSwapchain(size.width, size.height);

    // Recreate per-image semaphores for new swapchain
    const sem_info: vk.VkSemaphoreCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };
    for (0..self.swapchain_image_count) |i| {
        self.image_available_semaphores[i] = try vk.createSemaphore(self.device, &sem_info, null);
        self.render_finished_semaphores[i] = try vk.createSemaphore(self.device, &sem_info, null);
    }

    self.image_in_flight = .{null} ** 8;
}

fn createCommandResources(self: *Renderer) !void {
    const pool_info: vk.VkCommandPoolCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = self.graphics_family,
    };
    self.command_pool = try vk.createCommandPool(self.device, &pool_info, null);

    const alloc_info: vk.VkCommandBufferAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = self.command_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = MAX_FRAMES_IN_FLIGHT,
    };
    try vk.allocateCommandBuffers(self.device, &alloc_info, &self.command_buffers);
}

fn createSyncObjects(self: *Renderer) !void {
    const sem_info: vk.VkSemaphoreCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };
    const fence_info: vk.VkFenceCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .pNext = null,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    // One semaphore pair per swapchain image to avoid reuse while presentation is pending
    for (0..self.swapchain_image_count) |i| {
        self.image_available_semaphores[i] = try vk.createSemaphore(self.device, &sem_info, null);
        self.render_finished_semaphores[i] = try vk.createSemaphore(self.device, &sem_info, null);
    }
    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        self.in_flight_fences[i] = try vk.createFence(self.device, &fence_info, null);
    }
}

pub fn framebufferSizeCallback(glfw_window: ?*glfw.Window, _: c_int, _: c_int) callconv(.c) void {
    const renderer = glfw.getWindowUserPointer(glfw_window.?, Renderer) orelse return;
    renderer.framebuffer_resized = true;
}
