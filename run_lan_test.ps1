$godot = "C:\Users\ryanf\Downloads\apps\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"

$hostLog = "test_lan_host.log"
$clientLog = "test_lan_client.log"
if (Test-Path $hostLog) { Remove-Item $hostLog -Force }
if (Test-Path $clientLog) { Remove-Item $clientLog -Force }

Write-Host "Starting LAN Host with --host --autotest..."
$hostProc = Start-Process -FilePath $godot -ArgumentList "--host", "--autotest" -PassThru -RedirectStandardOutput $hostLog -RedirectStandardError "test_lan_host_err.log"

Start-Sleep -Seconds 2

Write-Host "Starting LAN Client with --join=127.0.0.1 --autotest..."
$clientProc = Start-Process -FilePath $godot -ArgumentList "--join=127.0.0.1", "--autotest" -PassThru -RedirectStandardOutput $clientLog -RedirectStandardError "test_lan_client_err.log"

Write-Host "Waiting for LAN match autotest to finish (up to 40s)..."

$completed = $false
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $hostLog) {
        $content = Get-Content $hostLog -Raw -ErrorAction SilentlyContinue
        if ($content -match "AUTOTEST SUCCESS") {
            Write-Host "LAN autotest succeeded!"
            $completed = $true
            break
        }
    }
    if ($hostProc.HasExited -and $clientProc.HasExited) {
        break
    }
}

Start-Sleep -Seconds 1
Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $clientProc.Id -Force -ErrorAction SilentlyContinue

Write-Host "=== LAN HOST LOG SUMMARY ==="
if (Test-Path $hostLog) {
    Get-Content $hostLog | Select-String -Pattern "ROUND CIRCLES|AUTOTEST SUCCESS"
}

if ($completed) {
    Write-Host "LAN REGRESSION TEST: SUCCESS"
    exit 0
} else {
    Write-Host "LAN REGRESSION TEST: FAILED"
    exit 1
}
