#!/bin/bash

repo="rktr1998/zig-wol"
apiUrl="https://api.github.com/repos/$repo/releases/latest"

# Fetch latest release information from GitHub API
latestRelease=$(curl -s $apiUrl)

# Extract the tag name from the JSON response
latestTag=$(echo $latestRelease | grep -oP '"tag_name": "\K[^"]+')

# Detect architecture
arch=$(uname -m)
if [ "$arch" == "x86_64" ]; then
    arch="x86_64"
elif [ "$arch" == "aarch64" ]; then
    arch="aarch64"
else
    echo "Unsupported architecture: $arch"
    exit 1
fi

# OS is Linux
os="linux"

# Preferred archive format
extension="tar.gz"

# Construct asset name and download URL
assetName="zig-wol-$arch-$os.$extension"
downloadUrl="https://github.com/$repo/releases/download/$latestTag/$assetName"

# Define paths
homeDir=$HOME
installDir="$homeDir/.zig-wol"
tempTar="$installDir/$assetName"

# If install directory exists already ask user for fresh install
if [ -d "$installDir" ]; then
    echo "Existing installation detected in: $installDir"
    read -p "Do you want to proceed with a fresh install? Existing configurations will be lost. (y/n): " response
    
    if [ "$response" != "y" ]; then
        echo "Installation aborted."
        exit 0
    fi
    echo "Removing existing installation..."
    rm -rf "$installDir"
fi

# Create install directory
echo "Creating installation directory: $installDir"
mkdir -p "$installDir"

# Download the file
echo "Detected architecture: $arch"
echo "Downloading latest release ($latestTag) from $downloadUrl..."
curl -L $downloadUrl -o "$tempTar"

# Extract the tar file
echo "Extracting archive..."
tar -xzvf "$tempTar" -C "$installDir" --strip-components=1

# Clean up tar file
rm "$tempTar"

echo "Installation completed! Files are in: $installDir"

# Check if path is already in PATH
if ! echo $PATH | grep -q "$installDir"; then
    # Only ask the user if the path is not already in PATH
    read -p "Do you want to add $installDir to your PATH? (y/n): " response
    if [ "$response" == "y" ]; then
        # Append new path with a comment in .bashrc
        echo "Adding $installDir to PATH..."

        # Check if the line already exists in .bashrc
        if ! grep -q "$installDir" "$HOME/.bashrc"; then
            # Insert a comment before adding the path
            echo -e "# zig-wol" >> "$HOME/.bashrc"
            echo "export PATH=\"$installDir:\$PATH\"" >> "$HOME/.bashrc"
            source "$HOME/.bashrc"
            echo "Added $installDir to PATH. Restart your terminal for changes to take effect."
        else
            echo "$installDir is already in .bashrc."
        fi
    else
        echo "To use 'zig-wol', manually add '$installDir' to your PATH."
    fi
else
    echo "$installDir is already in PATH."
fi
