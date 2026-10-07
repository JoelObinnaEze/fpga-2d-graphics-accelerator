param(
    [string]$GowinRoot = $env:GOWIN_ROOT,
    [int]$CableIndex = 1
)

$ErrorActionPreference = 'Stop'

if (-not $GowinRoot) {
    $GowinRoot = 'C:\Gowin\Gowin_V1.9.11.03_Education_x64'
}

$programmer = Join-Path $GowinRoot 'Programmer\bin\programmer_cli.exe'
if (-not (Test-Path -LiteralPath $programmer)) {
    throw "Gowin Programmer was not found at $programmer. Set GOWIN_ROOT to the installation directory."
}

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bitstream = Join-Path $projectRoot 'build\gowin\tang_nano_20k_sdram_bist\impl\pnr\tang_nano_20k_sdram_bist.fs'
if (-not (Test-Path -LiteralPath $bitstream)) {
    throw "SDRAM BIST bitstream was not found at $bitstream. Run scripts\build_sdram_bist.ps1 first."
}

# Operation 2 is SRAM programming. It is volatile and does not write onboard flash.
& $programmer `
    --device GW2AR-18C `
    --operation_index 2 `
    --fsFile $bitstream `
    --cable-index $CableIndex `
    --frequency '2.5MHz'

if ($LASTEXITCODE -ne 0) {
    throw "Gowin SRAM programming failed with exit code $LASTEXITCODE"
}
