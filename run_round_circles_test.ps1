$godot = "C:\Users\ryanf\Downloads\apps\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"

if (Test-Path "last_room_code.txt") {
    Remove-Item "last_room_code.txt" -Force
}

$hostLog = "test_circles_host.log"
$clientLog = "test_circles_client.log"
if (Test-Path $hostLog) { Remove-Item $hostLog -Force }
if (Test-Path $clientLog) { Remove-Item $clientLog -Force }

Write-Host "Starting Host with --create-room --relay=ws://127.0.0.1:10000 --autotest..."

$hostProc = Start-Process -FilePath $godot -ArgumentList "--create-room", "--relay=ws://127.0.0.1:10000", "--autotest" -PassThru -RedirectStandardOutput $hostLog -RedirectStandardError "test_circles_host_err.log"

$code = ""
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path "last_room_code.txt") {
        $code = (Get-Content "last_room_code.txt" -Raw).Trim()
        if ($code.Length -eq 4) {
            break
        }
    }
}

if (-not $code) {
    Write-Host "Failed to obtain room code from host!"
    Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Obtained room code: $code"
Write-Host "Starting Client with --join-room=$code --relay=ws://127.0.0.1:10000 --autotest..."

$clientProc = Start-Process -FilePath $godot -ArgumentList "--join-room=$code", "--relay=ws://127.0.0.1:10000", "--autotest" -PassThru -RedirectStandardOutput $clientLog -RedirectStandardError "test_circles_client_err.log"

Write-Host "Both processes running. Waiting for match to complete rounds and rematch (up to 80s)..."

$completed = $false
for ($i = 0; $i -lt 160; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $hostLog) {
        $content = Get-Content $hostLog -Raw -ErrorAction SilentlyContinue
        if ($content -match "AUTOTEST SUCCESS") {
            Write-Host "Full match and rematch flow succeeded!"
            $completed = $true
            break
        }
    }
    if ($hostProc.HasExited -and $clientProc.HasExited) {
        break
    }
}

Start-Sleep -Seconds 2
Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $clientProc.Id -Force -ErrorAction SilentlyContinue

Write-Host "=== HOST ROUND CIRCLES LOGS ==="
if (Test-Path $hostLog) {
    Get-Content $hostLog | Select-String -Pattern "ROUND CIRCLES|AUTOTEST SUCCESS"
}

Write-Host "=== CLIENT ROUND CIRCLES LOGS ==="
if (Test-Path $clientLog) {
    Get-Content $clientLog | Select-String -Pattern "ROUND CIRCLES"
}

if ($completed) {
    Write-Host "ROUND CIRCLES TEST: SUCCESS"
    exit 0
} else {
    Write-Host "ROUND CIRCLES TEST: INCOMPLETE"
    exit 1
}
