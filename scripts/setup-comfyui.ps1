#Requires -RunAsAdministrator
# ตั้งให้ ComfyUI Desktop เปิดเองหลังล็อกอิน และเปิดจาก Mac ผ่าน Tailscale ได้ที่ https://<เครื่อง>.<tailnet>.ts.net:8443
# ติดตั้ง ComfyUI Desktop ให้เสร็จก่อน แล้วรันใน Terminal แบบ Administrator ด้วยบัญชีเดียวกับที่ตั้ง Autologon:
#   .\scripts\setup-comfyui.ps1
# หมายเหตุ: ComfyUI ไม่มีระบบล็อกอิน ทุกเครื่องใน tailnet เดียวกันเปิดได้
. "$PSScriptRoot\common.ps1"
$TaskName = 'Lek-AI ComfyUI'

$p = Read-Host 'พอร์ตของ ComfyUI (ดูช่อง Port ในหน้า Overview ของแอป) [กด Enter เพื่อใช้ 8188]'
$port = if ($p) { [int]$p.Trim() } else { 8188 }

# Task Scheduler รันสคริปต์จาก C:\ai\scripts
if ((Resolve-Path $PSScriptRoot).Path -ne "$AiRoot\scripts") {
    Copy-Item "$PSScriptRoot\*.ps1" "$AiRoot\scripts\" -Force
}

# เปิดพอร์ต 8443 เฉพาะเครื่องใน Tailscale (100.64.0.0/10)
$rule = 'Lek-AI ComfyUI 8443 (Tailscale)'
if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP -LocalPort 8443 `
        -RemoteAddress 100.64.0.0/10 -Action Allow -Profile Private | Out-Null
}

# รันตอนบัญชีนี้ล็อกอิน (Autologon ทำให้ล็อกอินเสมอ) หน่วง 1 นาทีให้ Tailscale กับ LM Studio ขึ้นก่อน
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$AiRoot\scripts\start-comfyui.ps1`" -Port $port"
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$trigger.Delay = 'PT1M'
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "ตั้งงาน '$TaskName' ให้รันทุกครั้งที่ล็อกอินแล้ว (พอร์ต $port)" -ForegroundColor Green

Write-Host 'กำลังทดลองรัน...'
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 15
Get-Content (Join-Path $LogDir 'comfyui.log') -Tail 5 -ErrorAction SilentlyContinue
