$godot = "C:\Users\ryanf\Downloads\apps\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"

Write-Host "--- STARTING LAN REGRESSION TEST (2 INSTANCES) ---"

$hostLog = "user://host_lan.log"
$clientLog = "user://client_lan.log"
$hostLogPath = "$env:APPDATA\Godot\app_userdata\Fight Back\host_lan.log"
$clientLogPath = "$env:APPDATA\Godot\app_userdata\Fight Back\client_lan.log"

Remove-Item -Path $hostLogPath -ErrorAction SilentlyContinue
Remove-Item -Path $clientLogPath -ErrorAction SilentlyContinue

Write-Host "Launching Host instance (--host, --char=kitsune)..."
$hostProc = Start-Process -FilePath $godot -ArgumentList "--host", "--char=kitsune", "--name=LanHost", "--autotest", "--log-file", $hostLog -PassThru

Start-Sleep -Seconds 2

Write-Host "Launching Client instance (--join, --char=yamabushi)..."
$clientProc = Start-Process -FilePath $godot -ArgumentList "--join=127.0.0.1", "--char=yamabushi", "--name=LanClient", "--autotest", "--log-file", $clientLog -PassThru

$matchTimeout = 65
$matchSw = [System.Diagnostics.Stopwatch]::StartNew()
$success = $false

while ($matchSw.Elapsed.TotalSeconds -lt $matchTimeout) {
    if (Test-Path $hostLogPath) {
        $hContent = Get-Content -Path $hostLogPath -Raw -ErrorAction SilentlyContinue
        if ($hContent -match "AUTOTEST SUCCESS") {
            $success = $true
            Write-Host "Host logged AUTOTEST SUCCESS!"
            break
        }
    }
    if (Test-Path $clientLogPath) {
        $cContent = Get-Content -Path $clientLogPath -Raw -ErrorAction SilentlyContinue
        if ($cContent -match "AUTOTEST SUCCESS") {
            $success = $true
            Write-Host "Client logged AUTOTEST SUCCESS!"
            break
        }
    }
    if ($hostProc.HasExited -and $clientProc.HasExited) {
        break
    }
    Start-Sleep -Milliseconds 500
}

Start-Sleep -Seconds 2

Write-Host "`n=== HOST LAN LOG TAIL ==="
if (Test-Path $hostLogPath) {
    Get-Content -Path $hostLogPath | Select-Object -Last 30
}

Write-Host "`n=== CLIENT LAN LOG TAIL ==="
if (Test-Path $clientLogPath) {
    Get-Content -Path $clientLogPath | Select-Object -Last 30
}

Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $clientProc.Id -Force -ErrorAction SilentlyContinue

if ($success) {
    Write-Host "`n>>> LAN REGRESSION TEST PASSED 100%! <<<"
    exit 0
} else {
    Write-Host "`n>>> LAN REGRESSION TEST FAILED OR TIMED OUT! <<<"
    exit 1
}
