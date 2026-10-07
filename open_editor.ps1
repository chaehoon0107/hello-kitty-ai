$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot 'runtime/Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $engine)) {
    $engine = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Godot_v4.7.2-stable_win64.exe'
}
if (-not (Test-Path -LiteralPath $engine)) { throw 'Godot executable was not found.' }
Start-Process -FilePath $engine -ArgumentList @('--editor', '--path', ('"{0}"' -f $PSScriptRoot)) -WorkingDirectory $PSScriptRoot
