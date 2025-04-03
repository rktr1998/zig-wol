const std = @import("std");
const page_allocator = std.heap.page_allocator;

pub const Alias = struct {
    name: []const u8,
    mac: []const u8,
};

pub const ConfigZon = struct {
    aliases: []Alias,
};

var alias_array = [_]Alias{
    Alias{
        .name = "default-alias",
        .mac = "01-23-45-67-89-ab",
    },
};

pub const default_config_zon = ConfigZon{
    .aliases = alias_array[0..],
};

pub fn readConfigFile() !ConfigZon {
    const config_file_path = getConfigFilePath(page_allocator) catch |err| {
        std.debug.print("Error getting config file path: {}\n", .{err});
        return err;
    };
    defer page_allocator.free(config_file_path);

    // Check if the config file exists and if not create the default config file
    if (!try configFileExists()) {
        std.debug.print("Config file does not exist, creating default config file...\n", .{});
        writeConfigFile(default_config_zon) catch |err| {
            std.debug.print("Error writing default config file: {}\n", .{err});
            return err;
        };
        std.debug.print("Default config file created at {s}\n", .{config_file_path});
        return default_config_zon;
    }

    // Open the config file
    const file = try std.fs.openFileAbsolute(config_file_path, .{ .mode = .read_only });
    defer file.close();

    const file_source = file.readToEndAlloc(page_allocator, 1024 * 1024) catch |err| {
        std.debug.print("Error reading config file: {}\n", .{err});
        return err;
    };
    defer page_allocator.free(file_source);

    // Allocate a new null-terminated slice
    const file_source_nt = try page_allocator.allocSentinel(u8, file_source.len, 0);
    @memcpy(file_source_nt[0..file_source.len], file_source);

    const config_zon = std.zon.parse.fromSlice(ConfigZon, page_allocator, file_source_nt, null, .{}) catch |err| {
        std.debug.print("Error parsing config file: {}\n", .{err});
        return err;
    };

    return config_zon;
}

/// Write the config file in the same directory as the executable. Overwrites if it already exists.
pub fn writeConfigFile(config_zon: ConfigZon) !void {
    const file = std.fs.createFileAbsolute(try getConfigFilePath(page_allocator), .{}) catch |err| {
        std.debug.print("Error creating config file: {}\n", .{err});
        return err;
    };
    defer file.close();
    std.zon.stringify.serialize(config_zon, .{}, file.writer()) catch |err| {
        std.debug.print("Error serializing config file: {}\n", .{err});
        return err;
    };
}

/// Computes the absolute path to the config file in the same directory as the executable.
/// Caller must free the memory after use.
pub fn getConfigFilePath(allocator: std.mem.Allocator) ![]const u8 {
    // get the self executable directory path
    var exe_dir_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir_path = std.fs.selfExeDirPath(&exe_dir_path_buffer) catch |err| {
        std.debug.print("Error getting self executable directory path: {}\n", .{err});
        return err;
    };

    const config_file_path = std.fs.path.join(allocator, &[_][]const u8{
        exe_dir_path,
        "config.zon",
    }) catch |err| {
        std.debug.print("Error joining paths: {}\n", .{err});
        return err;
    };
    return config_file_path;
}

/// Check if the zon config file exists in the same directory as the executable.
/// Internally allocates and frees to compute the path.
pub fn configFileExists() !bool {
    // get the self executable directory path
    const config_file_path = getConfigFilePath(page_allocator) catch |err| {
        std.debug.print("Error getting config file path: {}\n", .{err});
        return err;
    };
    defer page_allocator.free(config_file_path);

    // check if the config file exists
    _ = std.fs.accessAbsolute(config_file_path, .{ .mode = .read_only }) catch {
        return false;
    };
    return true;
}

// some testing...

test "check config file exists in exe dir" {
    std.debug.print("config_file_exists = {}\n", .{try configFileExists()});
}

test "list all entries in cwd dir" {
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        std.debug.print("Entry: {s}\n", .{entry.name});
    }
}

test "list all entries in exe dir" {
    var exe_dir_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir_path = std.fs.selfExeDirPath(&exe_dir_path_buffer) catch |err| {
        std.debug.print("Error getting self executable directory path: {}\n", .{err});
        return err;
    };
    var dir = try std.fs.cwd().openDir(exe_dir_path, .{ .iterate = true });
    defer dir.close();
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        std.debug.print("Entry: {s}\n", .{entry.name});
    }
    std.debug.print("Exe dir path: {s}\n", .{exe_dir_path});
}
