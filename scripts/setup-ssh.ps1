#Requires -RunAsAdministrator
# เปิด SSH บน server ให้สั่งงานจาก Mac ได้ เช่น  ssh ai-server ai free-gpu
# - รับเฉพาะเครื่องใน Tailscale (100.64.0.0/10) ไม่เปิดให้ LAN หรือ ZeroTier
# - ล็อกอินด้วย SSH key เท่านั้น ปิดการใช้รหัสผ่าน
# รันใน Terminal แบบ Administrator:
#   .\scripts\setup-ssh.ps1
# ระบบจะถาม public key ของ Mac (ดูได้ด้วย  cat ~/.ssh/id_ed25519.pub  บน Mac)

$ErrorActionPreference = 'Stop'

# 1. ติดตั้ง OpenSSH Server (มาพร้อม Windows แค่เปิดใช้)
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
if ($cap.State -ne 'Installed') {
    Write-Host 'กำลังติดตั้ง OpenSSH Server (อาจใช้เวลา 1-3 นาที)...'
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
}
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd   # รันครั้งแรกเพื่อให้ระบบสร้าง C:\ProgramData\ssh\sshd_config

# 2. public key ของ Mac
$key = (Read-Host 'วาง public key ของ Mac (บรรทัดที่ขึ้นต้นด้วย ssh-ed25519)').Trim()
if ($key -notmatch '^ssh-(ed25519|rsa) ') { Write-Host 'รูปแบบ key ไม่ถูกต้อง' -ForegroundColor Red; exit 1 }

# บัญชีนี้อยู่ในกลุ่ม Administrators: Windows อ่าน key จาก administrators_authorized_keys
$auth = 'C:\ProgramData\ssh\administrators_authorized_keys'
$existing = if (Test-Path $auth) { Get-Content $auth } else { @() }
if ($existing -notcontains $key) { Add-Content -Path $auth -Value $key -Encoding ascii }
# ไฟล์นี้ต้องให้เฉพาะ Administrators และ SYSTEM อ่านได้ ไม่งั้น sshd จะไม่ยอมใช้
icacls.exe $auth /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

# 3. ปิดการล็อกอินด้วยรหัสผ่าน (ใช้ key อย่างเดียว)
$cfgPath = 'C:\ProgramData\ssh\sshd_config'
$cfg = Get-Content $cfgPath
$cfg = $cfg | Where-Object { $_ -notmatch '^\s*#?\s*PasswordAuthentication\s' }
$cfg = @('PasswordAuthentication no') + $cfg
Set-Content -Path $cfgPath -Value $cfg -Encoding ascii

# 4. ใช้ PowerShell เป็น shell เริ่มต้น (คำสั่ง ai อยู่ใน PATH แล้ว)
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -PropertyType String -Force `
    -Value "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" | Out-Null

# 5. firewall: พอร์ต 22 เฉพาะ Tailscale
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
$rule = 'Lek-AI SSH 22 (Tailscale)'
if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP -LocalPort 22 `
        -RemoteAddress 100.64.0.0/10 -Action Allow -Profile Private | Out-Null
}

Restart-Service sshd
Write-Host ''
Write-Host "เสร็จแล้ว บน Mac ลองสั่ง:  ssh $($env:USERNAME)@$($env:COMPUTERNAME.ToLower()) ai status" -ForegroundColor Green
