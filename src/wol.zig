//! This module implements Wake-on-LAN (WoL) basic functionality.
//! Author: Riccardo Torreggiani

const std = @import("std");
const network = @import("network");

/// Parse a MAC address string (with separators '-' or ':') into an array of 6 bytes.
pub fn parse_mac(mac: []const u8) ![6]u8 {
    if (mac.len != 17) return error.InvalidMacAddress;

    const sep: u8 = mac[2]; // Expect either ':' or '-'
    if (sep != ':' and sep != '-') return error.InvalidMacAddress;

    // Ensure all separators are the same
    var i: usize = 2;
    while (i < mac.len) : (i += 3) {
        if (mac[i] != sep) return error.InvalidMacAddress;
    }

    var mac_split_iterator = std.mem.tokenizeSequence(u8, mac, &.{sep});
    var mac_octets: [6]u8 = undefined;
    var idx: usize = 0;

    while (mac_split_iterator.next()) |mac_part| {
        if (idx >= 6) return error.InvalidMacAddress;
        mac_octets[idx] = std.fmt.parseInt(u8, mac_part, 16) catch return error.InvalidMacAddress;
        idx += 1;
    }

    if (idx != 6) return error.InvalidMacAddress;

    return mac_octets;
}

test "parse_mac valid cases" {
    try std.testing.expectEqual(parse_mac("01:23:45:67:89:ab"), [6]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab });
    try std.testing.expectEqual(parse_mac("01:23:45:67:89:Ab"), [6]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab });
    try std.testing.expectEqual(parse_mac("01:23:45:67:89:AB"), [6]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab });
    try std.testing.expectEqual(parse_mac("01-23-45-67-89-ab"), [6]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB });
    try std.testing.expectEqual(parse_mac("01-23-45-67-89-Ab"), [6]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB });
    try std.testing.expectEqual(parse_mac("01-23-45-67-89-AB"), [6]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB });
}

test "parse_mac invalid cases" {
    try std.testing.expectError(error.InvalidMacAddress, parse_mac("0123456789AB")); // No separators
    try std.testing.expectError(error.InvalidMacAddress, parse_mac("01:23:45:67:89")); // Too short
    try std.testing.expectError(error.InvalidMacAddress, parse_mac("01:23:45:67:89:AB:CD")); // Too long
    try std.testing.expectError(error.InvalidMacAddress, parse_mac("01:23:45:67:89:GG")); // Invalid hex
    try std.testing.expectError(error.InvalidMacAddress, parse_mac("01-23:45-67:89:AB")); // Mixed separators
    try std.testing.expectError(error.InvalidMacAddress, parse_mac("01::23:45:67:89:AB")); // Extra colon
    try std.testing.expectError(error.InvalidMacAddress, parse_mac("")); // Empty string
}

/// Broadcasts a magic packet to wake up a device with the specified MAC address. Only supports IPv4.
pub fn broadcast_magic_packet(mac: []const u8, port: ?u16, broadcast_address: ?[]const u8) !void {
    // Default address and port if not provided
    const actual_port = port orelse 9;
    const actual_addr = network.Address.IPv4.parse(broadcast_address orelse "255.255.255.255") catch |err| {
        std.debug.print("Invalid broadcast address: {}\n", .{err});
        return err;
    };

    // Parse MAC address to bytes and create magic packet: 6 bytes of 0xFF followed by MAC address repeated 16 times
    const mac_bytes = try parse_mac(mac);
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
    const destEndPoint = network.EndPoint{
        .address = network.Address{ .ipv4 = actual_addr },
        .port = actual_port,
    };

    // Send the magic packet
    _ = sock.sendTo(destEndPoint, &magic_packet) catch |err| {
        std.debug.print("Failed to send wake-on-lan magic packet: {}\n", .{err});
        return err;
    };

    std.debug.print("Sent wake-on-lan magic packet to target MAC {s} via {s}:{}/udp.\n", .{ mac, actual_addr, actual_port });
}
