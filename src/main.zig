const std = @import("std");
const network = @import("network");
const clap = @import("clap");
const wol = @import("wol.zig");

pub fn main() !void {
    // Handle command line arguments parsing
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\<str>              MAC address of the device to wake up.
        \\--help             Display this help and exit.
        \\--port <u16>       UDP port, default 9. This is generally irrelevant since wake-on-lan works with OSI layer 2 (Data Link), see https://en.wikipedia.org/wiki/Wake-on-LAN#Magic_packet).
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        // Report useful error and exit.
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    if (res.positionals.len != 1) {
        std.debug.print("Invalid number of arguments.\n", .{});
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    try wol.broadcast_magic_packet(res.positionals[0], res.args.port);
}
