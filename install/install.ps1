# Installs Godot Wingman on Windows and adds it to the AI apps on this computer.
#
#   irm https://raw.githubusercontent.com/Albis0/godot-wingman/main/install/install.ps1 | iex
#
# What it does:
# 1. Looks for Bun (https://bun.sh). When it is missing, installs it with Bun's own
#    installer. With Bun, Godot Wingman is one small file (godot-wingman.js, about 1-2 MB).
#    When Bun cannot be used, it downloads the single-file program instead (about 100 MB,
#    with Bun built in).
# 2. Checks the download against the release's SHA256SUMS file.
# 3. Puts it in %LOCALAPPDATA%\Programs\godot-wingman and adds that folder to your PATH,
#    so "godot-wingman" works in new terminals.
# 4. Runs "godot-wingman setup", which adds Godot Wingman to Codex, Claude, Cursor... (a copy
#    of every changed settings file is kept next to it).
#
# Files downloaded this way are not marked as "from the internet", so Windows does not
# show the "unknown app" warning for them.
#
# Options (environment variables):
#   GODOT_WINGMAN_INSTALL_DIR        install somewhere else
#   GODOT_WINGMAN_USE_EXECUTABLE=1   always use the single-file program; never install Bun
#   GODOT_WINGMAN_NO_SETUP=1         only download; do not change PATH or AI app settings
#   GITHUB_TOKEN                     GitHub token, needed only while the repository is private

$ErrorActionPreference = "Stop"
$Repository = "Albis0/godot-wingman"
$ExecutableAssetName = "godot-wingman-windows-x64.exe"
$BundleAssetName = "godot-wingman.js"
# The bundle is built and tested with this Bun version or newer.
$MinimumBunVersion = [version]"1.3.0"
$InstallFolder = if ($env:GODOT_WINGMAN_INSTALL_DIR) { $env:GODOT_WINGMAN_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\godot-wingman" }
$ExecutablePath = Join-Path $InstallFolder "godot-wingman.exe"
$BundlePath = Join-Path $InstallFolder $BundleAssetName
$LauncherPath = Join-Path $InstallFolder "godot-wingman.cmd"
$SkipSetup = $env:GODOT_WINGMAN_NO_SETUP -eq "1"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "User-Agent" = "godot-wingman-installer"; "Accept" = "application/vnd.github+json" }
if ($env:GITHUB_TOKEN) { $Headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)" }
$DownloadHeaders = $Headers.Clone()
$DownloadHeaders["Accept"] = "application/octet-stream"

# The full path of a Bun that is new enough, or $null.
function Find-Bun {
    $Candidates = @()
    $OnPath = Get-Command bun -ErrorAction SilentlyContinue
    if ($OnPath) { $Candidates += $OnPath.Source }
    $Candidates += Join-Path $env:USERPROFILE ".bun\bin\bun.exe"
    foreach ($Candidate in $Candidates) {
        if (-not (Test-Path $Candidate)) { continue }
        try {
            $VersionText = (& $Candidate --version).Trim() -replace "-.*$", ""
            if ([version]$VersionText -ge $MinimumBunVersion) { return $Candidate }
            Write-Host "Bun $VersionText is older than $MinimumBunVersion."
        } catch { }
    }
    return $null
}

# Downloads a release file and checks it against SHA256SUMS. Throws when they differ.
function Save-CheckedAsset($AssetName, $TargetPath) {
    $Asset = $Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
    if (-not $Asset) { throw "Release $($Release.tag_name) has no $AssetName." }
    $DownloadPath = "$TargetPath.download"
    Invoke-WebRequest -Uri $Asset.url -Headers $DownloadHeaders -OutFile $DownloadPath -UseBasicParsing
    $ActualChecksum = (Get-FileHash -Algorithm SHA256 -Path $DownloadPath).Hash.ToLower()
    if (-not $Checksums.ContainsKey($AssetName) -or $ActualChecksum -ne $Checksums[$AssetName]) {
        Remove-Item $DownloadPath
        throw "The download of $AssetName does not match its SHA-256 checksum, so it was not installed. Try again later."
    }
    # A running program cannot be overwritten, but it can be moved aside.
    if (Test-Path $TargetPath) { Move-Item -Force $TargetPath "$TargetPath.old" }
    Move-Item -Force $DownloadPath $TargetPath
}

Write-Host "Looking for the newest Godot Wingman release..."
$Releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases?per_page=20" -Headers $Headers
$Release = $Releases | Where-Object { -not $_.draft } | Select-Object -First 1
if (-not $Release) { throw "No Godot Wingman release found." }
$ChecksumsAsset = $Release.assets | Where-Object { $_.name -eq "SHA256SUMS" } | Select-Object -First 1
if (-not $ChecksumsAsset) { throw "Release $($Release.tag_name) has no SHA256SUMS." }
$ChecksumsText = (Invoke-WebRequest -Uri $ChecksumsAsset.url -Headers $DownloadHeaders -UseBasicParsing).Content
if ($ChecksumsText -is [byte[]]) { $ChecksumsText = [Text.Encoding]::UTF8.GetString($ChecksumsText) }
$Checksums = @{}
foreach ($Line in ($ChecksumsText -split "`n")) {
    $Parts = $Line.Trim() -split "\s+\*?", 2
    if ($Parts.Count -eq 2) { $Checksums[$Parts[1]] = $Parts[0].ToLower() }
}

New-Item -ItemType Directory -Force -Path $InstallFolder | Out-Null

$BunPath = $null
if ($env:GODOT_WINGMAN_USE_EXECUTABLE -ne "1" -and $Checksums.ContainsKey($BundleAssetName)) {
    $BunPath = Find-Bun
    if (-not $BunPath) {
        Write-Host "Installing Bun (https://bun.sh), which runs Godot Wingman..."
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://bun.sh/install.ps1 | iex" | Out-Host
        } catch {
            Write-Host "Bun could not be installed: $_"
        }
        $BunPath = Find-Bun
    }
}

if ($BunPath) {
    Write-Host "Downloading Godot Wingman $($Release.tag_name) (small version for Bun)..."
    Save-CheckedAsset $BundleAssetName $BundlePath
    Set-Content -Path $LauncherPath -Encoding ASCII -Value "@`"$BunPath`" `"%~dp0$BundleAssetName`" %*"
    # An executable from an earlier install would be found before the .cmd launcher.
    if (Test-Path $ExecutablePath) { Move-Item -Force $ExecutablePath "$ExecutablePath.old" }
    $RunCommand = @($BunPath, $BundlePath)
    Write-Host "Installed $BundlePath (run by $BunPath)"
} else {
    Write-Host "Downloading Godot Wingman $($Release.tag_name) (single-file program, about 100 MB)..."
    Save-CheckedAsset $ExecutableAssetName $ExecutablePath
    if (Test-Path $LauncherPath) { Remove-Item -Force $LauncherPath }
    $RunCommand = @($ExecutablePath)
    Write-Host "Installed $ExecutablePath"
}

if ($SkipSetup) { return }

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathEntries = if ($UserPath) { $UserPath -split ";" } else { @() }
if ($PathEntries -notcontains $InstallFolder) {
    $NewUserPath = if ($UserPath) { "$UserPath;$InstallFolder" } else { $InstallFolder }
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
    $env:Path = "$env:Path;$InstallFolder"
    Write-Host "Added $InstallFolder to your PATH (new terminals can run godot-wingman)."
}

$Program = $RunCommand[0]
$ProgramArguments = @($RunCommand | Select-Object -Skip 1) + @("setup")
& $Program @ProgramArguments
