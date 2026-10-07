param(
    [string]$GowinRoot = $env:GOWIN_ROOT
)

$ErrorActionPreference = 'Stop'

if (-not $GowinRoot) {
    $GowinRoot = 'C:\Gowin\Gowin_V1.9.11.03_Education_x64'
}

$gwSh = Join-Path $GowinRoot 'IDE\bin\gw_sh.exe'
if (-not (Test-Path -LiteralPath $gwSh)) {
    throw "Gowin Tcl shell was not found at $gwSh. Set GOWIN_ROOT to the installation directory."
}

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = Join-Path $projectRoot 'build\gowin\tang_nano_20k_sdram_bist'
$buildScript = Join-Path $projectRoot 'fpga\tang_nano_20k_sdram_bist.tcl'
$bitstream = Join-Path $buildRoot 'impl\pnr\tang_nano_20k_sdram_bist.fs'

[void](New-Item -ItemType Directory -Force -Path $buildRoot)

$previousProjectRoot = $env:FPGA_PROJECT_ROOT
try {
    $env:FPGA_PROJECT_ROOT = $projectRoot.Replace('\', '/')
    Push-Location $buildRoot
    try {
        & $gwSh $buildScript
        if ($LASTEXITCODE -ne 0) {
            throw "Gowin SDRAM BIST build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} finally {
    $env:FPGA_PROJECT_ROOT = $previousProjectRoot
}

if (-not (Test-Path -LiteralPath $bitstream)) {
    throw "Gowin completed without producing $bitstream"
}

Write-Output $bitstream
