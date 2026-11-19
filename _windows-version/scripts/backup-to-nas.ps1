# สำรองข้อมูล Open WebUI, n8n และ PostgreSQL ไปที่ NAS ทุกคืน
# ตั้งใน Task Scheduler (ดู README ขั้นที่ 9)

$ErrorActionPreference = 'Stop'

$Stack    = 'C:\ai\stack'                 # โฟลเดอร์ที่มี docker-compose.yml และ .env
$Staging  = 'E:\ai-backup-staging'        # พักไฟล์บน HDD ก่อนส่งไป NAS
$Nas      = '\\192.168.1.10\ai-backup'    # แก้เป็น IP ของ DS918+
$KeepDays = 14
$Project  = 'local-ai'                    # ตรงกับ name: ใน docker-compose.yml
$Log      = 'E:\ai-backup.log'

function Log($msg) { "$(Get-Date -Format s) $msg" | Tee-Object -FilePath $Log -Append }

if (-not (Test-Path $Nas)) { Log "ERROR: $Nas is not reachable, skipping backup"; exit 1 }

$Stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$Dir   = Join-Path $Staging $Stamp
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Set-Location $Stack

try {
    # 1) dump ฐานข้อมูล n8n ขณะยังทำงานอยู่ (pg_dump ได้ข้อมูลที่สมบูรณ์โดยไม่ต้องหยุด)
    docker compose exec -T postgres pg_dump -U n8n -F c -f /tmp/n8n.dump n8n
    if ($LASTEXITCODE -ne 0) { throw 'pg_dump failed' }
    docker compose cp postgres:/tmp/n8n.dump (Join-Path $Dir 'n8n-db.dump')

    # 2) หยุด Open WebUI และ n8n ชั่วคราว (~1 นาที) เพื่อให้ไฟล์ในโฟลเดอร์ข้อมูลอยู่ในสถานะสมบูรณ์
    docker compose stop open-webui n8n
    foreach ($vol in 'open-webui', 'n8n') {
        docker run --rm -v "${Project}_${vol}:/data:ro" -v "${Dir}:/backup" alpine `
            tar czf "/backup/$vol.tgz" -C /data .
        if ($LASTEXITCODE -ne 0) { throw "tar of volume $vol failed" }
    }
}
finally {
    docker compose start open-webui n8n | Out-Null
}

# 3) เก็บ config ไปด้วย (.env มี secret: share ai-backup ต้องจำกัดสิทธิ์)
Copy-Item (Join-Path $Stack 'docker-compose.yml'), (Join-Path $Stack '.env') $Dir

# 4) ย้ายไป NAS แล้วลบชุดที่เก่ากว่า KeepDays
robocopy $Dir (Join-Path $Nas $Stamp) /E /MOVE /R:3 /W:10 /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Log "ERROR: robocopy to NAS failed (code $LASTEXITCODE)"; exit 1 }

Get-ChildItem $Nas -Directory |
    Where-Object { $_.Name -match '^\d{8}-\d{4}$' -and $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } |
    Remove-Item -Recurse -Force

Log "OK: backup $Stamp"
