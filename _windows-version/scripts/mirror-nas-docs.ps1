# ทำสำเนาเอกสารองค์กรจาก NAS (ai-docs) ลง HDD 2TB ของ 5820 ทุกคืน
# สำเนานี้มีไว้กรณี NAS เสียทั้งเครื่อง ส่วนการย้อนเวอร์ชันไฟล์ให้ใช้ Snapshot บน NAS

$Src = '\\192.168.1.10\ai-docs'           # แก้เป็น IP ของ DS918+
$Dst = 'E:\nas-docs-mirror'
$Log = 'E:\ai-backup.log'

if (-not (Test-Path $Src)) { "$(Get-Date -Format s) ERROR: $Src is not reachable" | Add-Content $Log; exit 1 }

robocopy $Src $Dst /MIR /R:2 /W:5 /NP /NFL /NDL | Out-Null
# robocopy: exit code 0-7 = สำเร็จ, 8 ขึ้นไป = มีไฟล์ที่คัดลอกไม่ได้
if ($LASTEXITCODE -ge 8) { "$(Get-Date -Format s) ERROR: mirror failed (code $LASTEXITCODE)" | Add-Content $Log; exit 1 }
"$(Get-Date -Format s) OK: nas-docs mirrored" | Add-Content $Log
