# Zig wake-on-lan utility

A simple wake-on-lan utility written in Zig. Wakes up a computer in a LAN given its MAC address.

## Features

- Send WOL magic packets to wake up devices on the LAN.
- Cross-platform support for Windows and Linux.

## Installation

Pre-compiled binaries are distributed with [releases](https://github.com/rktr1998/zig-wol/releases): donwload the binary for your architecture and operating system and you are good to go!

## Usage

Wake a device on your LAN by broadcasting the magic packet.

```sh
zig-wol.exe <MAC_ADDRESS>
```

Replace `<MAC_ADDRESS>` with the target device's MAC address (e.g. `9A-63-A1-FF-8B-4C`).

Run `zig-wol --help` to display more options.

## Build

### Prerequisites

- [Zig (v0.13.0)](https://ziglang.org/download/) installed on your system.

### 1. Clone the Repository

```sh
git clone https://github.com/rktr1998/zig-wol.git
cd zig-wol
```

### 2. Build the Application

```sh
zig build
```

This command compiles the source code and places the executable in the `zig-out/bin/` directory.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
