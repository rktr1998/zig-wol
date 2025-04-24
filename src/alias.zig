const std = @import("std");
const ArrayList = std.ArrayList;

pub const Alias = struct {
    name: []const u8,
    mac: []const u8,
    description: []const u8,
};

/// Return the example alias list. Caller must free the memory after use.
fn getExampleAliasList(allocator: std.mem.Allocator) ArrayList(Alias) {
    var alias_list = ArrayList(Alias).init(allocator);

    alias_list.append(Alias{
        .name = "alias-example",
        .mac = "01-01-01-ab-ab-ab",
        .description = "Alias example description.",
    }) catch unreachable;

    return alias_list;
}

test "example alias list (ArrayList)" {
    const allocator = std.heap.page_allocator;
    var alias_list = getExampleAliasList(allocator);
    defer alias_list.deinit();

    try std.testing.expectEqual(alias_list.items.len, 1);
    try std.testing.expectEqual(alias_list.items[0].name, "alias-example");
    try std.testing.expectEqual(alias_list.items[0].mac, "01-01-01-ab-ab-ab");
    try std.testing.expectEqual(alias_list.items[0].description, "Alias example description.");
}

/// Read the alias file in the same directory as the executable. Caller must free the memory after use.
pub fn readAliasFile(allocator: std.mem.Allocator) ArrayList(Alias) {
    const file_path = getAliasFilePath(allocator);
    defer allocator.free(file_path);

    // Check if the alias file exists and if not create the default alias file
    if (!aliasFileExists()) {
        std.debug.print("Alias list file does not exist, creating the default file...\n", .{});
        const example_alias_list = getExampleAliasList(allocator);
        writeAliasFile(example_alias_list);
        return example_alias_list;
    }

    // Open the alias file
    const file = std.fs.openFileAbsolute(file_path, .{ .mode = .read_only }) catch |err| {
        std.debug.print("Error opening alias file: {}\n", .{err});
        unreachable;
    };
    defer file.close();

    const file_source = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        std.debug.print("Error reading alias file: {}\n", .{err});
        unreachable;
    };
    defer allocator.free(file_source);

    // Allocate a new null-terminated slice
    const file_source_nt = allocator.allocSentinel(u8, file_source.len, 0) catch |err| {
        std.debug.print("Error allocating memory for alias file: {}\n", .{err});
        unreachable;
    };
    @memcpy(file_source_nt[0..file_source.len], file_source);

    const alias_list_slice = std.zon.parse.fromSlice([]Alias, allocator, file_source_nt, null, .{}) catch |err| {
        std.debug.print("Error parsing alias file: {}\n", .{err});
        unreachable;
    };

    // Create an ArrayList from the parsed alias slice
    var alias_list = ArrayList(Alias).init(allocator);
    for (alias_list_slice) |alias| {
        alias_list.append(alias) catch |err| {
            std.debug.print("Error appending alias: {}\n", .{err});
            unreachable;
        };
    }

    return alias_list;
}

/// Write the alias file in the same directory as the executable. Overwrites if it already exists.
pub fn writeAliasFile(alias_list: ArrayList(Alias)) void {
    const page_allocator = std.heap.page_allocator;
    const file = std.fs.createFileAbsolute(getAliasFilePath(page_allocator), .{}) catch |err| {
        std.debug.print("Error creating alias file: {}\n", .{err});
        unreachable;
    };
    defer file.close();
    std.zon.stringify.serialize(alias_list.items, .{}, file.writer()) catch |err| {
        std.debug.print("Error serializing alias file: {}\n", .{err});
        unreachable;
    };
}

/// Computes the absolute path to the alias file in the same directory as the executable.
/// Caller must free the memory after use.
pub fn getAliasFilePath(allocator: std.mem.Allocator) []const u8 {
    // get the self executable directory path
    var exe_dir_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir_path = std.fs.selfExeDirPath(&exe_dir_path_buffer) catch |err| {
        std.debug.print("Error getting self executable directory path: {}\n", .{err});
        unreachable;
    };

    const file_path = std.fs.path.join(allocator, &[_][]const u8{
        exe_dir_path,
        "alias.zon",
    }) catch |err| {
        std.debug.print("Error joining paths: {}\n", .{err});
        unreachable;
    };
    return file_path;
}

/// Check if the zon alias file exists in the same directory as the executable.
/// Internally allocates and frees to compute the path.
pub fn aliasFileExists() bool {
    // get the self executable directory path
    const page_allocator = std.heap.page_allocator;
    const file_path = getAliasFilePath(page_allocator);
    defer page_allocator.free(file_path);

    // check if the alias file exists
    _ = std.fs.accessAbsolute(file_path, .{ .mode = .read_only }) catch {
        return false;
    };
    return true;
}

// some testing...

test "check alias file exists in exe dir" {
    std.debug.print("alias_file_exists = {}\n", .{aliasFileExists()});
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
