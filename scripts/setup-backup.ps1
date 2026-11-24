#Requires -RunAsAdministrator
# เชื่อม NAS (SMB) และตั้ง backup อัตโนมัติทุกคืน
# รันใน Terminal แบบ Administrator ด้วยบัญชีเดียวกับที่ตั้ง Autologon:
#   .\scripts\setup-backup.ps1
# ต้องตั้งค่าบน NAS ตาม docs\install.md ขั้นที่ 8 ให้เสร็จก่อน
. "$PSScriptRoot\common.ps1"
$cfg = Read-AiConfig

$nasIp = Read-Host "IP ของ NAS [กด Enter เพื่อใช้ $($cfg.NasHost)]"
if ($nasIp) { $cfg.NasHost = $nasIp }
$hdd = Read-Host "ไดรฟ์สำหรับพักไฟล์และสำเนาเอกสาร (HDD) [กด Enter เพื่อใช้ $($cfg.HddDrive)]"
if ($hdd) { $cfg.HddDrive = $hdd.TrimEnd('\') }
Save-AiConfig $cfg

$nasUser = Read-Host 'ชื่อผู้ใช้บน NAS สำหรับ backup (เช่น ai-backup)'
Write-Host 'กำลังบันทึกรหัสผ่าน NAS ไว้ใน Windows Credential Manager (ระบบจะถามรหัสผ่าน)...'
cmdkey /add:$($cfg.NasHost) /user:$nasUser /pass

foreach ($share in 'ai-backup', 'ai-docs') {
    $p = "\\$($cfg.NasHost)\$share"
    if (Test-Path $p) { Write-Host "OK: เข้าถึง $p ได้" -ForegroundColor Green }
    else { Write-Host "เข้าถึง $p ไม่ได้: ตรวจชื่อ share สิทธิ์ของผู้ใช้ และรหัสผ่าน" -ForegroundColor Red; exit 1 }
}

# รันเฉพาะตอนบัญชีนี้ล็อกอินอยู่ (Autologon ทำให้ล็อกอินเสมอ) เพื่อใช้รหัส NAS ที่บันทึกไว้
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 3)
foreach ($t in @(
    @{ Name = 'Lek-AI Backup to NAS';   Script = 'backup-to-nas.ps1';   At = '02:00' },
    @{ Name = 'Lek-AI Mirror NAS docs'; Script = 'mirror-nas-docs.ps1'; At = '02:30' }
)) {
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$AiRoot\scripts\$($t.Script)`""
    $trigger = New-ScheduledTaskTrigger -Daily -At $t.At
    Register-ScheduledTask -TaskName $t.Name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "ตั้งงาน '$($t.Name)' ทุกวันเวลา $($t.At) แล้ว"
}

$ans = Read-Host 'ทดลอง backup ตอนนี้เลยไหม [Y/n]'
if ($ans -notmatch '^[Nn]') {
    & "$AiRoot\scripts\backup-to-nas.ps1"
    Get-ChildItem "\\$($cfg.NasHost)\ai-backup" -Directory | Sort-Object Name | Select-Object -Last 3 | Format-Table Name, LastWriteTime
}
