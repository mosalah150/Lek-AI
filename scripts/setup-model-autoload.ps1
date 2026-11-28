#Requires -RunAsAdministrator
# ตั้งให้โหลดโมเดลแชทด้วย context เต็มทุกครั้งที่ล็อกอิน (Autologon ทำให้ล็อกอินเองหลังบูต)
# ถ้าปล่อยให้ LM Studio โหลดเองตอนมีคนแชท จะได้ context ค่าเริ่มต้นที่เล็กกว่าและแบ่งให้หลายแชท
# ทำให้แอปแบบ agent (เช่น OpenBot) ใช้ไม่ได้
# รันใน Terminal แบบ Administrator ด้วยบัญชีเดียวกับที่ตั้ง Autologon:
#   .\scripts\setup-model-autoload.ps1
. "$PSScriptRoot\common.ps1"
$TaskName = 'Lek-AI Load chat model'

if ((Resolve-Path $PSScriptRoot).Path -ne "$AiRoot\scripts") {
    Copy-Item "$PSScriptRoot\*.ps1" "$AiRoot\scripts\" -Force
}

# หน่วง 2 นาทีให้ LM Studio (headless service) เริ่มก่อน
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$AiRoot\scripts\ai.ps1`" load-model"
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$trigger.Delay = 'PT2M'
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
$m = Get-ChatModelConfig
Write-Host "ตั้งงาน '$TaskName' แล้ว: โหลด $($m.Model) context $($m.ContextLength) ทุกครั้งที่ล็อกอิน" -ForegroundColor Green
