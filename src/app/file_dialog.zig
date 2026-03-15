const std = @import("std");
const builtin = @import("builtin");

pub fn openFolderDialog(allocator: std.mem.Allocator, io: std.Io, environ_map: *std.process.Environ.Map) !?[]const u8 {
    if (comptime builtin.os.tag == .windows) {
        return openFolderWindows(allocator, io, environ_map);
    } else {
        return openFolderLinux(allocator, io);
    }
}

fn openFolderWindows(allocator: std.mem.Allocator, io: std.Io, environ_map: *std.process.Environ.Map) !?[]const u8 {
    const default_path = getDefaultSavesPathWindows(allocator, environ_map);
    defer if (default_path.len > 0) allocator.free(default_path);

    const script = if (default_path.len > 0)
        try std.fmt.allocPrint(allocator,
            \\[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
            \\$ofd = New-Object System.Windows.Forms.OpenFileDialog
            \\$ofd.Title = 'Select Minecraft World Folder'
            \\$ofd.InitialDirectory = '{s}'
            \\$ofd.ValidateNames = $false
            \\$ofd.CheckFileExists = $false
            \\$ofd.CheckPathExists = $true
            \\$ofd.FileName = 'Select Folder'
            \\if ($ofd.ShowDialog() -eq 'OK') {{
            \\  Write-Host ([System.IO.Path]::GetDirectoryName($ofd.FileName))
            \\}}
        , .{default_path})
    else
        try allocator.dupe(u8,
            \\[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
            \\$ofd = New-Object System.Windows.Forms.OpenFileDialog
            \\$ofd.Title = 'Select Minecraft World Folder'
            \\$ofd.ValidateNames = $false
            \\$ofd.CheckFileExists = $false
            \\$ofd.CheckPathExists = $true
            \\$ofd.FileName = 'Select Folder'
            \\if ($ofd.ShowDialog() -eq 'OK') {
            \\  Write-Host ([System.IO.Path]::GetDirectoryName($ofd.FileName))
            \\}
        );
    defer allocator.free(script);

    const result = try std.process.run(allocator, io, .{
        .argv = &.{ "powershell", "-NoProfile", "-STA", "-Command", script },
        .create_no_window = false,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const trimmed = std.mem.trim(u8, result.stdout, " \r\n\t");
    if (trimmed.len == 0) return null;

    return try allocator.dupe(u8, trimmed);
}

fn openFolderLinux(allocator: std.mem.Allocator, io: std.Io) !?[]const u8 {
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "zenity", "--file-selection", "--directory", "--title=Select Minecraft World Folder" },
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \r\n\t");
    if (trimmed.len == 0) return null;

    return try allocator.dupe(u8, trimmed);
}

fn getDefaultSavesPathWindows(allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) []const u8 {
    const appdata = environ_map.get("APPDATA") orelse return "";
    return std.fmt.allocPrint(allocator, "{s}\\.minecraft\\saves", .{appdata}) catch return "";
}
