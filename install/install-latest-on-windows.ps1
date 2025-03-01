$repo = "rktr1998/zig-wol"
$apiUrl = "https://api.github.com/repos/$repo/releases/latest"

# Fetch latest release information from GitHub API
$latestRelease = Invoke-RestMethod -Uri $apiUrl
$latestTag = $latestRelease.tag_name

# Detect architecture
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -eq "AMD64") {
    $arch = "x86_64"
} elseif ($arch -eq "ARM64") {
    $arch = "aarch64"
} else {
    Write-Host "Unsupported architecture: $arch"
    exit 1
}

# OS is Windows since it's PowerShell
$os = "windows"

# Preferred archive format
$extension = "zip"

# Construct asset name and download URL
$assetName = "zig-wol-$arch-$os.$extension"
$downloadUrl = "https://github.com/$repo/releases/download/$latestTag/$assetName"

# Define paths
$homeDir = [System.Environment]::GetFolderPath("UserProfile")
$installDir = "$homeDir\.zig-wol"
$tempZip = "$installDir\$assetName"

# If install directory exists already ask user for fresh install
if (Test-Path $installDir) {
    Write-Host "Existing installation detected in: $installDir"
    $response = Read-Host "Do you want to proceed with a fresh install? Existing configurations will be lost. (y/n)"
    if ($response -ne "y") {
        Write-Host "Installation aborted."
        exit 0
    }
    Write-Host "Removing existing installation..."
    Remove-Item -Recurse -Force $installDir
}

# Create install directory
Write-Host "Creating installation directory: $installDir"
New-Item -ItemType Directory -Path $installDir | Out-Null

# Download the file
Write-Host "Detected architecture: $arch"
Write-Host "Downloading latest release ($latestTag) from $downloadUrl..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip

# Extract the zip file
Write-Host "Extracting archive..."
Expand-Archive -Path $tempZip -DestinationPath $installDir -Force

# Clean up zip file
Remove-Item $tempZip

Write-Host "Installation completed! Files are in: $installDir"
Write-Host "To use 'zig-wol', consider adding '$installDir' to your PATH."

# Add to PATH but ask user first
$response = Read-Host "Do you want to add $installDir to your PATH? (y/n)"
if ($response -eq "y") {
    # Fetch current user PATH
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Check if path is already in PATH
    if ($currentPath -notlike "*$installDir*") {
        # Append new path
        $newPath = "$currentPath;$installDir"
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Added $installDir to PATH. Restart your terminal or log out/in for changes to take effect."
    } else {
        Write-Host "$installDir is already in PATH."
    }
} else {
    Write-Host "To use 'zig-wol', manually add '$installDir' to your PATH."
}
