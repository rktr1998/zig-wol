//! This module implements Wake-on-LAN (WoL) basic functionality.
//! Author: Riccardo Torreggiani

const std = @import("std");
const network = @import("network");

/// Parse a MAC address string (with separators '-' or ':') into an array of 6 bytes.
fn parse_mac(mac: []const u8) ![6]u8 {
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

pub fn broadcast_magic_packet(mac: []const u8, port: ?u16) !void {
    // Default port for wake-on-lan if parameter port is null
    const default_udp_port: u16 = 9;

    // Parse MAC address to bytes
    var mac_bytes = try parse_mac(mac);

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
        .port = port orelse default_udp_port,
    };

    // Send the magic packet
    _ = sock.sendTo(destAddr, &magic_packet) catch |err| {
        std.debug.print("Failed to send wake-on-lan magic packet: {}\n", .{err});
        return err; // Exit the program with an error
    };

    std.debug.print("Sent wake-on-lan magic packet to target MAC {s}.\n", .{mac});
}

pub fn config_subcommand_placeholder() !void {
    std.debug.print("config subcommand not implemented.\n", .{});
}

pub fn alias_subcommand_placeholder() !void {
    std.debug.print("alias subcommand not implemented.\n", .{});
}

pub fn list_subcommand_placeholder() !void {
    std.debug.print("list subcommand not implemented.\n", .{});
}
