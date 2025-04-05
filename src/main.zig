const std = @import("std");
const clap = @import("clap");
const wol = @import("wol.zig");
const config = @import("config.zig");

const version = "0.2.0"; // should be read from build.zig.zon at comptime

// Implement the subcommands parser
const SubCommands = enum {
    wake,
    alias,
    list,
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
        \\--addr <str>       IPv4 address, default is broadcast 255.255.255.255.
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
        return std.debug.print("Provide a MAC address or an alias name. Usage: zig-wol wake <MAC> [options]\n", .{});

    var mac = res.positionals[0] orelse return std.debug.print("Provide a MAC address. Usage: zig-wol wake <MAC> [options]\n", .{});

    // if arg is a MAC
    var is_maybe_alias = false;
    _ = wol.parse_mac(mac) catch {
        is_maybe_alias = true;
    };

    // try look for matching alias
    if (is_maybe_alias) {
        const config_zon = config.readConfigFile();
        for (config_zon.aliases) |alias| {
            if (alias.name.len > 0 and std.mem.eql(u8, alias.name, mac)) {
                mac = alias.mac;
                break;
            }
        }
    }

    try wol.broadcast_magic_packet(mac, res.args.port, res.args.addr, null);
}

fn subCommandAlias(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args; // parent args not used

    // The parameters for the subcommand.
    const params = comptime clap.parseParamsComptime(
        \\<str>              Name for the new alias.
        \\<str>              MAC for the new alias.
        \\-h, --help
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

    const name = res.positionals[0] orelse return std.debug.print("Provide name and MAC for the new alias. Usage: zig-wol alias <NAME> <MAC>\n", .{});
    const mac = res.positionals[1] orelse return std.debug.print("Provide a MAC address. Usage: zig-wol alias <NAME> <MAC>\n", .{});

    // ensure mac is valid
    _ = wol.parse_mac(mac) catch |err| {
        return std.debug.print("Invalid MAC address: {}\n", .{err});
    };

    // get config from file, add alias and save config to file
    var config_zon = config.readConfigFile();
    config_zon.addAlias(config.Alias{
        .name = name,
        .mac = mac,
    }) catch |err| {
        return std.debug.print("Failed to add alias: {}\n", .{err});
    };
    config.writeConfigFile(config_zon);

    std.debug.print("New alias added -> AliasName: {s}\tMAC: {s}\n", .{ name, mac });
}

fn subCommandList(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args; // parent args not used

    // The parameters for the subcommand.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help
    );

    // Here we pass the partially parsed argument iterator.
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.report(std.io.getStdErr().writer(), err);
        return err;
    };
    defer res.deinit();

    const config_zon = config.readConfigFile();
    const stdout = std.io.getStdOut().writer();
    for (config_zon.aliases) |alias| {
        if (alias.name.len > 0) {
            try stdout.print("AliasName: {s}\tMAC: {s}\n", .{ alias.name, alias.mac });
        }
    }
}

fn subCommandVersion() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}\n", .{version});
}

fn subCommandHelp() !void {
    const message =
        \\Usage: zig-wol <command> [options]
        \\Commands:
        \\  wake    Wake up a device by its MAC address.
        \\  alias   Manage aliases for MAC addresses. [not implemented]
        \\  list    List all aliases. [not implemented]
        \\  version Display the version of the program.
        \\  help    Display help for the program or a specific command.
        \\
        \\Run 'zig-wol <command> --help' for more information on a specific command.
    ;
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}\n", .{message});
}
