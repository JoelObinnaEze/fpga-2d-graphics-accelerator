param(
    [string]$Uf2Path = (Join-Path $PSScriptRoot '..\build\pico\fpga_pong\fpga_pong.uf2')
)

$ErrorActionPreference = 'Stop'

$uf2 = [IO.Path]::GetFullPath($Uf2Path)
if (-not (Test-Path -LiteralPath $uf2)) {
    throw "Pong UF2 was not found at $uf2. Run scripts\build_pico_pong.ps1 first."
}

$bootVolumes = @(Get-Volume | Where-Object {
    $_.FileSystemLabel -eq 'RPI-RP2' -and $_.DriveLetter
})
if ($bootVolumes.Count -ne 1) {
    throw "Expected one RPI-RP2 BOOTSEL drive, found $($bootVolumes.Count)."
}

$destination = "$($bootVolumes[0].DriveLetter):\"
Copy-Item -LiteralPath $uf2 -Destination $destination
Write-Output "Flashed $uf2 to $destination"
