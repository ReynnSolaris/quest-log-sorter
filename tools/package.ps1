<#
  Builds a mod archive that Vortex, MO2 and manual installers all accept.

  Vortex installs a Fallout 4 mod by copying the archive's contents into Data,
  so the archive must be rooted at Data's *contents* - F4SE\ and Interface\ at
  the top level, with no wrapping Data\ folder. Get that wrong and Vortex
  either flags it as unrecognised or deploys files one directory too deep,
  which looks exactly like "the mod does nothing".

  Usage:
      .\tools\package.ps1
      .\tools\package.ps1 -Version 1.1.0 -IncludeDataPage
#>

param(
    [string]$Version = "1.0.0",
    [string]$Config  = "releasedbg",

    # Pipboy_DataPage.swf is a modified Bethesda asset and conflicts with any
    # other mod touching it, so it is opt-in rather than bundled by default.
    [switch]$IncludeDataPage
)

$ErrorActionPreference = "Stop"

$root    = Split-Path $PSScriptRoot -Parent
$staging = Join-Path $root "dist\staging"
$distDir = Join-Path $root "dist"
$archive = Join-Path $distDir "QuestLogSorter-$Version.zip"

# --- locate the built DLL -------------------------------------------------
# Search all of build\ rather than assuming a config directory. xmake names the
# output folder after the active mode, which is "release" by default but
# "releasedbg" or "debug" if you configured one - and the script has no
# business caring which.
$candidates = @(Get-ChildItem -Path (Join-Path $root "build") -Filter "QuestLogSorter.dll" `
                -Recurse -File -ErrorAction SilentlyContinue)

if ($candidates.Count -eq 0) {
    throw "QuestLogSorter.dll not found anywhere under build\. Run 'xmake build' first."
}

# Prefer the requested config if it is actually there, else newest wins.
$preferred = $candidates | Where-Object { $_.FullName -like "*\$Config\*" }
if ($preferred) {
    $dll = $preferred | Sort-Object LastWriteTime -Descending | Select-Object -First 1
} else {
    $dll = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

$dllRel = $dll.FullName.Substring($root.Length + 1)
Write-Host "Using $dllRel  ($($dll.LastWriteTime))" -ForegroundColor Cyan

if ($candidates.Count -gt 1) {
    Write-Host "  ($($candidates.Count) builds present - picked the newest; pass -Config to force one)" -ForegroundColor Yellow
}

# A DLL older than the sources is the classic way to ship a stale build.
$newestSource = Get-ChildItem -Path (Join-Path $root "src") -Recurse -File |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($newestSource -and $newestSource.LastWriteTime -gt $dll.LastWriteTime) {
    Write-Host "  WARNING: src\$($newestSource.Name) is newer than the DLL - rebuild before shipping." -ForegroundColor Red
}

$swf     = Join-Path $root "data\Interface\QuestLogSorter\QLS.swf"
$groups  = Join-Path $root "data\F4SE\Plugins\QuestLogSorter\groups.json"
$dataPage= Join-Path $root "data\Interface\Pipboy_DataPage.swf"

if (-not (Test-Path $swf))    { throw "QLS.swf not found. Run swf\build.ps1 first." }
if (-not (Test-Path $groups)) { throw "groups.json missing from data\F4SE\Plugins\QuestLogSorter\." }

# --- stage ----------------------------------------------------------------
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }

New-Item -ItemType Directory -Force -Path "$staging\F4SE\Plugins\QuestLogSorter" | Out-Null
New-Item -ItemType Directory -Force -Path "$staging\Interface\QuestLogSorter"    | Out-Null

Copy-Item $dll.FullName "$staging\F4SE\Plugins\QuestLogSorter.dll"
Copy-Item $groups       "$staging\F4SE\Plugins\QuestLogSorter\groups.json"
Copy-Item $swf          "$staging\Interface\QuestLogSorter\QLS.swf"

if ($IncludeDataPage) {
    if (-not (Test-Path $dataPage)) {
        throw "-IncludeDataPage was given but data\Interface\Pipboy_DataPage.swf does not exist. Do the JPEXS step first."
    }
    Copy-Item $dataPage "$staging\Interface\Pipboy_DataPage.swf"
} else {
    Write-Host "Skipping Pipboy_DataPage.swf (pass -IncludeDataPage to bundle it)." -ForegroundColor Yellow
}

# --- readme for the archive ----------------------------------------------
@"
QuestLogSorter $Version

Requires:
  F4SE                                   (install manually to the game root)
  Address Library for F4SE Plugins

Archive invalidation must be enabled or the loose Interface files are ignored.

No ESP - this mod will not appear in the plugins list. That is expected.

Source: GPL-3.0. See the mod page for the repository link.
"@ | Set-Content "$staging\README.txt" -Encoding UTF8

# --- zip ------------------------------------------------------------------
if (Test-Path $archive) { Remove-Item $archive -Force }
Compress-Archive -Path "$staging\*" -DestinationPath $archive -CompressionLevel Optimal

Write-Host ""
Write-Host "Packaged $archive" -ForegroundColor Green
Write-Host ""
Get-ChildItem $staging -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($staging.Length + 1)
    "{0,-52} {1,8:N0} bytes" -f $rel, $_.Length
}
