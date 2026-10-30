$godot = "C:\Users\ryanf\Downloads\apps\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"

Write-Host "--- STARTING ONLINE ROOM-CODE TEST (2 INSTANCES) ---"

$hostLog = "user://host_online.log"
$clientLog = "user://client_online.log"
$hostLogPath = "$env:APPDATA\Godot\app_userdata\Fight Back\host_online.log"
$clientLogPath = "$env:APPDATA\Godot\app_userdata\Fight Back\client_online.log"

# Clean old logs if present
Remove-Item -Path $hostLogPath -ErrorAction SilentlyContinue
Remove-Item -Path $clientLogPath -ErrorAction SilentlyContinue

# Launch Host Instance
Write-Host "Launching Host instance (kitsune, --create-room)..."
$hostProc = Start-Process -FilePath $godot -ArgumentList "--create-room", "--char=kitsune", "--name=OnlineHost", "--autotest", "--log-file", $hostLog -PassThru

# Wait for room code to be generated and printed to log
$roomCode = ""
$timeout = 20
$sw = [System.Diagnostics.Stopwatch]::StartNew()

while ($sw.Elapsed.TotalSeconds -lt $timeout) {
    if (Test-Path $hostLogPath) {
        $content = Get-Content -Path $hostLogPath -Raw -ErrorAction SilentlyContinue
        if ($content -match "\[ONLINE\] Room created successfully! Code: ([0-9A-Z]{4})") {
            $roomCode = $matches[1]
            break
        }
    }
    Start-Sleep -Milliseconds 250
}

if (-not $roomCode) {
    Write-Host "ERROR: Host failed to create room within $timeout seconds!"
    if (Test-Path $hostLogPath) {
        Get-Content -Path $hostLogPath | Select-Object -Last 30
    }
    Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Captured Room Code: $roomCode"
Write-Host "Launching Client instance (yamabushi, --join-room=$roomCode)..."

$clientProc = Start-Process -FilePath $godot -ArgumentList "--join-room=$roomCode", "--char=yamabushi", "--name=OnlineClient", "--autotest", "--log-file", $clientLog -PassThru

# Wait for match completion or timeout (75 seconds max)
$matchTimeout = 75
$matchSw = [System.Diagnostics.Stopwatch]::StartNew()
$success = $false

while ($matchSw.Elapsed.TotalSeconds -lt $matchTimeout) {
    # Check if Host completed autotest
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

Write-Host "`n=== HOST LOG TAIL ==="
if (Test-Path $hostLogPath) {
    Get-Content -Path $hostLogPath | Select-Object -Last 35
}

Write-Host "`n=== CLIENT LOG TAIL ==="
if (Test-Path $clientLogPath) {
    Get-Content -Path $clientLogPath | Select-Object -Last 35
}

# Clean up processes if still running
Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $clientProc.Id -Force -ErrorAction SilentlyContinue

if ($success) {
    Write-Host "`n>>> ONLINE ROOM-CODE PLAY TEST PASSED 100%! <<<"
    exit 0
} else {
    Write-Host "`n>>> ONLINE ROOM-CODE PLAY TEST FAILED OR TIMED OUT! <<<"
    exit 1
}
