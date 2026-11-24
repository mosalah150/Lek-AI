# สำรองข้อมูล Open WebUI (แชท ผู้ใช้ เอกสาร Knowledge) และค่าตั้งไปที่ NAS
# Task Scheduler รันให้ทุกคืน 02:00 (ตั้งโดย setup-backup.ps1) · รันเองได้ด้วย  ai backup
. "$PSScriptRoot\common.ps1"
$cfg      = Read-AiConfig
$Nas      = "\\$($cfg.NasHost)\ai-backup"
$Staging  = Join-Path $cfg.HddDrive 'ai-backup-staging'
$KeepDays = 14
$LogFile  = 'backup.log'

if (-not (Test-Path $Nas)) {
    Write-AiLog $LogFile "ERROR: เข้าถึง $Nas ไม่ได้ (NAS ปิดอยู่ หรือยังไม่ได้บันทึกรหัสด้วย setup-backup.ps1)"
    exit 1
}

$Stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$Dir   = Join-Path $Staging $Stamp
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

try {
    # หยุด Open WebUI ชั่วคราว (~1 นาที) เพื่อให้ฐานข้อมูลอยู่ในสถานะสมบูรณ์
    Stop-OpenWebUI
    tar.exe -czf (Join-Path $Dir 'open-webui-data.tgz') -C (Join-Path $AiRoot 'open-webui') data
    if ($LASTEXITCODE -ne 0) { throw "tar จบด้วยรหัส $LASTEXITCODE" }
    Copy-Item $ConfigPath $Dir      # มีรหัสลับ: share ai-backup ต้องเข้าได้เฉพาะ admin
}
catch {
    Write-AiLog $LogFile "ERROR: $($_.Exception.Message)"
    Start-OpenWebUI
    exit 1
}
Start-OpenWebUI

robocopy $Dir (Join-Path $Nas $Stamp) /E /MOVE /R:3 /W:10 /NP /NFL /NDL | Out-Null
if ($LASTEXITCODE -ge 8) { Write-AiLog $LogFile "ERROR: คัดลอกไป NAS ไม่สำเร็จ (robocopy $LASTEXITCODE)"; exit 1 }

Get-ChildItem $Nas -Directory |
    Where-Object { $_.Name -match '^\d{8}-\d{4}$' -and $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } |
    Remove-Item -Recurse -Force

Write-AiLog $LogFile "OK: backup $Stamp"
exit 0
