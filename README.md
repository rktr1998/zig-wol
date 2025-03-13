# Zig wake-on-lan utility

A simple wake-on-lan utility written in Zig. Wakes up a computer in a LAN given its MAC address.

## Features

- Send WOL magic packets to wake up devices on the LAN.
- Cross-platform support for Windows and Linux.

## Usage

Wake a device on your LAN by broadcasting the magic packet.

```pwsh
zig-wol.exe wake <MAC_ADDRESS>
```

Replace `<MAC_ADDRESS>` with the target MAC address (e.g. `9A-63-A1-FF-8B-4C`).

Run `zig-wol help` to display all subcommands and `zig-wol <subcommand> --help` to display specific options.

## Installation

Pre-compiled binaries are distributed with [releases](https://github.com/rktr1998/zig-wol/releases): download the binary for your architecture and operating system and you are good to go!

### Install latest on Windows using PowerShell

```pwsh
Invoke-RestMethod "https://raw.githubusercontent.com/rktr1998/zig-wol/refs/heads/main/install/install-latest-on-windows.ps1" | Invoke-Expression
```

This command downloads the latest release for your processor architecture and **installs** the program at `C:\Users\%username%\.zig-wol`. To **uninstall** zig-wol you can simply delete this folder.

### Install latest on Linux

```sh
bash <(curl -sSL https://raw.githubusercontent.com/rktr1998/zig-wol/refs/heads/main/install/install-latest-on-linux.sh)
```

This command downloads the latest release for your processor architecture and **installs** the program at `/home/$USER/.zig-wol`. To **uninstall** zig-wol you can simply delete this folder.

## Build

### Prerequisites

- [Zig (v0.14.0)](https://ziglang.org/download/) installed on your system.

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
