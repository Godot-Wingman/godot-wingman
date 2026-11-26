# Installs Godot Pilot on Windows and adds it to the AI apps on this computer.
#
#   irm https://raw.githubusercontent.com/Albis0/godot-pilot/main/install/install.ps1 | iex
#
# What it does:
# 1. Downloads godot-pilot-windows-x64.exe from the newest GitHub release.
# 2. Checks it against the release's SHA256SUMS file.
# 3. Puts it in %LOCALAPPDATA%\Programs\godot-pilot and adds that folder to your PATH.
# 4. Runs "godot-pilot setup", which adds Godot Pilot to Codex, Claude, Cursor... (a copy
#    of every changed settings file is kept next to it).
#
# A file downloaded this way is not marked as "from the internet", so Windows does not
# show the "unknown app" warning for it.
#
# Options (environment variables):
#   GODOT_PILOT_INSTALL_DIR   install somewhere else
#   GODOT_PILOT_NO_SETUP=1    only download; do not change PATH or AI app settings
#   GITHUB_TOKEN              GitHub token, needed only while the repository is private

$ErrorActionPreference = "Stop"
$Repository = "Albis0/godot-pilot"
$AssetName = "godot-pilot-windows-x64.exe"
$InstallFolder = if ($env:GODOT_PILOT_INSTALL_DIR) { $env:GODOT_PILOT_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\godot-pilot" }
$ExecutablePath = Join-Path $InstallFolder "godot-pilot.exe"
$SkipSetup = $env:GODOT_PILOT_NO_SETUP -eq "1"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "User-Agent" = "godot-pilot-installer"; "Accept" = "application/vnd.github+json" }
if ($env:GITHUB_TOKEN) { $Headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)" }
$DownloadHeaders = $Headers.Clone()
$DownloadHeaders["Accept"] = "application/octet-stream"

Write-Host "Looking for the newest Godot Pilot release..."
$Releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases?per_page=20" -Headers $Headers
$Release = $Releases | Where-Object { -not $_.draft } | Select-Object -First 1
if (-not $Release) { throw "No Godot Pilot release found." }
$ExecutableAsset = $Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
$ChecksumsAsset = $Release.assets | Where-Object { $_.name -eq "SHA256SUMS" } | Select-Object -First 1
if (-not $ExecutableAsset -or -not $ChecksumsAsset) { throw "Release $($Release.tag_name) has no $AssetName or SHA256SUMS." }

New-Item -ItemType Directory -Force -Path $InstallFolder | Out-Null
$DownloadPath = "$ExecutablePath.download"
Write-Host "Downloading Godot Pilot $($Release.tag_name)..."
Invoke-WebRequest -Uri $ExecutableAsset.url -Headers $DownloadHeaders -OutFile $DownloadPath -UseBasicParsing
$ChecksumsPath = Join-Path $InstallFolder "SHA256SUMS"
Invoke-WebRequest -Uri $ChecksumsAsset.url -Headers $DownloadHeaders -OutFile $ChecksumsPath -UseBasicParsing

$ExpectedChecksum = ""
foreach ($Line in Get-Content $ChecksumsPath) {
    $Parts = $Line.Trim() -split "\s+\*?", 2
    if ($Parts.Count -eq 2 -and $Parts[1] -eq $AssetName) { $ExpectedChecksum = $Parts[0].ToLower() }
}
Remove-Item $ChecksumsPath
$ActualChecksum = (Get-FileHash -Algorithm SHA256 -Path $DownloadPath).Hash.ToLower()
if ($ExpectedChecksum -eq "" -or $ActualChecksum -ne $ExpectedChecksum) {
    Remove-Item $DownloadPath
    throw "The download does not match its SHA-256 checksum, so it was not installed. Try again later."
}

# A running program cannot be overwritten, but it can be moved aside.
if (Test-Path $ExecutablePath) { Move-Item -Force $ExecutablePath "$ExecutablePath.old" }
Move-Item -Force $DownloadPath $ExecutablePath
Write-Host "Installed $ExecutablePath"

if ($SkipSetup) { return }

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathEntries = if ($UserPath) { $UserPath -split ";" } else { @() }
if ($PathEntries -notcontains $InstallFolder) {
    $NewUserPath = if ($UserPath) { "$UserPath;$InstallFolder" } else { $InstallFolder }
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
    $env:Path = "$env:Path;$InstallFolder"
    Write-Host "Added $InstallFolder to your PATH (new terminals can run godot-pilot)."
}

& $ExecutablePath setup
