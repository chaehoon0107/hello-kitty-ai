$ErrorActionPreference = 'Stop'
$python = Join-Path $PSScriptRoot 'runtime/python/python.exe'
$engine = Join-Path $PSScriptRoot 'runtime/Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $python) -or -not (Test-Path -LiteralPath $engine)) {
    throw 'Extract the complete transfer archive, including the runtime folder, first.'
}
& $python -I -c 'import sys, torch, transformers, PIL, sqlite3; print("Python", sys.version.split()[0], "| Torch", torch.__version__, "| Transformers", transformers.__version__)'
if ($LASTEXITCODE -ne 0) { throw 'The bundled Python runtime check failed.' }
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'previews') -Force | Out-Null
$importProcess = Start-Process -FilePath $engine -ArgumentList @('--headless', '--editor', '--import', '--path', ('"{0}"' -f $PSScriptRoot)) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $PSScriptRoot 'previews/setup.log') -RedirectStandardError (Join-Path $PSScriptRoot 'previews/setup_errors.log')
if ($importProcess.ExitCode -ne 0) { throw 'Godot import failed. See previews/setup_errors.log.' }
$shortcutShell = New-Object -ComObject WScript.Shell
$shortcutNames = @('Pet Start', 'Pet Stop', 'Godot Editor')
$scripts = @('start_pet.ps1', 'stop_pet.ps1', 'open_editor.ps1')
for ($index = 0; $index -lt $scripts.Count; $index++) {
    $shortcut = $shortcutShell.CreateShortcut((Join-Path $PSScriptRoot ($shortcutNames[$index] + '.lnk')))
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot $scripts[$index]) + '"'
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.WindowStyle = 7
    $shortcut.Save()
}
Write-Host 'Ready. Use Pet Start.lnk to run, or Godot Editor.lnk to continue editing.'
