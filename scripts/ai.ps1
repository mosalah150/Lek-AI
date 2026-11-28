# คำสั่งลัดสำหรับดูแล Lek-AI บน Windows
# ใช้ผ่าน  ai <คำสั่ง>  ใน Terminal (คำสั่ง update / restart / backup ต้องเปิด Terminal แบบ Administrator)
param([string]$Command = 'help', [string]$Arg = '')
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # ให้ภาษาไทยแสดงถูกเมื่อสั่งผ่าน SSH
. "$PSScriptRoot\common.ps1"

function Show-Section([string]$t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }

switch ($Command) {
    'status' {
        Show-Section 'Open WebUI'
        if (Test-OpenWebUI) { Write-Host 'ทำงานปกติ  http://127.0.0.1:3000' -ForegroundColor Green }
        else { Write-Host 'ไม่ตอบ: ลอง  ai restart  แล้วดู  ai logs' -ForegroundColor Red }

        Show-Section 'LM Studio'
        try {
            $m = Invoke-RestMethod -Uri 'http://127.0.0.1:1234/v1/models' -TimeoutSec 5
            Write-Host 'server ทำงานปกติ โมเดลที่เรียกใช้ได้:' -ForegroundColor Green
            $m.data | ForEach-Object { Write-Host "  - $($_.id)" }
        } catch { Write-Host 'server ไม่ตอบ: เปิด LM Studio แล้วเปิด server ที่แท็บ Developer' -ForegroundColor Red }

        Show-Section 'GPU'
        nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader

        Show-Section 'ดิสก์'
        Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } |
            Select-Object DriveLetter, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB)}}, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}} |
            Format-Table -AutoSize

        Show-Section 'Backup ล่าสุด'
        $bl = Join-Path $LogDir 'backup.log'
        if (Test-Path $bl) { Get-Content $bl -Tail 3 } else { Write-Host 'ยังไม่เคย backup: รัน scripts\setup-backup.ps1' }

        Show-Section 'Tailscale'
        $ts = "$env:ProgramFiles\Tailscale\tailscale.exe"
        if (Test-Path $ts) { & $ts status | Select-Object -First 5 }
    }
    'logs' {
        Get-Content (Join-Path $LogDir 'open-webui.log') -Tail 100 -Wait
    }
    'restart' {
        Stop-OpenWebUI; Start-OpenWebUI
        Write-Host 'รีสตาร์ต Open WebUI แล้ว รอราว 1 นาทีแล้วตรวจด้วย  ai status'
    }
    'models' {
        $lms = Get-LmsPath
        if ($lms) { & $lms ls } else { Write-Host 'ไม่พบคำสั่ง lms: เปิด LM Studio หนึ่งครั้ง แล้วรัน  %USERPROFILE%\.lmstudio\bin\lms.exe bootstrap' }
    }
    'free-gpu' {
        $lms = Get-LmsPath
        if ($lms) {
            & $lms unload --all
            Write-Host 'คืน VRAM จาก LM Studio แล้ว'
            Write-Host 'ใช้ ComfyUI เสร็จแล้วให้รัน  ai load-model  เพื่อโหลดโมเดลแชทกลับด้วย context เต็ม (ถ้าปล่อยให้โหลดเอง context จะเล็กลง)'
        }
        else { Write-Host 'ไม่พบคำสั่ง lms: ใช้ปุ่ม Eject ในหน้าจอ LM Studio แทน' }
    }
    'load-model' {
        # โหลดโมเดลแชทด้วยค่าที่เหมาะกับเครื่องนี้ (context ยาว, ทีละ 1 แชท) และไม่ปลดเองเมื่อว่าง
        $lms = Get-LmsPath
        if (-not $lms) { Write-Host 'ไม่พบคำสั่ง lms' -ForegroundColor Red; break }
        $m = Get-ChatModelConfig
        & $lms unload --all 2>&1 | Out-Null
        & $lms load $m.Model -c $m.ContextLength --parallel 1 --gpu max --no-speculative-draft-mtp -y
        & $lms ps
    }
    'backup' {
        & "$PSScriptRoot\backup-to-nas.ps1"
    }
    'update' {
        Write-Host 'สำรองข้อมูลก่อนอัปเดต...'
        & "$PSScriptRoot\backup-to-nas.ps1"
        if ($LASTEXITCODE -ne 0) { Write-Host 'backup ไม่สำเร็จ: ยกเลิกการอัปเดต' -ForegroundColor Red; break }
        Stop-OpenWebUI
        & (Join-Path $AiRoot 'open-webui\venv\Scripts\python.exe') -m pip install --upgrade open-webui
        Start-OpenWebUI
        Write-Host 'อัปเดต Open WebUI แล้ว · LM Studio อัปเดตผ่านหน้าจอของโปรแกรมเอง · ตรวจด้วย  ai status'
    }
    default {
        Write-Host @'
คำสั่ง ai:
  ai status      ดูสถานะ Open WebUI, LM Studio, GPU, ดิสก์, backup และ Tailscale
  ai logs        ดู log ของ Open WebUI (กด Ctrl+C เพื่อออก)
  ai restart     รีสตาร์ต Open WebUI                       (ต้องใช้ Terminal แบบ Administrator)
  ai models      ดูโมเดลที่ดาวน์โหลดไว้ใน LM Studio
  ai free-gpu    คืน VRAM ทันที (ก่อนใช้ ComfyUI)
  ai load-model  โหลดโมเดลแชทด้วย context เต็ม (หลังใช้ ComfyUI เสร็จ)
  ai backup      สำรองข้อมูลไป NAS ทันที                    (ต้องใช้ Terminal แบบ Administrator)
  ai update      backup แล้วอัปเดต Open WebUI                (ต้องใช้ Terminal แบบ Administrator)
'@
    }
}
