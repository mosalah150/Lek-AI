# คู่มือติดตั้ง Lek-AI บน Windows (ไม่ใช้ Docker)

AI Server เปิดทิ้งไว้ · จัดการจาก MacBook ผ่าน Remote Desktop · เหมาะกับผู้ใช้ 1–10 คน

> ภาพรวมโครงการอยู่ที่ [README](../README.md) · คู่มือนี้ต่อ server และ NAS เข้า router บ้านโดยตรง ถ้าอยู่คนละชั้นและไม่มีสาย LAN ถึง router ให้ดู [คู่มือเครือข่าย MikroTik](network-mikrotik.md) (ตัวเลือก) · ชุดติดตั้ง Ubuntu อยู่ที่ [`_ubuntu-version/`](../_ubuntu-version/)

## สิ่งที่จะได้

```
ผู้ใช้ (เบราว์เซอร์) ──► Open WebUI :3000 ──► LM Studio :1234 (เฉพาะในเครื่อง) ──► RTX 6000
                       บัญชี, สิทธิ์, RAG      โหลดโมเดล, API
คุณ (Remote Desktop) ──► LM Studio: ดาวน์โหลดและทดลองโมเดล · ComfyUI: สร้างภาพ/วิดีโอ
ข้างนอกบ้าน ──► Tailscale ──► https://ai-server.<tailnet>.ts.net
ทุกคืน ──► backup ไป NAS (SMB)
```

| โปรแกรม | ติดตั้งแบบ | หน้าที่ |
|---|---|---|
| **LM Studio** | โปรแกรม Windows | เครื่องยนต์ AI: ดาวน์โหลดและรันโมเดลบน GPU |
| **Open WebUI** | Python (ติดตั้งให้โดยสคริปต์) | หน้าแชทของทีม: บัญชีผู้ใช้ ประวัติแชท และถามตอบเอกสาร (RAG) |
| **Tailscale** | โปรแกรม Windows | เข้าใช้จากข้างนอก + HTTPS ที่ถูกต้อง |
| ComfyUI Desktop | โปรแกรม Windows (ตัวเลือก) | สร้างภาพ วิดีโอ และ asset เกม |

**ค่าที่ใช้ในคู่มือ:** ทุกเครื่องต่อสาย LAN เข้า router บ้าน (`192.168.1.1`) · server `192.168.1.20` · NAS `192.168.1.10` ถ้าเครือข่ายของคุณต่างจากนี้ ให้แทนด้วย IP จริง

**เลือก IP ตายตัวให้อยู่นอกช่วงที่ router แจกอัตโนมัติ (DHCP pool)** ดูได้ในหน้า LAN ของ router เช่น router ของ True มักแจก `.33–.254` ดังนั้น `.10` และ `.20` จะไม่ชนกับเครื่องอื่น

---

## ขั้นที่ 1: ติดตั้ง Windows 11 Pro

> ⚠️ **การติดตั้งใหม่จะลบข้อมูลบนดิสก์ที่เลือก** สำรองไฟล์สำคัญออกก่อน

1. **BIOS ของ Dell 5820** (กด F2 ตอนเปิดเครื่อง): Power Management > **AC Recovery = Power On** (เปิดเครื่องเองเมื่อไฟกลับมา)
2. ทำ USB ติดตั้งด้วย **Media Creation Tool** จาก microsoft.com แล้วติดตั้ง **Windows 11 Pro** ลง **NVMe** (ระวังอย่าเลือก HDD)
3. ตั้งชื่อเครื่องเป็น `ai-server`
4. ติดตั้ง **NVIDIA RTX Enterprise Driver** (driver สำหรับการ์ดตระกูล Quadro) จาก nvidia.com แล้วรีสตาร์ต
5. Windows Update ให้ครบจนไม่มีอัปเดตเหลือ แล้วรีสตาร์ต
6. เสียบสาย LAN เข้า router แล้วตั้ง IP ตายตัว: **Settings > Network & internet > Ethernet > IP assignment > Edit > Manual** เปิด IPv4 แล้วใส่
   - IP address `192.168.1.20` · Subnet mask `255.255.255.0` · Gateway `192.168.1.1`
   - Preferred DNS `192.168.1.1` · Alternate DNS `1.1.1.1`

   จากนั้นทดสอบใน Terminal: `ping 192.168.1.10` (NAS) และ `ping google.com`

**HDD 2TB:** เปิด **Disk Management** ถ้า HDD ยังไม่มีไดรฟ์ ให้คลิกขวา > New Simple Volume (ระวัง: การ format จะลบข้อมูลบน HDD) แล้วจดตัวอักษรไดรฟ์ไว้ เช่น `D:`

## ขั้นที่ 2: ดาวน์โหลดชุดติดตั้ง

บน server เปิดเบราว์เซอร์ไปที่ `https://github.com/mosalah150/Lek-AI` > ปุ่ม **Code** > **Download ZIP** แล้วแตกไฟล์ไว้ที่ `C:\Lek-AI`

## ขั้นที่ 3: รันสคริปต์ติดตั้ง (ประมาณ 20–30 นาที)

คลิกขวาที่ปุ่ม Start > **Terminal (Admin)** แล้วรันทีละบรรทัด:

```powershell
cd C:\Lek-AI
```

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

```powershell
.\scripts\install.ps1
```

สคริปต์ทำให้ทั้งหมด:
- ตั้งเครื่องไม่ให้หลับ และให้ Windows Update **ไม่รีสตาร์ตเอง**
- เปิด Remote Desktop
- เปิด firewall พอร์ต 3000 ให้ใน LAN และ**ปิดพอร์ต 1234 ของ LM Studio** ไม่ให้เครื่องอื่นเรียกตรง
- ติดตั้ง Python, Tailscale, LM Studio และ Open WebUI
- ตั้งให้ Open WebUI **เริ่มเองตอนบูต** โดยไม่ต้องรอใครล็อกอิน
- สร้างรหัสลับไว้ที่ `C:\ai\config.json`

ระหว่างทาง สคริปต์จะแสดง**ลิงก์ล็อกอิน Tailscale** ให้เปิดในเบราว์เซอร์แล้วล็อกอิน

> ถ้าสคริปต์หยุดเพราะหา Python ไม่เจอ ให้ปิด Terminal เปิดใหม่แบบ Admin แล้วรันซ้ำ (รันซ้ำได้อย่างปลอดภัย)

## ขั้นที่ 4: Tailscale

1. ติดตั้ง **Tailscale** บน MacBook (App Store) แล้วล็อกอิน**บัญชีเดียวกัน**
2. https://login.tailscale.com/admin/dns: เปิด **MagicDNS** และ **HTTPS Certificates**
3. https://login.tailscale.com/admin/machines: ที่เครื่อง `ai-server` > ⋯ > **Disable key expiry** (ไม่อย่างนั้นเครื่องจะหลุดทุก 180 วัน)
4. ถ้าขั้นที่ 3 มีข้อความเตือนเรื่อง `tailscale serve` ให้รัน `.\scripts\install.ps1` อีกรอบ

ผลที่ได้: เปิด Open WebUI ได้จากทุกที่ที่ `https://ai-server.<ชื่อ-tailnet>.ts.net` พร้อมรูปแม่กุญแจถูกต้อง

## ขั้นที่ 5: ตั้งค่า LM Studio

เปิด **LM Studio** จากเมนู Start (ชื่อเมนูอาจต่างเล็กน้อยตามเวอร์ชัน)

**5.1 ดาวน์โหลดโมเดล** (แท็บ Discover หรือรูปแว่นขยาย):

| โมเดล | ใช้ทำ | ขนาดโดยประมาณ |
|---|---|---|
| **Qwen3 30B A3B** (GGUF, Q4_K_M) | ตัวหลัก: แชท สรุป RAG ภาษาไทย | ~18GB |
| **Qwen3 Coder 30B A3B** (GGUF, Q4_K_M) | เขียนโค้ด | ~18GB |

LM Studio จะบอกว่าโมเดลใส่ใน VRAM ได้พอดีหรือไม่ ให้เลือกรุ่นที่ขึ้นว่า **Full GPU Offload** ได้ (รุ่นใหม่ออกบ่อย ใช้รุ่นล่าสุดที่ใกล้เคียงได้)

**5.2 เปิด server** (แท็บ **Developer**):
- เปิดสวิตช์ **Status: Running** ที่พอร์ต `1234`
- **ปิด** Serve on Local Network (ให้รับเฉพาะในเครื่อง เพราะ Open WebUI อยู่เครื่องเดียวกัน)
- เปิด **Just-in-Time model loading** และตั้ง **Auto unload** เมื่อว่าง 10–30 นาที (คืน VRAM ให้ ComfyUI)

**5.3 ให้ server เริ่มเองหลังบูต** (Settings): เปิดตัวเลือกประมาณ **Run LLM server on login** / ใช้งานแบบ headless

**5.4 ติดตั้งคำสั่ง `lms`** (ใช้กับคำสั่ง `ai models` และ `ai free-gpu`): เปิด Terminal ใหม่แล้วรัน

```powershell
& "$env:USERPROFILE\.lmstudio\bin\lms.exe" bootstrap
```

**5.5 ตั้งค่าโมเดล:** ในหน้าโหลดโมเดล ตั้ง **Context Length** ราว 16,000–32,000 และ **GPU Offload** สูงสุด

## ขั้นที่ 6: Autologon (ให้ระบบขึ้นเองหลังไฟดับ)

LM Studio เริ่มทำงานเมื่อมีคนล็อกอินเท่านั้น จึงต้องให้ Windows ล็อกอินเอง:

1. ดาวน์โหลด **Autologon** จาก Microsoft Sysinternals (learn.microsoft.com/sysinternals) แล้วตั้งให้บัญชีของคุณ (เครื่องมือนี้เก็บรหัสผ่านแบบเข้ารหัส)
2. สั่งล็อกหน้าจอทันทีหลังล็อกอินอัตโนมัติ เพื่อไม่ให้คนที่เดินผ่านใช้เครื่องได้ (Terminal แบบ Admin):

```powershell
schtasks /Create /TN "Lek-AI Lock after autologon" /TR "rundll32.exe user32.dll,LockWorkStation" /SC ONLOGON /RU $env:USERNAME /DELAY 0002:00
```

3. ทดสอบ: รีสตาร์ตเครื่อง รอ 5 นาที แล้วรัน `ai status` ผ่าน Remote Desktop ต้องเห็นทั้ง Open WebUI และ LM Studio ทำงาน

## ขั้นที่ 7: ตั้งค่า Open WebUI ครั้งแรก

1. เปิด `http://localhost:3000` (หรือ URL ของ Tailscale) แล้วสมัครบัญชีแรก บัญชีนี้จะเป็น **admin**
2. **Admin Settings > Connections:** ตรวจว่ามีการเชื่อมต่อแบบ OpenAI ที่ `http://127.0.0.1:1234/v1` และเห็นโมเดลจาก LM Studio
3. **Admin Settings > Documents:** ตรวจว่า Embedding Model เป็น `BAAI/bge-m3` และเปิด Hybrid Search กับ Reranking (`BAAI/bge-reranker-v2-m3`) ไว้ ครั้งแรกระบบจะดาวน์โหลดโมเดลเหล่านี้ให้เอง (ราว 3GB)
4. **Admin Settings > Models:** ตั้งโมเดลหลักเป็นค่าเริ่มต้น
5. ใช้คนเดียว: **Admin Settings > General > ปิด Enable New Sign Ups** ได้เลย · ใช้หลายคน: ให้ทุกคนสมัครก่อน อนุมัติที่ Admin Panel > Users แล้วค่อยปิด
6. (หลายคน) สร้าง **Groups** ตามแผนก และ **Knowledge** แยกตามกลุ่ม

## ขั้นที่ 8: NAS และ backup

### บน DSM
1. สร้าง Shared Folder `ai-docs` (เอกสารสำหรับ AI) และ `ai-backup`
2. สร้างผู้ใช้ `ai-backup` บน NAS:
   - `ai-backup`: **Read/Write**
   - `ai-docs`: **Read only**
   - **ห้ามให้ผู้ใช้อื่นเข้า `ai-backup`** เพราะมีไฟล์รหัสลับ `config.json`
3. **Snapshot Replication:** snapshot ทั้งสองโฟลเดอร์ทุกชั่วโมง เก็บ 14 วัน (ต้องเป็น volume แบบ Btrfs ถ้าเป็น ext4 ให้ข้ามข้อนี้ และเปิด Recycle Bin ของ `ai-docs` แทน)
4. Control Panel > Hardware & Power: ✅ **Restart automatically when power supply issue is fixed**

### บน server (Terminal แบบ Admin)

```powershell
cd C:\Lek-AI
```

```powershell
.\scripts\setup-backup.ps1
```

สคริปต์จะถาม IP ของ NAS, ไดรฟ์ของ HDD และผู้ใช้/รหัสผ่านของ NAS แล้วตั้ง backup ทุกคืน และทดลอง backup ให้หนึ่งครั้ง

| ข้อมูล | ต้นฉบับ | สำเนา |
|---|---|---|
| แชท, ผู้ใช้, Knowledge, ค่าตั้ง | `C:\ai` บน NVMe | NAS `ai-backup` ทุกคืน 02:00 (เก็บ 14 วัน) |
| เอกสาร | NAS `ai-docs` | HDD ของ server ทุกคืน 02:30 |
| โมเดล | LM Studio บน NVMe | ไม่ต้อง backup เพราะดาวน์โหลดใหม่ได้ |

## ขั้นที่ 9 (ตัวเลือก): ComfyUI

1. ดาวน์โหลด **ComfyUI Desktop** สำหรับ Windows จาก comfy.org แล้วติดตั้ง (เก็บโมเดลไว้บน NVMe)
2. ก่อนสร้างภาพ ให้คืน VRAM จาก LM Studio ด้วย `ai free-gpu`
3. เปิดจาก MacBook ผ่าน Tailscale (Terminal แบบ Admin บน server):

```powershell
& "$env:ProgramFiles\Tailscale\tailscale.exe" serve --bg --https=8443 8000
```

แล้วเปิด `https://ai-server.<tailnet>.ts.net:8443` (เปลี่ยน `8000` เป็นพอร์ตที่ ComfyUI ใช้จริง ดูได้ในหน้าตั้งค่าของ ComfyUI)

**ตรวจ license ของแต่ละโมเดลก่อนนำภาพไปใช้เชิงพาณิชย์**

---

## ใช้งานประจำวัน

**จัดการจาก MacBook:** ติดตั้ง **Windows App** (ชื่อเดิม Microsoft Remote Desktop) จาก App Store แล้วเชื่อมไปที่ `192.168.1.20` (ในบ้าน) หรือ `ai-server` (ผ่าน Tailscale จากที่ไหนก็ได้)

**คำสั่ง `ai`** (เปิด Terminal บน server):

| คำสั่ง | ใช้เมื่อ |
|---|---|
| `ai status` | อยากรู้ว่าระบบปกติไหม |
| `ai logs` | มีปัญหา อยากดู log ของ Open WebUI (Ctrl+C เพื่อออก) |
| `ai restart` | Open WebUI ค้าง (Terminal แบบ Admin) |
| `ai models` | ดูโมเดลใน LM Studio |
| `ai free-gpu` | ก่อนใช้ ComfyUI |
| `ai backup` | สำรองข้อมูลทันที (Terminal แบบ Admin) |
| `ai update` | อัปเดต Open WebUI โดย backup ให้ก่อน (Terminal แบบ Admin) |

**ที่อยู่สำหรับใช้งาน:**

| | ในบ้าน | นอกบ้าน (Tailscale) |
|---|---|---|
| แชท AI | `http://192.168.1.20:3000` | `https://ai-server.<tailnet>.ts.net` |
| หน้าจัดการ NAS (DSM) | `https://192.168.1.10:5001` | `https://<ชื่อ-NAS>:5001` (ชื่อ NAS ใน Tailscale) |
| ไฟล์ NAS (Mac: Finder > ⌘K) | `smb://192.168.1.10` | `smb://<ชื่อ-NAS>` |

## ดูแลเดือนละครั้ง (ประมาณ 15 นาที)

1. `ai update` (Terminal แบบ Admin)
2. LM Studio: ติดตั้งอัปเดตเมื่อโปรแกรมแจ้ง
3. Windows Update: ติดตั้งแล้วรีสตาร์ตด้วยตัวเอง จากนั้นรอ 5 นาทีแล้ว `ai status`
4. ตรวจ backup: `ai status` ดูหัวข้อ Backup ล่าสุดต้องขึ้น `OK`
5. **ทดสอบกู้คืนอย่างน้อยไตรมาสละครั้ง** (ดูด้านล่าง)

## กู้คืน

1. ติดตั้งเครื่องใหม่ตามขั้นที่ 1–3
2. หยุด Open WebUI: `ai restart` จะเริ่มใหม่อัตโนมัติ ดังนั้นให้สั่ง `Stop-ScheduledTask "Lek-AI Open WebUI"` แทน
3. คัดลอกโฟลเดอร์ backup ล่าสุดจาก `\\192.168.1.10\ai-backup` มาไว้ที่เครื่อง แล้วแตกไฟล์:

```powershell
tar.exe -xzf .\open-webui-data.tgz -C C:\ai\open-webui
```

4. คัดลอก `config.json` จาก backup ทับ `C:\ai\config.json` (เพื่อใช้รหัสลับเดิม ไม่อย่างนั้นทุกคนจะต้องล็อกอินใหม่)
5. `Start-ScheduledTask "Lek-AI Open WebUI"` แล้วตรวจด้วย `ai status`

## แก้ปัญหาเบื้องต้น

| อาการ | ลองทำ |
|---|---|
| เปิดหน้าแชทไม่ได้ | `ai status` ถ้า Open WebUI ไม่ตอบ ให้ `ai restart` แล้วดู `ai logs` |
| หน้าแชทเปิดได้ แต่ไม่มีโมเดลให้เลือก | LM Studio ไม่ได้เปิด server: เปิดที่แท็บ Developer และตรวจขั้นที่ 5.3 |
| หลังไฟดับ เข้าไม่ได้ | รอ 5 นาที ถ้ายังไม่ได้ ตรวจว่าเครื่องเปิดอยู่ และ Autologon ทำงาน (ขั้นที่ 6) |
| AI ตอบช้าผิดปกติ | ดู GPU ใน `ai status` และตรวจในหน้าโหลดโมเดลของ LM Studio ว่า GPU Offload สูงสุด |
| ComfyUI แจ้งว่า VRAM ไม่พอ | `ai free-gpu` |
| backup ล้มเหลว | ดูหัวข้อ Backup ล่าสุดใน `ai status` ส่วนใหญ่เกิดจาก NAS ปิดหรือรหัสผ่าน NAS ถูกเปลี่ยน (รัน `setup-backup.ps1` ใหม่) |
| ไม่แน่ใจ | คัดลอกผลของ `ai status` และ `ai logs` มาถาม Claude ได้เลย |

## ความปลอดภัย

- **LM Studio รับคำขอเฉพาะในเครื่อง** และ firewall ปิดพอร์ต 1234 ไว้อีกชั้น เพราะ LM Studio ไม่มีระบบล็อกอิน
- **ไม่ต้อง forward พอร์ตใดๆ บน router** การเข้าจากข้างนอกทั้งหมดผ่าน Tailscale
- `C:\ai\config.json` เก็บรหัสลับ และกำหนดสิทธิ์ให้เฉพาะ admin อ่านได้
- ใช้รหัสผ่าน Windows ที่แข็งแรง เพราะเปิด Remote Desktop ไว้
- ComfyUI ไม่มีระบบล็อกอิน เปิดใช้ผ่าน Tailscale เท่านั้น
