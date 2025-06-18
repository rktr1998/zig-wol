const std = @import("std");

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

pub fn is_mac_valid(mac: []const u8) bool {
    _ = parse_mac(mac) catch return false;
    return true;
}

test "is_mac_valid" {
    try std.testing.expectEqual(is_mac_valid("01:23:45:67:89:ab"), true);
    try std.testing.expectEqual(is_mac_valid("01-23-45-67-89-ab"), true);
    try std.testing.expectEqual(is_mac_valid("01:23:45:67:89"), false); // Too short
    try std.testing.expectEqual(is_mac_valid("01:23:45:67:89:AB:CD"), false); // Too long
    try std.testing.expectEqual(is_mac_valid("01:23:45:67:89:GG"), false); // Invalid hex
    try std.testing.expectEqual(is_mac_valid("01-23:45-67-89:AB"), false); // Mixed separators
    try std.testing.expectEqual(is_mac_valid("01::23:45:67:89:AB"), false); // Extra colon
    try std.testing.expectEqual(is_mac_valid(""), false); // Empty string
}

pub fn generate_magic_packet(mac_bytes: [6]u8) [102]u8 {
    var packet: [102]u8 = undefined;
    @memset(packet[0..6], 0xFF); // First 6 bytes are 0xFF
    for (0..16) |i| {
        @memcpy(packet[6 + i * 6 .. 6 + (i + 1) * 6], &mac_bytes);
    }
    return packet;
}

/// Broadcasts a magic packet to wake up a device with the specified MAC address.
pub fn broadcast_magic_packet_ipv4(mac: []const u8, port: ?u16, address: ?[]const u8, count: ?u8) !void {
    // Defaults
    const actual_port = port orelse 9;
    const actual_address = try std.net.Address.parseIp(address orelse "255.255.255.255", actual_port);
    const actual_count = count orelse 3; // how man times the magic packet is sent

    // Parse MAC address to bytes and create magic packet: 6 bytes of 0xFF followed by MAC address repeated 16 times
    const mac_bytes = parse_mac(mac) catch |err| {
        std.debug.print("Invalid MAC address: {}\n", .{err});
        return err;
    };
    const magic_packet = generate_magic_packet(mac_bytes);

    // Create a UDP socket
    const socket = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP);
    defer std.posix.close(socket);

    // Enable socket broadcast (setting SO_BROADCAST to anything othen than empty string enables broadcast)
    const option_value: u32 = 1;
    std.posix.setsockopt(socket, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST, std.mem.asBytes(&option_value)) catch |err| {
        std.debug.print("Failed to set socket option to enable broadcast: {}\n", .{err});
        return err;
    };

    // Send the magic packet
    for (0..actual_count) |_| {
        _ = std.posix.sendto(socket, &magic_packet, 0, &actual_address.any, actual_address.getOsSockLen()) catch |err| {
            // std.debug.print("Failed to send to {s}.\n", .{actual_address.in});
            return err;
        };
    }

    std.debug.print("Sent {} magic packet to target MAC {s} via {}/udp.\n", .{ actual_count, mac, actual_address });
}
