#Requires -RunAsAdministrator
# ติดตั้ง Lek-AI บน Windows 11 Pro แบบไม่ใช้ Docker
# วิธีใช้ (Terminal แบบ Administrator ในโฟลเดอร์ของ repo):
#   Set-ExecutionPolicy -Scope Process Bypass
#   .\scripts\install.ps1
# รันซ้ำได้อย่างปลอดภัย: ขั้นที่ทำไปแล้วจะถูกข้ามหรือทำซ้ำโดยไม่เสียหาย

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

function Step([string]$m) { Write-Host "`n==> $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "[!] $m" -ForegroundColor Yellow }

function Install-WingetPackage([string]$id) {
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Warn "winget $id จบด้วยรหัส $LASTEXITCODE (ถ้าติดตั้งอยู่แล้ว ไม่ต้องกังวล)" }
}

# ------------------------------------------------------------------ 0. ตรวจเบื้องต้น
$os = (Get-CimInstance Win32_OperatingSystem).Caption
if ($os -notmatch 'Pro|Enterprise|Education') { Warn "ระบบนี้คือ $os แนะนำ Windows 11 Pro เพื่อใช้ Remote Desktop และตั้งค่า Windows Update ได้" }
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'ไม่พบ winget: อัปเดต App Installer จาก Microsoft Store ก่อน' }

# ------------------------------------------------------------------ 1. ไฟและการนอนหลับ
Step '1/7 ตั้งค่าให้เครื่องไม่หลับ'
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 15
powercfg /hibernate off

# ------------------------------------------------------------------ 2. Windows Update
Step '2/7 Windows Update: ดาวน์โหลดเอง แต่ไม่รีสตาร์ตเองขณะมีคนล็อกอิน'
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
New-Item -Path $wu -Force | Out-Null
Set-ItemProperty -Path $wu -Name NoAutoUpdate -Value 0 -Type DWord
Set-ItemProperty -Path $wu -Name AUOptions -Value 3 -Type DWord                       # ดาวน์โหลดเอง แจ้งให้ติดตั้ง
Set-ItemProperty -Path $wu -Name NoAutoRebootWithLoggedOnUsers -Value 1 -Type DWord

# ------------------------------------------------------------------ 3. Remote Desktop และ firewall
Step '3/7 เปิด Remote Desktop และตั้ง firewall'
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'                               # กลุ่ม Remote Desktop (ใช้ได้ทุกภาษา)
Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' } |
    Set-NetConnectionProfile -NetworkCategory Private                                 # เครือข่ายในบ้าน = Private

if (-not (Get-NetFirewallRule -DisplayName 'Lek-AI Open WebUI 3000' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Lek-AI Open WebUI 3000' -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow -Profile Private | Out-Null
}
if (-not (Get-NetFirewallRule -DisplayName 'Lek-AI block LM Studio 1234' -ErrorAction SilentlyContinue)) {
    # LM Studio ไม่มีระบบยืนยันตัวตน: ห้ามเครื่องอื่นเรียกตรง (Open WebUI ในเครื่องเดียวกันยังใช้ได้)
    New-NetFirewallRule -DisplayName 'Lek-AI block LM Studio 1234' -Direction Inbound -Protocol TCP -LocalPort 1234 -Action Block -Profile Any | Out-Null
}

# ------------------------------------------------------------------ 4. โปรแกรม
Step '4/7 ติดตั้ง Python 3.11, Tailscale และ LM Studio'
Install-WingetPackage 'Python.Python.3.11'
Install-WingetPackage 'Tailscale.Tailscale'
Install-WingetPackage 'ElementLabs.LMStudio'

$py = $null
foreach ($c in @("$env:ProgramFiles\Python311\python.exe", "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe")) {
    if (Test-Path $c) { $py = $c; break }
}
if (-not $py) { throw 'ไม่พบ Python 3.11: ปิดแล้วเปิด Terminal ใหม่ แล้วรันสคริปต์นี้อีกครั้ง' }

# ------------------------------------------------------------------ 5. Open WebUI
Step '5/7 ติดตั้ง Open WebUI (ครั้งแรกใช้เวลาราว 5-15 นาที)'
foreach ($d in @("$AiRoot\open-webui\data", "$AiRoot\hf-cache", "$AiRoot\scripts", $LogDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
$venvPy = "$AiRoot\open-webui\venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) { & $py -m venv "$AiRoot\open-webui\venv" }
& $venvPy -m pip install --upgrade pip
& $venvPy -m pip install --upgrade open-webui
if ($LASTEXITCODE -ne 0) { throw 'ติดตั้ง open-webui ไม่สำเร็จ: ดูข้อความ error ด้านบน' }

# สคริปต์ดูแลระบบ
if ((Resolve-Path $PSScriptRoot).Path -ne "$AiRoot\scripts") {
    Copy-Item "$PSScriptRoot\*.ps1" "$AiRoot\scripts\" -Force
}
Set-Content -Path "$AiRoot\ai.cmd" -Encoding ASCII -Value '@powershell -NoProfile -ExecutionPolicy Bypass -File "C:\ai\scripts\ai.ps1" %*'
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($machinePath -notlike "*$AiRoot;*" -and -not $machinePath.EndsWith($AiRoot)) {
    [Environment]::SetEnvironmentVariable('Path', "$machinePath;$AiRoot", 'Machine')
}

# ค่าตั้งและรหัสลับ (สร้างครั้งเดียว)
if (-not (Test-Path $ConfigPath)) {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $secret = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    $hdd = (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.DriveLetter -ne 'C' } |
            Sort-Object Size -Descending | Select-Object -First 1).DriveLetter
    $cfg = [pscustomobject]@{
        SecretKey = $secret
        WebUIUrl  = ''
        NasHost   = '192.168.1.10'
        HddDrive  = $(if ($hdd) { "${hdd}:" } else { 'C:' })
    }
    Save-AiConfig $cfg
    icacls $ConfigPath /inheritance:r /grant:r 'Administrators:F' 'SYSTEM:F' "$($env:USERNAME):F" | Out-Null
    Warn "สร้างรหัสลับไว้ที่ $ConfigPath แล้ว (backup จะเก็บไฟล์นี้ไปที่ NAS ให้)"
}

# ให้ Open WebUI เริ่มเองตอนเครื่องบูต (ไม่ต้องรอใครล็อกอิน)
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$AiRoot\scripts\start-open-webui.ps1`""
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
Register-ScheduledTask -TaskName $WebUITask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Stop-OpenWebUI
Start-OpenWebUI

# ------------------------------------------------------------------ 6. Tailscale
Step '6/7 Tailscale (เข้าใช้จากข้างนอก + HTTPS)'
$ts = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $ts) {
    # PowerShell 5.1: ข้อความ stderr ของโปรแกรมภายนอกจะกลายเป็น error ถ้าตั้ง Stop ไว้ จึงผ่อนชั่วคราว
    $ErrorActionPreference = 'Continue'
    & $ts status *> $null
    if ($LASTEXITCODE -ne 0) {
        Warn 'เปิดลิงก์ที่จะแสดงด้านล่างในเบราว์เซอร์ เพื่อล็อกอิน Tailscale'
        & $ts up --unattended --hostname=ai-server
    }
    & $ts serve --bg 3000
    $serveOk = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = 'Stop'
    if ($serveOk) {
        $dns = (((& $ts status --json) | Out-String | ConvertFrom-Json).Self.DNSName).TrimEnd('.')
        $cfg = Read-AiConfig
        if ($cfg.WebUIUrl -ne "https://$dns") {
            $cfg.WebUIUrl = "https://$dns"
            Save-AiConfig $cfg
            Stop-OpenWebUI
            Start-OpenWebUI
        }
    } else {
        Warn 'tailscale serve ยังใช้ไม่ได้: เปิด MagicDNS และ HTTPS Certificates ที่ Tailscale admin > DNS แล้วรันสคริปต์นี้อีกครั้ง'
    }
} else {
    Warn 'ไม่พบ Tailscale: ติดตั้งจาก tailscale.com แล้วรันสคริปต์นี้อีกครั้ง'
}

# ------------------------------------------------------------------ 7. สรุป
Step '7/7 รอ Open WebUI เริ่มทำงาน (ครั้งแรกอาจนานหลายนาที เพราะต้องดาวน์โหลดโมเดล embedding)'
$ok = $false
for ($i = 0; $i -lt 60; $i++) { if (Test-OpenWebUI) { $ok = $true; break }; Start-Sleep -Seconds 10 }
if (-not $ok) { Warn 'Open WebUI ยังไม่ตอบ: รอสักครู่แล้วตรวจด้วยคำสั่ง  ai status  หรือดู log ด้วย  ai logs' }

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.|100\.)' } |
        Select-Object -First 1).IPAddress
$url = (Read-AiConfig).WebUIUrl
Write-Host @"

=============================================================
 ติดตั้งเสร็จแล้ว
-------------------------------------------------------------
 Open WebUI (ใน LAN)   : http://${lan}:3000
 Open WebUI (ข้างนอก)  : $(if ($url) { $url } else { 'ยังไม่ได้ตั้ง Tailscale Serve' })
 Remote Desktop        : $lan  (หรือ ai-server ผ่าน Tailscale)
-------------------------------------------------------------
 ขั้นต่อไป (ดู docs\install.md):
  1. เปิด LM Studio ดาวน์โหลดโมเดล และเปิด server (ขั้นที่ 5)
  2. ตั้ง Autologon (ขั้นที่ 6)
  3. เปิด Open WebUI แล้วสมัครบัญชีแรก (จะเป็น admin)
  4. ตั้ง backup:  .\scripts\setup-backup.ps1
 คำสั่งลัด: เปิด Terminal ใหม่ แล้วพิมพ์  ai help
=============================================================
"@
