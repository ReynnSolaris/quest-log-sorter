# Builds QLS.swf from the AS3 sources.
#
# Needs the Apache Flex SDK (or AIR SDK) on PATH - mxmlc is the compiler.
# Fallout 4's Scaleform runtime is Flash 11.2 / SWF 15, so both flags matter:
# a SWF 16+ file silently fails to load in-game.

param(
    [string]$Out = "..\data\Interface\QuestLogSorter\QLS.swf",
    [string]$Config = "release"
)

$ErrorActionPreference = "Stop"

$mxmlc = Get-Command mxmlc -ErrorAction SilentlyContinue
if (-not $mxmlc) {
    throw "mxmlc not found. Install the Apache Flex SDK and add its bin/ to PATH."
}

$outPath = Join-Path $PSScriptRoot $Out
New-Item -ItemType Directory -Force -Path (Split-Path $outPath) | Out-Null

# Delete the previous build first. mxmlc leaves the old file in place when it
# fails, so without this a failed compile looks like a successful one right up
# until the game loads a SWF that is three edits out of date.
if (Test-Path $outPath) {
    Remove-Item $outPath -Force
}

$mxmlcArgs = @(
    "src\Main.as",
    "-source-path=src",
    "-output=$outPath",
    "-target-player=11.2",
    "-swf-version=15",
    "-default-frame-rate=30",
    "-default-background-color=0x000000",
    "-static-link-runtime-shared-libraries=true",
    "-warnings=true"
)

if ($Config -eq "debug") {
    $mxmlcArgs += "-debug=true"
} else {
    $mxmlcArgs += @("-debug=false", "-optimize=true")
}

Push-Location $PSScriptRoot
try {
    & mxmlc @mxmlcArgs
    $code = $LASTEXITCODE

    # mxmlc prints errors to stdout and still exits 0 in some SDK builds, so
    # check that the file actually appeared rather than trusting the exit code.
    if ($code -ne 0) {
        throw "mxmlc failed (exit $code)"
    }
    if (-not (Test-Path $outPath)) {
        throw "mxmlc reported success but produced no output - scroll up for the errors"
    }

    $size = (Get-Item $outPath).Length
    Write-Host "Built $outPath ($size bytes)" -ForegroundColor Green
} finally {
    Pop-Location
}
