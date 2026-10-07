$projectRoot = $PSScriptRoot
$serverPidFile = Join-Path $projectRoot '.godot/ai_server.pid'
if (Test-Path -LiteralPath $serverPidFile) {
    $serverProcessId = [int](Get-Content -LiteralPath $serverPidFile)
    $serverInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $serverProcessId" -ErrorAction SilentlyContinue
    $serverPath = Join-Path $projectRoot 'ai/server.py'
    if ($serverInfo -and $serverInfo.CommandLine.Contains($serverPath)) {
        $runtimeInfoFile = Join-Path $projectRoot 'ai/server_info.json'
        if (Test-Path -LiteralPath $runtimeInfoFile) {
            try {
                $runtimeInfo = Get-Content -LiteralPath $runtimeInfoFile | ConvertFrom-Json
                Invoke-RestMethod -Uri "http://127.0.0.1:$($runtimeInfo.port)/shutdown" -Method Post -Headers @{'X-Kitty-Token'=$runtimeInfo.token} -Body '{}' -ContentType 'application/json' -TimeoutSec 3 | Out-Null
            } catch { }
        }
        $ownedServers = Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($serverPath) }
        foreach ($ownedServer in $ownedServers) {
            Stop-Process -Id $ownedServer.ProcessId -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $serverPidFile
}
$pidFile = Join-Path $projectRoot '.godot/desktop_pet.pid'
if (Test-Path -LiteralPath $pidFile) {
    $petProcessId = [int](Get-Content -LiteralPath $pidFile)
    $petProcess = Get-Process -Id $petProcessId -ErrorAction SilentlyContinue
    if ($petProcess -and $petProcess.ProcessName -like 'Godot*') {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $petProcessId" -ErrorAction SilentlyContinue
        if ($processInfo.CommandLine -and $processInfo.CommandLine.Replace('\','/').Contains($projectRoot.Replace('\','/'))) {
            Stop-Process -Id $petProcessId
        }
    }
    Remove-Item -LiteralPath $pidFile
}
