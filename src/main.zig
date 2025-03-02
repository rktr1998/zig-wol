const std = @import("std");
const clap = @import("clap");
const wol = @import("wol.zig");

// Implement the subcommands parser
const SubCommands = enum {
    help,
    wake,
    config,
};
const main_parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
};
const main_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<command>
    \\
);
const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);

/// Entry point of zig-wol.exe
pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    var iter = try std.process.ArgIterator.initWithAllocator(gpa);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
        .terminating_positional = 0,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return subCommandHelp();
    };
    defer res.deinit();

    // If no subcommand is provided, print the subcommand help message and exit.
    if (res.positionals.len == 0) {
        return subCommandHelp();
    }

    // If a subcommand is provided, parse it and execute the corresponding subcommand handler
    const command = res.positionals[0] orelse return subCommandHelp();
    switch (command) {
        .help => try subCommandHelp(),
        .wake => try subCommandWake(gpa, &iter, res),
        .config => try subCommandConfig(gpa, &iter, res),
    }
}

fn subCommandHelp() !void {
    std.debug.print("Usage: zig-wol <command> [options]\n", .{});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  help    Display help for the program or a specific command.\n", .{});
    std.debug.print("  wake    Wake up a device using Wake-on-LAN.\n", .{});
    std.debug.print("  config  Configure the program.\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Run 'zig-wol <command> --help' for more information on a command.\n", .{});
    return;
}

fn subCommandWake(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args; // parent args not used

    // The parameters for the subcommand.
    const params = comptime clap.parseParamsComptime(
        \\<str>              MAC address of the device to wake up.
        \\--help             Display this help and exit.
        \\--port <u16>       UDP port, default 9. This is generally irrelevant since wake-on-lan works with OSI layer 2 (Data Link), see https://en.wikipedia.org/wiki/Wake-on-LAN#Magic_packet).
        \\
    );

    // Here we pass the partially parsed argument iterator.
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        std.debug.print("--help\n", .{});

    const mac = res.positionals[0] orelse return std.debug.print("Provide a MAC address. Usage: zig-wol wake <MAC> [options]\n", .{});

    try wol.broadcast_magic_packet(mac, res.args.port);
}

fn subCommandConfig(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args; // parent args not used

    // The parameters for the subcommand.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help  Display help for subCommandConfig.
    );

    // Here we pass the partially parsed argument iterator.
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    try wol.config_placeholder();
}
