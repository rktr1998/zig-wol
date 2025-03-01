# Zig wake-on-lan utility

A simple wake-on-lan utility written in Zig. Wakes up a computer in a LAN given its MAC address.

## Features

- Send WOL magic packets to wake up devices on the LAN.
- Cross-platform support for Windows and Linux.

## Installation

Pre-compiled binaries are distributed with [releases](https://github.com/rktr1998/zig-wol/releases): donwload the binary for your architecture and operating system and you are good to go!

### Install latest on Windows using PowerShell

```pwsh
Invoke-RestMethod "https://raw.githubusercontent.com/rktr1998/zig-wol/refs/heads/main/install/install-latest-on-windows.ps1" | Invoke-Expression
```

### Install latest on Linux

```sh
curl -sSL https://raw.githubusercontent.com/rktr1998/zig-wol/refs/heads/main/install/install-latest-on-linux.sh -o /tmp/zig-wol.sh && chmod +x /tmp/zig-wol.sh && /tmp/zig-wol.sh && rm -f /tmp/zig-wol.sh
```

This command donwloads the latest release for your processor architecture and **installs** the program under `C:\Users\%username%\.zig-wol`.
To **uninstall** zig-wol you can simply delete this folder.

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
