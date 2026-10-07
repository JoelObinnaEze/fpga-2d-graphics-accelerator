param(
    [string]$PicoSdkPath = $env:PICO_SDK_PATH
)

$ErrorActionPreference = 'Stop'

if (-not $PicoSdkPath) {
    $PicoSdkPath = 'C:\pico-sdk'
}

$sdkImport = Join-Path $PicoSdkPath 'external\pico_sdk_import.cmake'
if (-not (Test-Path -LiteralPath $sdkImport)) {
    throw "Pico SDK was not found at $PicoSdkPath"
}

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceRoot = Join-Path $projectRoot 'firmware\rp2040'
$buildRoot = Join-Path $projectRoot 'build\pico\fpga_pong'
$uf2 = Join-Path $buildRoot 'fpga_pong.uf2'

$previousSdkPath = $env:PICO_SDK_PATH
try {
    $env:PICO_SDK_PATH = $PicoSdkPath
    & cmake -S $sourceRoot -B $buildRoot -G 'MinGW Makefiles' `
        -DCMAKE_BUILD_TYPE=Release -DPICO_BOARD=pico
    if ($LASTEXITCODE -ne 0) {
        throw "Pico firmware configuration failed with exit code $LASTEXITCODE"
    }

    & cmake --build $buildRoot --parallel
    if ($LASTEXITCODE -ne 0) {
        throw "Pico firmware build failed with exit code $LASTEXITCODE"
    }
} finally {
    $env:PICO_SDK_PATH = $previousSdkPath
}

if (-not (Test-Path -LiteralPath $uf2)) {
    throw "Pico build completed without producing $uf2"
}

Write-Output $uf2
