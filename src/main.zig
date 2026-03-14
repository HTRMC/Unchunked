const std = @import("std");
const builtin = @import("builtin");
const Window = @import("platform/Window.zig").Window;
const glfw = @import("platform/glfw.zig");
const vk = @import("platform/volk.zig");

const MAX_FRAMES_IN_FLIGHT = 2;

const VulkanState = struct {
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
    image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.VkSemaphore = .{null} ** MAX_FRAMES_IN_FLIGHT,
    render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.VkSemaphore = .{null} ** MAX_FRAMES_IN_FLIGHT,
    in_flight_fences: [MAX_FRAMES_IN_FLIGHT]vk.VkFence = .{null} ** MAX_FRAMES_IN_FLIGHT,
    current_frame: u32 = 0,
    framebuffer_resized: bool = false,
};

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

fn createVulkanInstance(enable_validation: bool) !vk.VkInstance {
    const app_info: vk.VkApplicationInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "Unchunked",
        .applicationVersion = vk.VK_MAKE_VERSION(0, 0, 0),
        .pEngineName = "Unchunked",
        .engineVersion = vk.VK_MAKE_VERSION(0, 0, 0),
        .apiVersion = vk.VK_API_VERSION_1_3,
    };

    const glfw_extensions = Window.getRequiredExtensions();

    // Build extension list
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

fn selectPhysicalDevice(state: *VulkanState) !void {
    var device_count: u32 = 0;
    try vk.enumeratePhysicalDevices(state.instance, &device_count, null);
    if (device_count == 0) return error.NoVulkanDevices;

    var devices: [16]vk.VkPhysicalDevice = .{null} ** 16;
    var count: u32 = @min(device_count, 16);
    try vk.enumeratePhysicalDevices(state.instance, &count, &devices);

    // Prefer discrete GPU
    var best: ?vk.VkPhysicalDevice = null;
    var best_discrete = false;

    for (devices[0..count]) |dev| {
        if (dev == null) continue;

        var props: vk.VkPhysicalDeviceProperties = undefined;
        try vk.getPhysicalDeviceProperties(dev, &props);

        // Check queue families
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
            vk.getPhysicalDeviceSurfaceSupportKHR(dev, idx, state.surface, &present_support) catch continue;
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
            state.graphics_family = gfx_family;
            state.present_family = prs_family;
        }
    }

    state.physical_device = best orelse return error.NoSuitableDevice;

    var props: vk.VkPhysicalDeviceProperties = undefined;
    try vk.getPhysicalDeviceProperties(state.physical_device, &props);
    const name: [*:0]const u8 = @ptrCast(&props.deviceName);
    std.log.info("Selected GPU: {s}", .{name});
}

fn createLogicalDevice(state: *VulkanState) !void {
    const queue_priority: f32 = 1.0;
    var queue_create_infos: [2]vk.VkDeviceQueueCreateInfo = undefined;
    var queue_create_count: u32 = 1;

    queue_create_infos[0] = .{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = state.graphics_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    if (state.present_family != state.graphics_family) {
        queue_create_infos[1] = .{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = state.present_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
        queue_create_count = 2;
    }

    const swapchain_ext = vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME;

    const device_create_info: vk.VkDeviceCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueCreateInfoCount = queue_create_count,
        .pQueueCreateInfos = &queue_create_infos,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = @ptrCast(&swapchain_ext),
        .pEnabledFeatures = null,
    };

    state.device = try vk.createDevice(state.physical_device, &device_create_info, null);
    vk.loadDevice(state.device);

    vk.getDeviceQueue(state.device, state.graphics_family, 0, &state.graphics_queue);
    vk.getDeviceQueue(state.device, state.present_family, 0, &state.present_queue);

    std.log.info("Logical device created", .{});
}

fn createSwapchain(state: *VulkanState, width: u32, height: u32) !void {
    var caps: vk.VkSurfaceCapabilitiesKHR = undefined;
    try vk.getPhysicalDeviceSurfaceCapabilitiesKHR(state.physical_device, state.surface, &caps);

    // Choose format
    var format_count: u32 = 0;
    try vk.getPhysicalDeviceSurfaceFormatsKHR(state.physical_device, state.surface, &format_count, null);
    var formats: [32]vk.VkSurfaceFormatKHR = undefined;
    var fc: u32 = @min(format_count, 32);
    try vk.getPhysicalDeviceSurfaceFormatsKHR(state.physical_device, state.surface, &fc, &formats);

    var chosen_format = formats[0];
    for (formats[0..fc]) |fmt| {
        if (fmt.format == vk.VK_FORMAT_B8G8R8A8_SRGB and fmt.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            chosen_format = fmt;
            break;
        }
    }

    state.swapchain_format = chosen_format.format;

    // Choose extent
    if (caps.currentExtent.width != 0xFFFFFFFF) {
        state.swapchain_extent = caps.currentExtent;
    } else {
        state.swapchain_extent = .{
            .width = std.math.clamp(width, caps.minImageExtent.width, caps.maxImageExtent.width),
            .height = std.math.clamp(height, caps.minImageExtent.height, caps.maxImageExtent.height),
        };
    }

    // Use exactly MAX_FRAMES_IN_FLIGHT images to avoid semaphore reuse issues
    var image_count: u32 = MAX_FRAMES_IN_FLIGHT;
    if (image_count < caps.minImageCount) image_count = caps.minImageCount;
    if (caps.maxImageCount > 0 and image_count > caps.maxImageCount) image_count = caps.maxImageCount;

    const same_family = state.graphics_family == state.present_family;
    const family_indices = [2]u32{ state.graphics_family, state.present_family };

    const create_info: vk.VkSwapchainCreateInfoKHR = .{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = state.surface,
        .minImageCount = image_count,
        .imageFormat = chosen_format.format,
        .imageColorSpace = chosen_format.colorSpace,
        .imageExtent = state.swapchain_extent,
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

    state.swapchain = try vk.createSwapchainKHR(state.device, &create_info, null);

    // Get swapchain images
    try vk.getSwapchainImagesKHR(state.device, state.swapchain, &state.swapchain_image_count, null);
    state.swapchain_image_count = @min(state.swapchain_image_count, 8);
    try vk.getSwapchainImagesKHR(state.device, state.swapchain, &state.swapchain_image_count, &state.swapchain_images);

    // Create image views
    for (0..state.swapchain_image_count) |i| {
        const view_info: vk.VkImageViewCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = state.swapchain_images[i],
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = state.swapchain_format,
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
        state.swapchain_image_views[i] = try vk.createImageView(state.device, &view_info, null);
    }

    std.log.info("Swapchain created: {}x{}, {} images", .{ state.swapchain_extent.width, state.swapchain_extent.height, state.swapchain_image_count });
}

fn cleanupSwapchain(state: *VulkanState) void {
    for (0..state.swapchain_image_count) |i| {
        if (state.swapchain_image_views[i] != null) {
            vk.destroyImageView(state.device, state.swapchain_image_views[i], null);
            state.swapchain_image_views[i] = null;
        }
    }
    if (state.swapchain != null) {
        vk.destroySwapchainKHR(state.device, state.swapchain, null);
        state.swapchain = null;
    }
}

fn recreateSwapchain(state: *VulkanState, window: *const Window) !void {
    const size = window.getFramebufferSize();
    if (size.width == 0 or size.height == 0) return;

    try vk.deviceWaitIdle(state.device);
    cleanupSwapchain(state);
    try createSwapchain(state, size.width, size.height);
}

fn createCommandResources(state: *VulkanState) !void {
    const pool_info: vk.VkCommandPoolCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = state.graphics_family,
    };
    state.command_pool = try vk.createCommandPool(state.device, &pool_info, null);

    const alloc_info: vk.VkCommandBufferAllocateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = state.command_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = MAX_FRAMES_IN_FLIGHT,
    };
    try vk.allocateCommandBuffers(state.device, &alloc_info, &state.command_buffers);
}

fn createSyncObjects(state: *VulkanState) !void {
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

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        state.image_available_semaphores[i] = try vk.createSemaphore(state.device, &sem_info, null);
        state.render_finished_semaphores[i] = try vk.createSemaphore(state.device, &sem_info, null);
        state.in_flight_fences[i] = try vk.createFence(state.device, &fence_info, null);
    }
}

fn recordCommandBuffer(state: *VulkanState, image_index: u32) !void {
    const cmd = state.command_buffers[state.current_frame];

    try vk.resetCommandBuffer(cmd, 0);

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
    const barrier_to_clear: vk.VkImageMemoryBarrier = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        .oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
        .image = state.swapchain_images[image_index],
        .subresourceRange = subresource_range,
    };

    vk.cmdPipelineBarrier(
        cmd,
        vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
        0,
        0,
        null,
        0,
        null,
        1,
        @ptrCast(&barrier_to_clear),
    );

    // Cornflower blue: (100/255, 149/255, 237/255, 1.0)
    const clear_color: vk.VkClearColorValue = .{ .float32 = .{ 0.392, 0.584, 0.929, 1.0 } };

    vk.cmdClearColorImage(
        cmd,
        state.swapchain_images[image_index],
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        &clear_color,
        1,
        @ptrCast(&subresource_range),
    );

    // Transition: TRANSFER_DST_OPTIMAL → PRESENT_SRC_KHR
    const barrier_to_present: vk.VkImageMemoryBarrier = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        .dstAccessMask = 0,
        .oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .newLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .srcQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
        .image = state.swapchain_images[image_index],
        .subresourceRange = subresource_range,
    };

    vk.cmdPipelineBarrier(
        cmd,
        vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
        vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        0,
        0,
        null,
        0,
        null,
        1,
        @ptrCast(&barrier_to_present),
    );

    try vk.endCommandBuffer(cmd);
}

fn drawFrame(state: *VulkanState, window: *const Window) !void {
    const frame = state.current_frame;

    try vk.waitForFences(state.device, 1, @ptrCast(&state.in_flight_fences[frame]), vk.VK_TRUE, std.math.maxInt(u64));

    var image_index: u32 = 0;
    const acquire_result = vk.acquireNextImageKHR(
        state.device,
        state.swapchain,
        std.math.maxInt(u64),
        state.image_available_semaphores[frame],
        null,
        &image_index,
    ) catch |err| {
        if (err == error.OutOfDateKHR) {
            try recreateSwapchain(state, window);
            return;
        }
        return err;
    };

    try vk.resetFences(state.device, 1, @ptrCast(&state.in_flight_fences[frame]));

    try recordCommandBuffer(state, image_index);

    const wait_stage: u32 = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    const submit_info: vk.VkSubmitInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = @ptrCast(&state.image_available_semaphores[frame]),
        .pWaitDstStageMask = @ptrCast(&wait_stage),
        .commandBufferCount = 1,
        .pCommandBuffers = @ptrCast(&state.command_buffers[frame]),
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = @ptrCast(&state.render_finished_semaphores[frame]),
    };

    try vk.queueSubmit(state.graphics_queue, 1, @ptrCast(&submit_info), state.in_flight_fences[frame]);

    const present_info: vk.VkPresentInfoKHR = .{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = @ptrCast(&state.render_finished_semaphores[frame]),
        .swapchainCount = 1,
        .pSwapchains = @ptrCast(&state.swapchain),
        .pImageIndices = @ptrCast(&image_index),
        .pResults = null,
    };

    const present_result = vk.queuePresentKHR(state.present_queue, &present_info) catch |err| {
        if (err == error.OutOfDateKHR) {
            try recreateSwapchain(state, window);
            state.current_frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT;
            return;
        }
        return err;
    };

    if (present_result == vk.VK_SUBOPTIMAL_KHR or acquire_result == vk.VK_SUBOPTIMAL_KHR or state.framebuffer_resized) {
        state.framebuffer_resized = false;
        try recreateSwapchain(state, window);
    }

    state.current_frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT;
}

fn framebufferSizeCallback(glfw_window: ?*glfw.Window, _: c_int, _: c_int) callconv(.c) void {
    const state = glfw.getWindowUserPointer(glfw_window.?, VulkanState) orelse return;
    state.framebuffer_resized = true;
}

pub fn main() !void {
    const enable_validation = (builtin.mode == .Debug);

    var window = try Window.init(.{
        .width = 1280,
        .height = 720,
        .title = "Unchunked",
    });
    defer window.deinit();

    var state = VulkanState{};

    glfw.setWindowUserPointer(window.handle, &state);
    glfw.setFramebufferSizeCallback(window.handle, framebufferSizeCallback);

    // Initialize Vulkan
    try vk.initialize();
    std.log.info("Volk initialized", .{});

    state.instance = try createVulkanInstance(enable_validation);
    vk.loadInstance(state.instance);
    std.log.info("Vulkan instance created", .{});

    if (enable_validation) {
        state.debug_messenger = setupDebugMessenger(state.instance) catch null;
    }

    state.surface = try window.createSurface(state.instance, null);
    std.log.info("Vulkan surface created", .{});

    try selectPhysicalDevice(&state);
    try createLogicalDevice(&state);

    const fb = window.getFramebufferSize();
    try createSwapchain(&state, fb.width, fb.height);
    try createCommandResources(&state);
    try createSyncObjects(&state);

    std.log.info("Entering main loop...", .{});

    while (!window.shouldClose()) {
        window.pollEvents();
        drawFrame(&state, &window) catch |err| {
            std.log.err("Draw frame error: {}", .{err});
        };
    }

    // Cleanup
    std.log.info("Shutting down...", .{});
    vk.deviceWaitIdle(state.device) catch {};

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        vk.destroySemaphore(state.device, state.image_available_semaphores[i], null);
        vk.destroySemaphore(state.device, state.render_finished_semaphores[i], null);
        vk.destroyFence(state.device, state.in_flight_fences[i], null);
    }

    vk.destroyCommandPool(state.device, state.command_pool, null);
    cleanupSwapchain(&state);
    vk.destroyDevice(state.device, null);

    if (state.debug_messenger != null) {
        vk.destroyDebugUtilsMessengerEXT(state.instance, state.debug_messenger, null);
    }

    vk.destroySurfaceKHR(state.instance, state.surface, null);
    vk.destroyInstance(state.instance, null);
}
