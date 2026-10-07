$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
& (Join-Path $projectRoot 'start_ai.ps1')
$pidFile = Join-Path $projectRoot '.godot/desktop_pet.pid'
if (Test-Path -LiteralPath $pidFile) {
    $petProcessId = [int](Get-Content -LiteralPath $pidFile)
    $existingProcess = Get-Process -Id $petProcessId -ErrorAction SilentlyContinue
    if ($existingProcess -and $existingProcess.ProcessName -like 'Godot*') {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $petProcessId" -ErrorAction SilentlyContinue
        if ($processInfo.CommandLine -and $processInfo.CommandLine.Replace('\','/').Contains($projectRoot.Replace('\','/'))) {
            Set-Content -LiteralPath (Join-Path $projectRoot '.godot/restore_pet.request') -Value 'show' -Encoding ASCII
            return
        }
    }
}
$godotPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Godot_v4.7.2-stable_win64.exe'
$portableGodot = Join-Path $projectRoot 'runtime/Godot_v4.7.2-stable_win64.exe'
if (Test-Path -LiteralPath $portableGodot) { $godotPath = $portableGodot }
if (-not (Test-Path -LiteralPath $godotPath)) {
    $engine = Get-Command godot -ErrorAction SilentlyContinue
    if ($engine) { $godotPath = $engine.Source }
    else { throw 'Godot executable was not found. Update godotPath in start_pet.ps1.' }
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.godot/global_script_class_cache.cfg'))) {
    $importProcess = Start-Process -FilePath $godotPath -ArgumentList @('--headless', '--editor', '--import', '--path', ('"{0}"' -f $projectRoot)) -WorkingDirectory $projectRoot -WindowStyle Hidden -Wait -PassThru
    if ($importProcess.ExitCode -ne 0) { throw 'Godot project import failed. Open project.godot in the included editor.' }
}
$logDirectory = Join-Path $projectRoot 'previews'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$petProcess = Start-Process -FilePath $godotPath -ArgumentList @('--path', ('"{0}"' -f $projectRoot), '--rendering-driver', 'opengl3') -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru -RedirectStandardOutput (Join-Path $logDirectory 'pet.log') -RedirectStandardError (Join-Path $logDirectory 'pet_errors.log')
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot '.godot') | Out-Null
Set-Content -LiteralPath $pidFile -Value $petProcess.Id -Encoding ASCII
