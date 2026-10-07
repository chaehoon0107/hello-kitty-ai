$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$pythonPath = Join-Path $projectRoot 'ai/.venv/Scripts/python.exe'
$portablePython = Join-Path $projectRoot 'runtime/python/python.exe'
if (Test-Path -LiteralPath $portablePython) { $pythonPath = $portablePython }
$serverPath = Join-Path $projectRoot 'ai/server.py'
$pidPath = Join-Path $projectRoot '.godot/ai_server.pid'
$runtimeInfoPath = Join-Path $projectRoot 'ai/server_info.json'
if (Test-Path -LiteralPath $runtimeInfoPath) {
    try {
        $runtimeInfo = Get-Content -LiteralPath $runtimeInfoPath | ConvertFrom-Json
        $runtimeProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($runtimeInfo.pid)" -ErrorAction SilentlyContinue
        if ($runtimeProcess -and $runtimeProcess.CommandLine.Contains($serverPath)) {
            Set-Content -LiteralPath $pidPath -Value $runtimeInfo.pid -Encoding ASCII
            return
        }
    } catch { }
}
if (Test-Path -LiteralPath $pidPath) {
    $serverProcessId = [int](Get-Content -LiteralPath $pidPath)
    $existingServer = Get-CimInstance Win32_Process -Filter "ProcessId = $serverProcessId" -ErrorAction SilentlyContinue
    if ($existingServer -and $existingServer.CommandLine.Contains($serverPath)) { return }
}
if (-not (Test-Path -LiteralPath $pythonPath)) { throw 'The local Qwen environment is missing.' }
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'ai/data') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot '.godot') | Out-Null
$env:PYTHONUTF8 = '1'
$serverProcess = Start-Process -FilePath $pythonPath -ArgumentList @('-u', ('"{0}"' -f $serverPath)) -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $projectRoot 'ai/data/server.log') -RedirectStandardError (Join-Path $projectRoot 'ai/data/server_errors.log')
Set-Content -LiteralPath $pidPath -Value $serverProcess.Id -Encoding ASCII
