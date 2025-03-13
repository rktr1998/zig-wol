const std = @import("std");
const clap = @import("clap");
const wol = @import("wol.zig");

const version = "0.1.2"; // should be read from build.zig.zon at comptime

// Implement the subcommands parser
const SubCommands = enum {
    wake,
    alias,
    list,
    config,
    version,
    help,
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
    // Initialize allocator for the command line arguments parsing
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
    const subcommand = res.positionals[0] orelse return subCommandHelp();
    switch (subcommand) {
        .wake => try subCommandWake(gpa, &iter, res),
        .alias => try subCommandAlias(gpa, &iter, res),
        .list => try subCommandList(gpa, &iter, res),
        .config => try subCommandConfig(gpa, &iter, res),
        .version => try subCommandVersion(),
        .help => try subCommandHelp(),
    }
}

fn subCommandWake(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args; // parent args not used

    // The parameters for the subcommand.
    const params = comptime clap.parseParamsComptime(
        \\<str>              MAC address of the device to wake up.
        \\--help             Display this help and exit.
        \\--port <u16>       UDP port, default 9. This is generally irrelevant since wake-on-lan works with OSI layer 2 (Data Link).
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
        return std.debug.print("Provide a MAC address. Usage: zig-wol wake <MAC> [options]\n", .{});

    const mac = res.positionals[0] orelse return std.debug.print("Provide a MAC address. Usage: zig-wol wake <MAC> [options]\n", .{});

    try wol.broadcast_magic_packet(mac, res.args.port);
}

fn subCommandAlias(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
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

    try wol.alias_subcommand_placeholder();
}

fn subCommandList(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
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

    try wol.list_subcommand_placeholder();
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

    try wol.config_subcommand_placeholder();
}

fn subCommandVersion() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(version, .{});
}

fn subCommandHelp() !void {
    const message =
        \\Usage: zig-wol <command> [options]
        \\Commands:
        \\  wake    Wake up a device by its MAC address.
        \\  alias   Manage aliases for MAC addresses. [not implemented]
        \\  list    List all aliases. [not implemented]
        \\  config  Configure the program. [not implemented]
        \\  version Display the version of the program.
        \\  help    Display help for the program or a specific command.
        \\
        \\Run 'zig-wol <command> --help' for more information on a specific command.
    ;
    const stdout = std.io.getStdOut().writer();
    try stdout.print(message, .{});
}
