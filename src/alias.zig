const std = @import("std");
const ArrayList = std.ArrayList;

pub const Alias = struct {
    name: []const u8,
    mac: []const u8,
    broadcast: []const u8,
    port: u16,
    fqdn: []const u8,
    description: []const u8,
};

/// Return the example alias list. Caller must free the memory after use.
fn getExampleAliasList(allocator: std.mem.Allocator) ArrayList(Alias) {
    var alias_list = ArrayList(Alias).initCapacity(allocator, 0) catch @panic("OutOfMemory");

    alias_list.append(allocator, Alias{
        .name = "alias-example-unreachable",
        .mac = "01-01-01-ab-ab-ab",
        .broadcast = "255.255.255.255",
        .port = 9,
        .fqdn = "alias-example.unreachable-by-ping",
        .description = "Alias example. Works with WOL but cannot be pinged.",
    }) catch unreachable;

    alias_list.append(allocator, Alias{
        .name = "alias-example-localhost",
        .mac = "00-00-00-00-00-00",
        .broadcast = "255.255.255.255",
        .port = 9,
        .fqdn = "localhost",
        .description = "Alias example. Can be pinged successfully when using the subcommand status. Does not support WOL.",
    }) catch unreachable;

    return alias_list;
}

/// Read the alias file in the same directory as the executable. Caller must free the memory after use.
/// Allocates internally.
pub fn readAliasFile(allocator: std.mem.Allocator, io: std.Io) ArrayList(Alias) {
    const file_path = getAliasFilePath(allocator);
    defer allocator.free(file_path);

    if (!aliasFileExists(allocator)) {
        std.debug.print("Alias list file does not exist, creating the default file...\n", .{});
        const example_alias_list = getExampleAliasList(allocator);
        writeAliasFile(allocator, example_alias_list);
        return example_alias_list;
    }

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
    defer allocator.free(file_source_nt);

    @memcpy(file_source_nt[0..file_source.len], file_source);

    // Zon parsing
    const alias_list_slice = std.zon.parse.fromSlice([]Alias, allocator, file_source_nt, null, .{}) catch |err| {
        std.debug.print("Error parsing alias file: {}\n", .{err});
        unreachable;
    };

    // Create the alias list and fill with default items
    var alias_list = ArrayList(Alias).initCapacity(allocator, alias_list_slice.len) catch |err| {
        std.debug.print("Error allocating memory for alias list: {}\n", .{err});
        unreachable;
    };

    for (alias_list_slice) |item| {
        alias_list.append(allocator, item) catch |err| {
            std.debug.print("Error appending to alias list: {}\n", .{err});
            unreachable;
        };
    }

    return alias_list;
}

test "readAliasFile" {
    const page_allocator = std.heap.page_allocator;

    var alias_list = readAliasFile(page_allocator);
    defer alias_list.deinit(page_allocator);

    try std.testing.expect(alias_list.items.len >= 1);

    std.debug.print("First alias: {s}, {s}, {s}\n", .{ alias_list.items[0].name, alias_list.items[0].mac, alias_list.items[0].description });

    try std.testing.expect(std.mem.eql(u8, alias_list.items[0].name, "alias-example-unreachable"));
    try std.testing.expect(std.mem.eql(u8, alias_list.items[0].mac, "01-01-01-ab-ab-ab"));
}

/// Write the alias file in the same directory as the executable. Overwrites if it already exists.
pub fn writeAliasFile(allocator: std.mem.Allocator, alias_list: ArrayList(Alias)) void {
    const file_path = getAliasFilePath(allocator);
    defer allocator.free(file_path);

    const file = std.fs.createFileAbsolute(file_path, .{}) catch |err| {
        std.debug.print("Error creating alias file: {}\n", .{err});
        unreachable;
    };
    defer file.close();

    var buf: [1024]u8 = undefined;
    var writer = std.fs.File.writer(file, &buf);
    const writer_interface = &writer.interface;
    defer writer_interface.flush() catch @panic("stdout flush failed");

    std.zon.stringify.serialize(alias_list.items, .{}, writer_interface) catch |err| {
        std.debug.print("Error serializing alias file: {}\n", .{err});
        unreachable;
    };
}

test "writeAliasFile" {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const gpa = da.allocator();

    var alias_list = getExampleAliasList(gpa);
    defer alias_list.deinit(gpa);

    writeAliasFile(gpa, alias_list);
}

/// Computes the absolute path to the alias file in the same directory as the executable.
/// Caller must free the memory after use.
pub fn getAliasFilePath(allocator: std.mem.Allocator) []u8 {
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

test "getAliasFilePath" {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const gpa = da.allocator();

    const file_path = getAliasFilePath(gpa);
    defer gpa.free(file_path);

    std.debug.print("Alias file path: {s}\n", .{file_path});
}

/// Check if the zon alias file exists in the same directory as the executable.
/// Internally allocates and frees to compute the path.
pub fn aliasFileExists(allocator: std.mem.Allocator) bool {
    const file_path = getAliasFilePath(allocator);
    defer allocator.free(file_path);

    _ = std.fs.accessAbsolute(file_path, .{ .read = true }) catch {
        return false;
    };

    return true;
}

test "aliasFileExists" {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const gpa = da.allocator();

    _ = aliasFileExists(gpa);
}
