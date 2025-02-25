const std = @import("std");
const network = @import("network");
const clap = @import("clap");

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Parse args into string array
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Ensure correct usage
    if (args.len != 2) {
        return std.debug.print("Usage: {s} <MAC e.g. 00-11-22-33-44-55>\n", .{args[0]});
    }

    // Get the MAC address
    const mac = args[1];

    // Parse MAC address
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
        .port = 9,
    };

    // Send the magic packet
    _ = sock.sendTo(destAddr, &magic_packet) catch |err| {
        std.debug.print("Failed to send wake-on-lan magic packet: {}\n", .{err});
        return err; // Exit the program with an error
    };

    std.debug.print("Sent wake-on-lan magic packet to target MAC {s}.\n", .{mac});
}
