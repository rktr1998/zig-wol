const std = @import("std");
const page_allocator = std.heap.page_allocator;

pub const Alias = struct {
    name: []const u8,
    mac: []const u8,
};

pub const ConfigZon = struct {
    const max_aliases = 64;
    aliases: [max_aliases]Alias = undefined,
    alias_count: usize = 0,

    pub fn addAlias(self: *ConfigZon, alias: Alias) !void {
        if (self.alias_count >= max_aliases) {
            return error.AliasArrayFull;
        }
        self.aliases[self.alias_count] = alias;
        self.alias_count += 1;
    }

    pub fn getAliases(self: *const ConfigZon) []const Alias {
        return self.aliases[0..self.alias_count];
    }
};

var default_aliases = [_]Alias{
    Alias{
        .name = "default-alias",
        .mac = "01-23-45-67-89-ab",
    },
    Alias{
        .name = "another-alias",
        .mac = "01-23-45-67-89-cd",
    },
};

pub fn getDefaultConfigZon() ConfigZon {
    var config_zon = ConfigZon{};
    config_zon.addAlias(Alias{
        .name = "default-alias",
        .mac = "01-23-45-67-89-ab",
    }) catch |err| {
        std.debug.print("Error adding default alias: {}\n", .{err});
        unreachable;
    };
    config_zon.addAlias(Alias{
        .name = "another-alias",
        .mac = "01-23-45-67-89-cd",
    }) catch |err| {
        std.debug.print("Error adding default alias: {}\n", .{err});
        unreachable;
    };
    return config_zon;
}

pub fn readConfigFile() ConfigZon {
    const config_file_path = getConfigFilePath(page_allocator);
    defer page_allocator.free(config_file_path);

    // Check if the config file exists and if not create the default config file
    if (!configFileExists()) {
        std.debug.print("Config file does not exist, creating default config file...\n", .{});
        writeConfigFile(getDefaultConfigZon());
        return getDefaultConfigZon();
    }

    // Open the config file
    const file = std.fs.openFileAbsolute(config_file_path, .{ .mode = .read_only }) catch |err| {
        std.debug.print("Error opening config file: {}\n", .{err});
        unreachable;
    };
    defer file.close();

    const file_source = file.readToEndAlloc(page_allocator, 1024 * 1024) catch |err| {
        std.debug.print("Error reading config file: {}\n", .{err});
        unreachable;
    };
    defer page_allocator.free(file_source);

    // Allocate a new null-terminated slice
    const file_source_nt = page_allocator.allocSentinel(u8, file_source.len, 0) catch |err| {
        std.debug.print("Error allocating memory for config file: {}\n", .{err});
        unreachable;
    };
    @memcpy(file_source_nt[0..file_source.len], file_source);

    const config_zon = std.zon.parse.fromSlice(ConfigZon, page_allocator, file_source_nt, null, .{}) catch |err| {
        std.debug.print("Error parsing config file: {}\n", .{err});
        unreachable;
    };

    return config_zon;
}

/// Write the config file in the same directory as the executable. Overwrites if it already exists.
pub fn writeConfigFile(config_zon: ConfigZon) void {
    const file = std.fs.createFileAbsolute(getConfigFilePath(page_allocator), .{}) catch |err| {
        std.debug.print("Error creating config file: {}\n", .{err});
        unreachable;
    };
    defer file.close();
    std.zon.stringify.serialize(config_zon, .{}, file.writer()) catch |err| {
        std.debug.print("Error serializing config file: {}\n", .{err});
        unreachable;
    };
    std.debug.print("Config file written successfully.\n", .{});
}

/// Computes the absolute path to the config file in the same directory as the executable.
/// Caller must free the memory after use.
pub fn getConfigFilePath(allocator: std.mem.Allocator) []const u8 {
    // get the self executable directory path
    var exe_dir_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir_path = std.fs.selfExeDirPath(&exe_dir_path_buffer) catch |err| {
        std.debug.print("Error getting self executable directory path: {}\n", .{err});
        unreachable;
    };

    const config_file_path = std.fs.path.join(allocator, &[_][]const u8{
        exe_dir_path,
        "config.zon",
    }) catch |err| {
        std.debug.print("Error joining paths: {}\n", .{err});
        unreachable;
    };
    return config_file_path;
}

/// Check if the zon config file exists in the same directory as the executable.
/// Internally allocates and frees to compute the path.
pub fn configFileExists() bool {
    // get the self executable directory path
    const config_file_path = getConfigFilePath(page_allocator);
    defer page_allocator.free(config_file_path);

    // check if the config file exists
    _ = std.fs.accessAbsolute(config_file_path, .{ .mode = .read_only }) catch {
        return false;
    };
    return true;
}

// some testing...

test "check config file exists in exe dir" {
    std.debug.print("config_file_exists = {}\n", .{configFileExists()});
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
