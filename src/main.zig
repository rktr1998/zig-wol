const std = @import("std");
const builtin = @import("builtin");
const build_zig_zon = @import("build_zig_zon");
const clap = @import("clap"); // third-party lib for cmd line args parsing
const wol = @import("wol"); // local module
const alias = @import("alias.zig"); // local src file
const ping = @import("ping.zig");

const SubCommands = enum {
    wake,
    status,
    alias,
    remove,
    list,
    relay,
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
        try diag.reportToFile(.stderr(), err);
        return subCommandHelp();
    };
    defer res.deinit();

    if (res.positionals.len == 0) {
        return subCommandHelp();
    }

    const subcommand = res.positionals[0] orelse return subCommandHelp();
    switch (subcommand) {
        .wake => try subCommandWake(gpa, &iter, res),
        .status => try subCommandStatus(gpa, &iter, res),
        .alias => try subCommandAlias(gpa, &iter, res),
        .remove => try subCommandRemove(gpa, &iter, res),
        .list => try subCommandList(gpa, &iter, res),
        .relay => try subCommandRelay(gpa, &iter, res),
        .version => try subCommandVersion(),
        .help => try subCommandHelp(),
    }
}

fn subCommandWake(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;

    const params = comptime clap.parseParamsComptime(
        \\<str>               MAC of the device to wake up, or an existing alias name.
        \\--help              Display this help and exit.
        \\--broadcast <str>   IPv4, defaults to 255.255.255.255, setting this may be required in some scenarios.
        \\--port <u16>        UDP port, default 9. Generally irrelevant since wake-on-lan works with OSI layer 2 (Data Link).
        \\--all               Wake up all devices in the alias list.
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    const help_message = "Provide a MAC or an alias name. Usage: zig-wol wake <MAC or ALIAS> [options]\n";

    if (res.args.help != 0)
        return std.debug.print("{s}", .{help_message});

    // if --all is provided, wake up all devices in the alias list
    if (res.args.all != 0) {
        const page_allocator = std.heap.page_allocator;

        var alias_list = alias.readAliasFile(page_allocator);
        defer alias_list.deinit(page_allocator);

        for (alias_list.items) |item| {
            try wol.broadcast_magic_packet_ipv4(item.mac, item.port, item.broadcast, null);
            std.Thread.sleep(100 * std.time.ns_per_ms); // sleep 100ms
        }
        return;
    }

    const mac = res.positionals[0] orelse return std.debug.print("{s}", .{help_message});

    if (wol.is_mac_valid(mac)) {
        return try wol.broadcast_magic_packet_ipv4(mac, res.args.port, res.args.broadcast, null);
    } else {
        const page_allocator = std.heap.page_allocator;

        var alias_list = alias.readAliasFile(page_allocator);
        alias_list.deinit(page_allocator);

        for (alias_list.items) |item| {
            if (item.name.len > 0 and std.mem.eql(u8, item.name, mac)) {
                return try wol.broadcast_magic_packet_ipv4(item.mac, item.port, item.broadcast, null);
            }
        }

        std.debug.print("Provided argument {s} is neither a valid MAC nor an existing alias name.\n", .{mac});
    }
}

fn subCommandStatus(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;

    const params = comptime clap.parseParamsComptime(
        \\--live            Ping continuously.
        \\--help            Display this help and exit.
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    const help_message = "Ping all aliases to check their status. Usage: zig-wol status [--live] [--help]\n";

    if (res.args.help != 0)
        return std.debug.print("{s}", .{help_message});

    const page_allocator = std.heap.page_allocator;
    var alias_list = alias.readAliasFile(page_allocator);
    defer alias_list.deinit(page_allocator);

    var threads = try page_allocator.alloc(std.Thread, alias_list.items.len);
    defer page_allocator.free(threads);

    var is_alive_array = try page_allocator.alloc(bool, alias_list.items.len);
    defer page_allocator.free(is_alive_array);

    // To use UNICODE on windows we need to set the console code page to UTF-8 (65001)
    // see https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers
    if (builtin.target.os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }
    const unicode_circle_green = "\u{1F7E2}";
    const unicode_circle_red = "\u{1F534}";

    //TODO: implement this with async as soon as it comes out and print results ordered instead of randomly...
    var idx: u64 = 0;
    while (true) {
        for (alias_list.items, 0..) |item, i| {
            threads[i] = try std.Thread.spawn(.{}, ping.ping_with_os_command, .{ item.fqdn, &is_alive_array[i] });
        }

        for (threads) |*t| t.join();

        // reset the cursor to the top left before reprinting all lines
        if (res.args.live != 0 and idx != 0) {
            std.debug.print("\u{1B}[{d}A\r", .{alias_list.items.len});
        }

        for (alias_list.items, 0..) |item, i| {
            if (is_alive_array[i]) {
                std.debug.print("{s}  {s}\n", .{ unicode_circle_green, item.name });
            } else {
                std.debug.print("{s}  {s}\n", .{ unicode_circle_red, item.name });
            }
        }
        // move the cursor up N lines and to the left to print again the new list next cycle
        if (res.args.live == 0) {
            break;
        }

        std.Thread.sleep(5 * std.time.ns_per_s); // do not spam too many pings
        idx += 1;
    }
}

fn subCommandAlias(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;

    const params = comptime clap.parseParamsComptime(
        \\<str>                 Name for the new alias.
        \\<str>                 MAC for the new alias.
        \\--broadcast <str>     IPv4, defaults to 255.255.255.255, setting this may be required in some scenarios.
        \\--port <u16>          UDP port, default 9. Generally irrelevant since wake-on-lan works with OSI layer 2 (Data Link).
        \\--fqdn <str>          Fully Qualified Domain Name or IP address. Required to ping for displaying the status.
        \\--description <str>   Description for the new alias.
        \\-h, --help
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    const name = res.positionals[0] orelse return std.debug.print("Provide name and MAC for the new alias. Usage: zig-wol alias <NAME> <MAC>\n", .{});
    const mac = res.positionals[1] orelse return std.debug.print("Provide a MAC. Usage: zig-wol alias <NAME> <MAC>\n", .{});
    const broadcast = res.args.broadcast orelse "255.255.255.255";
    const port = res.args.port orelse 9;
    const fqdn = res.args.fqdn orelse "";
    const description = res.args.description orelse "";

    _ = wol.parse_mac(mac) catch |err| {
        return std.debug.print("Invalid MAC: {}\n", .{err});
    };

    // get config from file, add alias and save config to file
    const page_allocator = std.heap.page_allocator;
    var alias_list = alias.readAliasFile(page_allocator);
    defer alias_list.deinit(page_allocator);

    // check if alias already exists
    for (alias_list.items) |item| {
        if (std.mem.eql(u8, item.name, name)) {
            return std.debug.print("Failed to add alias: name already exists.", .{});
        }
    }

    alias_list.append(page_allocator, alias.Alias{
        .name = name,
        .mac = mac,
        .broadcast = broadcast,
        .port = port,
        .fqdn = fqdn,
        .description = description,
    }) catch |err| {
        return std.debug.print("Failed to add alias: {}\n", .{err});
    };
    alias.writeAliasFile(alias_list);

    std.debug.print("Alias added.\n", .{});
}

fn subCommandRemove(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;

    const params = comptime clap.parseParamsComptime(
        \\<str>?       Name of the alias to be removed.
        \\--all        Remove all aliases.
        \\-h, --help
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    const name = res.positionals[0] orelse "";

    // if --all is provided, remove all aliases
    if (res.args.all != 0) {
        const page_allocator = std.heap.page_allocator;
        var alias_list = alias.readAliasFile(page_allocator);
        const alias_count = alias_list.items.len;
        defer alias_list.deinit(page_allocator);

        alias_list.clearAndFree(page_allocator);
        alias.writeAliasFile(alias_list);
        std.debug.print("Removed {d} aliases.\n", .{alias_count});
        return;
    }

    // if name len is 0 or --help is provided, print help message
    if (name.len == 0 or res.args.help != 0) {
        std.debug.print("Provide an alias name to remove. Usage: zig-wol remove <NAME>\n", .{});
        return std.debug.print("To remove all aliases: zig-wol remove --all\n", .{});
    }

    // finally, if a name is provided, remove the alias
    const page_allocator = std.heap.page_allocator;
    var alias_list = alias.readAliasFile(page_allocator);
    defer alias_list.deinit(page_allocator);

    for (alias_list.items, 0..) |item, idx| {
        if (std.mem.eql(u8, item.name, name)) {
            _ = alias_list.orderedRemove(idx);
            alias.writeAliasFile(alias_list);
            std.debug.print("Alias removed.\n", .{});
            return;
        }
    }
    std.debug.print("Alias not found.\n", .{});
}

fn subCommandList(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;

    const params = comptime clap.parseParamsComptime(
        \\-h, --help
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        std.debug.print("{}", .{err});
        return err;
    };
    defer res.deinit();

    const page_allocator = std.heap.page_allocator;
    var alias_list = alias.readAliasFile(page_allocator);
    defer alias_list.deinit(page_allocator);

    for (alias_list.items) |item| {
        std.debug.print("Name: {s}\nMAC: {s}\nBroadcast: {s}\nPort: {d}\nFQDN: {s}\nDescription: {s}\n\n", .{
            item.name,
            item.mac,
            item.broadcast,
            item.port,
            item.fqdn,
            item.description,
        });
    }
}

fn subCommandRelay(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;

    const params = comptime clap.parseParamsComptime(
        \\--help                  Display this help and exit.
        \\--listen_address <str>  The address to listen on for wake-on-lan packets, for example coming from a router.
        \\--listen_port <u16>     Default 9, the port to listen on for wake-on-lan packets.
        \\--relay_address <str>   The address to relay the packets to, normally the subnet broadcast e.g. 192.168.1.255.
        \\--relay_port <u16>      Default 9, generally irrelevant since wake-on-lan works with OSI layer 2 (Data Link).
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    const help_message =
        \\Relay mode: Listen for Wake-on-LAN packets and forward them to another address.
        \\Usage: zig-wol relay --listen_address <ADDR> --relay_address <ADDR> [--listen_port <PORT>] [--relay_port <PORT>] [--help]
        \\
        \\Options:
        \\  --listen_address <ADDR>   The address to listen on for incoming WOL packets (required).
        \\  --listen_port <PORT>      The port to listen on (default: 9).
        \\  --relay_address <ADDR>    The address to relay WOL packets to (required, usually a broadcast address).
        \\  --relay_port <PORT>       The port to relay packets to (default: 9).
        \\  --help                    Display this help and exit.
        \\
        \\Example:
        \\  zig-wol relay --listen_address 192.168.0.10 --listen_port 9999 --relay_address 192.168.0.255 --relay_port 9
        \\
    ;

    if (res.args.help != 0)
        return std.debug.print("{s}", .{help_message});

    const listen_addr = std.net.Address.resolveIp(res.args.listen_address orelse {
        std.debug.print("A value for the parameter --listen_address must be specified.\n\n", .{});
        return std.debug.print("{s}", .{help_message});
    }, res.args.listen_port orelse 9) catch |err| {
        std.debug.print("Invalid listen address: {}\n\n", .{err});
        return std.debug.print("{s}", .{help_message});
    };

    const relay_addr = std.net.Address.resolveIp(res.args.relay_address orelse {
        std.debug.print("A value for the parameter --relay_address must be specified.\n\n", .{});
        return std.debug.print("{s}", .{help_message});
    }, res.args.relay_port orelse 9) catch |err| {
        std.debug.print("Invalid relay address: {}\n\n", .{err});
        return std.debug.print("{s}", .{help_message});
    };

    wol.relay_begin(listen_addr, relay_addr) catch |err| {
        return std.debug.print("Failed to start relay: {}\n", .{err});
    };
}

fn subCommandVersion() !void {
    const version = try std.SemanticVersion.parse(build_zig_zon.version);
    std.debug.print("{f}\n", .{version});
}

fn subCommandHelp() !void {
    const message =
        \\Usage: zig-wol <command> [options]
        \\Commands:
        \\  wake      Wake up a device by its MAC.
        \\  status    Ping all aliases.
        \\  alias     Create an alias for a MAC, optionally specify a broadcast, FQDN and more.
        \\  remove    Remove an alias by name.
        \\  list      List all aliases.
        \\  relay     Start listening for wol packets and relay them.
        \\  version   Display the version of the program.
        \\  help      Display help for the program or a specific command.
        \\
        \\Run 'zig-wol <command> --help' for more information on a specific command.
        \\
    ;
    std.debug.print("{s}\n", .{message});
}
