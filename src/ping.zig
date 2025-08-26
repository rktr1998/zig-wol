const std = @import("std");
const builtin = @import("builtin");

/// Pings a machine using the system's ping command, returns true if the destination replies.
pub fn ping_with_os_command(alias_fqdn: []const u8, is_alive: *bool) !void {
    const allocator = std.heap.page_allocator;

    const args = switch (builtin.target.os.tag) {
        .linux, .macos => &[_][]const u8{ "ping", "-c", "1", "-W", "1", alias_fqdn },
        .windows => &[_][]const u8{ "ping", "-n", "1", "-w", "1000", alias_fqdn },
        else => @compileError("Unsupported OS"),
    };
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
    });
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    if (result.term.Exited == 0 and
        std.mem.indexOf(u8, result.stdout, "unreachable") == null and
        std.mem.indexOf(u8, result.stderr, "unreachable") == null)
    {
        is_alive.* = true;
    } else {
        is_alive.* = false;
    }
}
