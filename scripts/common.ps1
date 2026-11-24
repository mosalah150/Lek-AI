# ฟังก์ชันที่สคริปต์อื่นใช้ร่วมกัน (dot-source:  . "$PSScriptRoot\common.ps1")

$AiRoot     = 'C:\ai'
$ConfigPath = Join-Path $AiRoot 'config.json'
$LogDir     = Join-Path $AiRoot 'logs'
$WebUITask  = 'Lek-AI Open WebUI'

function Read-AiConfig {
    if (-not (Test-Path $ConfigPath)) { throw "ไม่พบ ${ConfigPath} (รัน scripts\install.ps1 ก่อน)" }
    return Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

function Save-AiConfig($cfg) {
    $cfg | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Write-AiLog([string]$file, [string]$msg) {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
    $line = "$(Get-Date -Format s) $msg"
    Write-Host $line
    Add-Content -Path (Join-Path $LogDir $file) -Value $line -Encoding UTF8
}

function Stop-OpenWebUI {
    Stop-ScheduledTask -TaskName $WebUITask -ErrorAction SilentlyContinue
    # หยุด process ของ Open WebUI ที่ยังค้างอยู่ (ยกเว้นตัวสคริปต์นี้เอง)
    Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like '*open-webui*' -and $_.ProcessId -ne $PID } |
        ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }
    Start-Sleep -Seconds 3
}

function Start-OpenWebUI {
    Start-ScheduledTask -TaskName $WebUITask
}

function Test-OpenWebUI {
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:3000/health' -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Get-LmsPath {
    $p = Join-Path $env:USERPROFILE '.lmstudio\bin\lms.exe'
    if (Test-Path $p) { return $p }
    $cmd = Get-Command lms -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}
