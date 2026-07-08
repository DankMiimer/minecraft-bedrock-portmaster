# Minecraft Bedrock port — SD card preparation tool (Windows)
#
# Lays the release zip out on your SD card in the right structure for your
# CFW, and checks your APK on the PC (ABI, split-set completeness, PairIP)
# so the first on-device launch doesn't fail after minutes of extraction.
#
# Usage (interactive):
#   powershell -ExecutionPolicy Bypass -File prepare_sd.ps1
# Usage (scripted):
#   prepare_sd.ps1 -Zip minecraftbedrock-1.3.1.zip -Target E:\ -Cfw muos -Apk mc.apk
param(
    [string]$Zip,
    [string]$Target,
    [ValidateSet('knulli', 'muos', 'rocknix', 'flat', '')]
    [string]$Cfw,
    [string[]]$Apk
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Ok($msg)   { Write-Host $msg -ForegroundColor Green }

# --- Gather inputs -------------------------------------------------------------
if (-not $Zip) {
    $candidates = Get-ChildItem -Path . -Filter 'minecraftbedrock-*.zip' -ErrorAction SilentlyContinue
    if ($candidates.Count -eq 1) { $Zip = $candidates[0].FullName; Info "Using release zip: $Zip" }
    else { $Zip = Read-Host 'Path to the minecraftbedrock release zip' }
}
if (-not (Test-Path $Zip)) { Fail "zip not found: $Zip" }

# Verify checksum when a SHA256SUMS.txt sits next to the zip.
$sumsFile = Join-Path (Split-Path -Parent (Resolve-Path $Zip)) 'SHA256SUMS.txt'
if (Test-Path $sumsFile) {
    $zipName = Split-Path -Leaf $Zip
    $expected = (Get-Content $sumsFile | Where-Object { $_ -match [regex]::Escape($zipName) }) -split '\s+' | Select-Object -First 1
    if ($expected) {
        $actual = (Get-FileHash -Algorithm SHA256 $Zip).Hash.ToLower()
        if ($actual -ne $expected.ToLower()) { Fail "checksum mismatch for $zipName — re-download the release zip" }
        Ok 'Release zip checksum OK.'
    }
}

if (-not $Cfw) {
    Write-Host @'
Which firmware does your handheld run?
  1) Knulli / Batocera   (everything goes into roms/ports/)
  2) muOS                (.sh into ROMS/Ports/, folder into ports/)
  3) ROCKNIX             (everything goes into roms/ports/)
  4) Just extract flat into the target folder
'@
    switch (Read-Host 'Choice [1-4]') {
        '1' { $Cfw = 'knulli' } '2' { $Cfw = 'muos' } '3' { $Cfw = 'rocknix' } default { $Cfw = 'flat' }
    }
}

if (-not $Target) {
    Write-Host 'Target: the SD card root (e.g. E:\).'
    Write-Host 'For Knulli/ROCKNIX this must be the card/partition your device shows as roms storage.'
    Write-Host 'NOTE: if that partition is ext4, Windows cannot write it - use the flat mode onto a'
    Write-Host 'folder and transfer it over the network instead.'
    $Target = Read-Host 'Target drive or folder'
}
if (-not (Test-Path $Target)) { Fail "target not found: $Target" }

# --- APK validation ------------------------------------------------------------
function Test-Apk([string[]]$apkFiles) {
    $hasLib = $false; $hasAssets = $false; $abis = @{}; $pairip = $false
    foreach ($f in $apkFiles) {
        if (-not (Test-Path $f)) { Fail "APK not found: $f" }
        try { $z = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $f)) }
        catch { Fail "corrupt or unreadable APK: $f" }
        try {
            foreach ($e in $z.Entries) {
                if ($e.FullName -match '^lib/([^/]+)/libminecraftpe\.so$') { $hasLib = $true; $abis[$Matches[1]] = $true }
                elseif ($e.FullName -match 'libpairipcore\.so') { $pairip = $true }
                elseif ($e.FullName -match '^assets/(assets/)?resource_packs') { $hasAssets = $true }
            }
        } finally { $z.Dispose() }
    }
    if ($pairip) {
        Fail @'
This APK is a 1.26+ Google Play build with PairIP licensing and cannot run
outside Google Play services. Use a 1.16-1.21 APK instead
(1.16.221.01 or 1.20.x recommended).
'@
    }
    if (-not $hasLib) {
        if ($apkFiles.Count -gt 1 -or $hasAssets) {
            Fail 'No native-library APK in this set. Add split_config.arm64_v8a.apk from the same install.'
        }
        Fail 'This APK contains no Minecraft native libraries (libminecraftpe.so).'
    }
    if (-not ($abis.ContainsKey('arm64-v8a') -or $abis.ContainsKey('armeabi-v7a'))) {
        Fail "APK has no ARM libraries. ABIs found: $($abis.Keys -join ', '). This port needs arm64-v8a (or armeabi-v7a on RK3326 devices)."
    }
    if (-not $hasAssets) {
        Fail 'No assets APK in this set. Add the install-pack split (the large one, often split_install_pack.apk).'
    }
    Ok ("APK OK - ABIs: " + ($abis.Keys -join ', '))
}

if (-not $Apk -or $Apk.Count -eq 0) {
    $answer = Read-Host 'Path to your Bedrock APK (or several split APKs separated by ; — Enter to skip)'
    if ($answer) { $Apk = $answer -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
}
if ($Apk) { Test-Apk $Apk }

# --- Layout --------------------------------------------------------------------
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("mcbedrock_prep_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path $Zip), $staging)
# Zips may nest everything under a single top folder — normalize.
$rootItems = Get-ChildItem $staging
if ($rootItems.Count -eq 1 -and $rootItems[0].PSIsContainer -and
    (Test-Path (Join-Path $rootItems[0].FullName 'minecraftbedrock'))) {
    $staging = $rootItems[0].FullName
}
if (-not (Test-Path (Join-Path $staging 'minecraftbedrock'))) { Fail 'unexpected zip layout: no minecraftbedrock/ folder inside' }

switch ($Cfw) {
    'muos' {
        $shDest  = Join-Path $Target 'ROMS\Ports'
        $dirDest = Join-Path $Target 'ports'
    }
    { $_ -in 'knulli', 'rocknix' } {
        # If the user pointed at the card root, place under roms/ports; if they
        # pointed straight at a ports folder, use it as-is.
        $isPortsDir = (Split-Path -Leaf $Target) -match '^ports$'
        $base = if ($isPortsDir) { $Target } else { Join-Path $Target 'roms\ports' }
        $shDest = $base; $dirDest = $base
    }
    default { $shDest = $Target; $dirDest = $Target }
}
New-Item -ItemType Directory -Force $shDest | Out-Null
New-Item -ItemType Directory -Force $dirDest | Out-Null

Get-ChildItem $staging -Filter '*.sh' | ForEach-Object {
    Copy-Item $_.FullName -Destination $shDest -Force
    Info "  -> $(Join-Path $shDest $_.Name)"
}
Copy-Item (Join-Path $staging 'minecraftbedrock') -Destination $dirDest -Recurse -Force
Info "  -> $(Join-Path $dirDest 'minecraftbedrock')\"

if ($Apk) {
    $apkDest = Join-Path $dirDest 'minecraftbedrock\apk'
    New-Item -ItemType Directory -Force $apkDest | Out-Null
    foreach ($f in $Apk) { Copy-Item $f -Destination $apkDest -Force; Info "  -> APK copied: $(Split-Path -Leaf $f)" }
}

Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue

Ok ''
Ok 'Done. Next steps on the device:'
Ok '  1. Safely eject the SD card and boot the handheld.'
Ok '  2. Refresh the game list and launch "Minecraft Bedrock" from Ports.'
if ($Apk) { Ok '  3. First launch extracts the game (a few minutes). Delete the APK from apk/ afterwards.' }
else      { Ok '  3. Copy your Bedrock APK into ports/minecraftbedrock/apk/ first, then launch.' }
