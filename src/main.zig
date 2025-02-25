const std = @import("std");
const network = @import("network");
const clap = @import("clap");

pub fn main() !void {
    // Handle command line arguments parsing
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\--help             Display this help and exit.
        \\--port <u16>       Port to send the magic packet to. Default is 9.
        \\<str>...
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

    var port: u16 = 9;
    if (res.args.port) |p| {
        port = @as(u16, p); // this cast is redundant (clap handles it see above)
    }

    if (res.positionals.len != 1) {
        std.debug.print("Usage: wake-on-lan <MAC>\n", .{});
        return error.InvalidUsage;
    }

    const mac = res.positionals[0];

    // Parse MAC address to bytes
    var mac_bytes: [6]u8 = undefined;
    var mac_split_iterator = std.mem.split(u8, mac, "-");
    var idx: usize = 0;
    while (mac_split_iterator.next()) |mac_part| {
        if (idx >= mac_bytes.len) return error.InvalidMacAddress;
        mac_bytes[idx] = try std.fmt.parseUnsigned(u8, mac_part, 16);
        idx += 1;
    }
    if (idx != 6) return error.InvalidMacAddress;

    // Create magic packet: 6 bytes of 0xFF followed by MAC address repeated 16 times
    var magic_packet: [102]u8 = undefined;
    @memset(magic_packet[0..6], 0xFF);
    for (0..16) |i| {
        @memcpy(magic_packet[6 + i * 6 .. 6 + (i + 1) * 6], &mac_bytes);
    }

    // Initialize network
    try network.init();
    defer network.deinit();

    // Create a UDP socket
    var sock = try network.Socket.create(.ipv4, .udp);
    defer sock.close();
    try sock.setBroadcast(true);

    // Bind to any address, port 0
    try sock.bind(network.EndPoint{
        .address = network.Address{ .ipv4 = network.Address.IPv4.any },
        .port = 0,
    });

    // Destination broadcast address 255.255.255.255:9
    const destAddr = network.EndPoint{
        .address = network.Address{ .ipv4 = network.Address.IPv4.broadcast },
        //.address = network.Address{ .ipv4 = network.Address.IPv4.broadcast },
        .port = port,
    };

    // Send the magic packet
    _ = sock.sendTo(destAddr, &magic_packet) catch |err| {
        std.debug.print("Failed to send wake-on-lan magic packet: {}\n", .{err});
        return err; // Exit the program with an error
    };

    std.debug.print("Sent wake-on-lan magic packet to target MAC {s}.\n", .{mac});
}
