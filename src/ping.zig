const std = @import("std");
const builtin = @import("builtin");

/// Pings a machine using the system's ping command, returns true if the destination replies.
pub fn ping_with_os_command(destination: []const u8) !void {
    const allocator = std.heap.page_allocator;

    const args = switch (builtin.target.os.tag) {
        .linux, .macos => &[_][]const u8{ "ping", "-c", "1", "-W", "1", destination },
        .windows => &[_][]const u8{ "ping", "-n", "1", "-w", "1000", destination },
        else => @compileError("Unsupported OS"),
    };
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
    });
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    // To use UNICODE on windows we need to set the console code page to UTF-8 (65001)
    // see https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers
    if (builtin.target.os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }

    const unicode_circle_green = "\u{1F7E2}";
    const unicode_circle_red = "\u{1F534}";

    // On Windows "Destination host unreachable" still returns $LASTEXITCODE = 0
    // therefore we must also check the output to catch this case.
    if (result.term.Exited == 0 and
        std.mem.indexOf(u8, result.stdout, "unreachable") == null and
        std.mem.indexOf(u8, result.stderr, "unreachable") == null)
    {
        std.debug.print("{s}  {s}\n", .{ unicode_circle_green, destination });
    } else {
        std.debug.print("{s}  {s}\n", .{ unicode_circle_red, destination });
    }

    // std.debug.print("exit code: {}\n", .{result.term.Exited});
    // std.debug.print("stdout:\n{s}\n", .{result.stdout});
    // std.debug.print("stderr:\n{s}\n", .{result.stderr});

    // return PingResult{
    //     .name = destination,
    //     .alive = result.term.Exited == 0,
    // };
}

// test "ping_with_os_command localhost" {
//     const result = try ping_with_os_command("localhost");

//     try std.testing.expect(result.alive);
//     try std.testing.expect(std.mem.eql(u8, result.name, "localhost"));
// }

// pub const PingResult = struct {
//     name: []const u8,
//     alive: bool,
// };
