# เปิด ComfyUI Desktop และตั้ง Tailscale ให้เปิดจาก Mac ได้ (ถูกเรียกโดย Task Scheduler ตอนล็อกอิน ไม่ต้องรันเอง)
# ตั้งงานนี้ด้วย  .\scripts\setup-comfyui.ps1
param([int]$Port = 8188, [int]$HttpsPort = 8443)
. "$PSScriptRoot\common.ps1"
$LogFile = 'comfyui.log'
$ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'

function Test-Port([int]$p) {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.Connect('127.0.0.1', $p); return $true } catch { return $false } finally { $c.Dispose() }
}

# 1. รอให้ Tailscale พร้อม (สูงสุด 2 นาที) แล้วตั้ง https://<เครื่อง>.<tailnet>.ts.net:8443 -> ComfyUI
#    ตั้งซ้ำทุกครั้ง เพราะค่า serve ของพอร์ตนี้เคยหายหลังรีสตาร์ต Tailscale
for ($i = 0; $i -lt 24; $i++) {
    & $ts status *> $null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 5
}
& $ts serve --bg --https=$HttpsPort $Port *> $null
if ($LASTEXITCODE -eq 0) { Write-AiLog $LogFile "OK: tailscale serve :$HttpsPort -> 127.0.0.1:$Port" }
else { Write-AiLog $LogFile "ERROR: tailscale serve ไม่สำเร็จ (exit $LASTEXITCODE)" }

# 2. เปิดแอป ComfyUI ถ้ายังไม่ได้เปิด
if (Test-Port $Port) { Write-AiLog $LogFile "OK: ComfyUI ทำงานอยู่แล้วที่พอร์ต $Port"; exit 0 }
if (-not (Get-Process | Where-Object { $_.ProcessName -match 'comfy' })) {
    $menus = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    $lnk = Get-ChildItem $menus -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match 'comfy' } | Select-Object -First 1
    if (-not $lnk) { Write-AiLog $LogFile 'ERROR: ไม่พบ shortcut ของ ComfyUI ใน Start menu'; exit 1 }
    Start-Process $lnk.FullName
    Write-AiLog $LogFile "เปิดแอป $($lnk.BaseName)"
}

# 3. รอให้ ComfyUI ตอบ (สูงสุด 5 นาที)
for ($i = 0; $i -lt 60; $i++) {
    if (Test-Port $Port) { Write-AiLog $LogFile "OK: ComfyUI ตอบที่พอร์ต $Port"; exit 0 }
    Start-Sleep -Seconds 5
}
Write-AiLog $LogFile "WARN: ComfyUI ยังไม่ตอบที่พอร์ต $Port หลังรอ 5 นาที: RDP เข้าไปดูว่าแอปขึ้น Running หรือยัง"
exit 1
