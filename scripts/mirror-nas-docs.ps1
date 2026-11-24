# ทำสำเนาเอกสารจาก NAS (ai-docs) ลง HDD ของ server ทุกคืน 02:30
# สำเนานี้มีไว้กรณี NAS เสียทั้งเครื่อง ส่วนการย้อนเวอร์ชันไฟล์ให้ใช้ Snapshot บน NAS
. "$PSScriptRoot\common.ps1"
$cfg     = Read-AiConfig
$Src     = "\\$($cfg.NasHost)\ai-docs"
$Dst     = Join-Path $cfg.HddDrive 'nas-docs-mirror'
$LogFile = 'backup.log'

if (-not (Test-Path $Src)) { Write-AiLog $LogFile "ERROR: เข้าถึง $Src ไม่ได้"; exit 1 }

robocopy $Src $Dst /MIR /R:2 /W:5 /NP /NFL /NDL | Out-Null
if ($LASTEXITCODE -ge 8) { Write-AiLog $LogFile "ERROR: mirror เอกสารไม่สำเร็จ (robocopy $LASTEXITCODE)"; exit 1 }
Write-AiLog $LogFile 'OK: nas-docs mirrored'
exit 0
