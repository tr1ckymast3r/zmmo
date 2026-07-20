# ZMMO Agent — Windows One-Line Install
# Run in PowerShell (Right-click → Run as Administrator NOT required):
#   powershell -ExecutionPolicy Bypass -File install.ps1

$agentUrl = "http://100.87.34.74:3013/agent-binaries/zmmo-agent-windows-amd64.exe"
$destDir = "$env:LOCALAPPDATA\zmmo"
$destExe = "$destDir\zmmo-agent.exe"

Write-Host "ZMMO Agent Installer" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan

# Create directory
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

# Download
Write-Host "Downloading agent..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $agentUrl -OutFile $destExe -UseBasicParsing
    Write-Host "Downloaded: $destExe" -ForegroundColor Green
} catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    Write-Host "Check that the server is reachable at $agentUrl" -ForegroundColor Red
    pause
    exit 1
}

# Unblock (critical — removes SmartScreen warning)
Unblock-File -Path $destExe
Write-Host "Unblocked — SmartScreen will not appear" -ForegroundColor Green

# Create desktop shortcut
$shortcut = "$env:USERPROFILE\Desktop\ZMMO Agent.lnk"
$WScriptShell = New-Object -ComObject WScript.Shell
$sc = $WScriptShell.CreateShortcut($shortcut)
$sc.TargetPath = $destExe
$sc.WorkingDirectory = $destDir
$sc.Save()
Write-Host "Desktop shortcut created" -ForegroundColor Green

# Run agent
Write-Host ""
Write-Host "Starting agent on port 55555..." -ForegroundColor Cyan
Write-Host "Keep this window open while using the panel." -ForegroundColor Yellow
Write-Host "Dashboard: http://100.87.34.74:3013" -ForegroundColor Cyan
Write-Host ""

Start-Process -FilePath $destExe -WorkingDirectory $destDir -NoNewWindow -Wait

pause
