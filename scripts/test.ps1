$ErrorActionPreference = 'Stop'

$bash = 'C:\msys64\usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) {
    throw 'MSYS2 bash was not found at C:\msys64\usr\bin\bash.exe'
}

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($root -notmatch '^([A-Za-z]):\\(.*)$') {
    throw "Cannot convert project path to an MSYS2 path: $root"
}
$msysRoot = '/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2].Replace('\', '/')

$command = @"
set -euo pipefail
export PATH=/ucrt64/bin:/usr/bin:`$PATH
cd '$msysRoot'
verilator --version

run_test() {
  local top="`$1"
  local filelist="`$2"
  local output="build/sim/`$top"
  mkdir -p "`$output"
  verilator --binary --timing --assert --Wall --Wno-fatal \
    --Mdir "`$output" \
    --top-module "`$top" \
    -f "`$filelist"
  "./`$output/V`$top"
}

run_test tb_video_timing sim/video.f
run_test tb_framebuffer_scanout sim/framebuffer.f
run_test tb_rect_renderer sim/rect_renderer.f
run_test tb_command_path sim/command_path.f
run_test tb_spi_command sim/spi_command.f
"@

& $bash -lc $command
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
