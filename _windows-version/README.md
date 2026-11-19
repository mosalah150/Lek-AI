# Local AI สำหรับองค์กร: คู่มือติดตั้ง (Windows Server Edition)

Dell Precision 5820 เปิดทิ้งไว้เป็น server · จัดการจาก MacBook ผ่าน Tailscale · ผู้ใช้ ≤10 คน

> เวอร์ชัน Ubuntu เดิมเก็บไว้ที่ `_ubuntu-version/` เผื่อเปลี่ยนใจในอนาคต

## ภาพรวม

```
MacBook / ผู้ใช้ใน LAN ──► Tailscale (ข้างนอก) / LAN (ในออฟฟิศ)
                                │
┌──────────── Dell Precision 5820 · Windows 11 Pro ─────────────────────┐
│  Docker Desktop (WSL2)                                                │
│   ├─ Open WebUI :3000 ── แชท, RAG, บัญชีผู้ใช้, API key                     │
│   ├─ Ollama (GPU) ────── ไม่เปิดพอร์ตออกนอก Docker                         │
│   ├─ Docling (CPU) ───── แปลง PDF/ตาราง                                  │
│   └─ n8n :5678 + PostgreSQL ── งานอัตโนมัติ                               │
│  ComfyUI (ติดตั้งบน Windows) ── สร้างภาพ/เสียง/3D ใช้ GPU ร่วมกับ Ollama        │
│  C: NVMe 1TB = ระบบ + Docker + โมเดล  ·  E: HDD 2TB = สำเนาเอกสาร/พัก backup │
└───────────────────────────────┬───────────────────────────────────────┘
                                │ SMB
            Synology DS918+ (RAID5 8TB): ai-docs · ai-backup · Snapshot
```

### ทำไม Windows ต้องตั้งค่าเพิ่ม

| ปัญหา | ผลถ้าไม่แก้ | วิธีแก้ (ขั้นตอน) |
|---|---|---|
| Docker Desktop และ ComfyUI เริ่มทำงานเมื่อมีคน**ล็อกอิน**เท่านั้น | หลังไฟดับ เครื่องบูตขึ้นมาแต่ระบบไม่ทำงาน | Autologon แล้วสั่งล็อกหน้าจออัตโนมัติ (ขั้นที่ 1.4) |
| Windows Update รีสตาร์ตเอง | ระบบดับกลางวันโดยไม่มีใครรู้ | ตั้ง Group Policy (ขั้นที่ 1.3) |
| WSL2 จำกัด RAM | Docker ใช้ได้แค่ครึ่งหนึ่งของ 128GB | `.wslconfig` (ขั้นที่ 2) |
| ไฟล์บน C:\ หรือ E:\ ที่ mount เข้า container ทำงานช้า | โหลดโมเดลช้ามาก | ใช้ named volume ทั้งหมด (ตั้งไว้แล้วใน compose) |

---

## 1. เตรียม Windows

### 1.1 พื้นฐาน
- ใช้ **Windows 11 Pro** (ต้องมี Group Policy และ Remote Desktop)
- สร้างบัญชี local ชื่อ `aiserver` สำหรับรันระบบ ใช้รหัสผ่านที่แข็งแรง
- ติดตั้ง **NVIDIA RTX Enterprise Driver** (driver สำหรับการ์ดตระกูล Quadro) จาก nvidia.com แล้วตรวจด้วย `nvidia-smi`
- ตั้ง IP ของเครื่องแบบ fixed (หรือจองไว้ใน DHCP ของ router)

### 1.2 ไฟฟ้าและการนอนหลับ
- **BIOS** (กด F2 ตอนบูต): Power Management > AC Recovery > **Power On**
- Settings > System > Power: **Screen และ Sleep = Never**
- PowerShell (Admin): `powercfg /hibernate off`

### 1.3 Windows Update ไม่ให้รีสตาร์ตเอง
`gpedit.msc` > Computer Configuration > Administrative Templates > Windows Components > Windows Update:
- **Configure Automatic Updates** = Enabled > `3 - Auto download and notify for install`
- **No auto-restart with logged on users for scheduled automatic updates installations** = Enabled

แล้วตั้งเวลาเข้าไปติดตั้งอัปเดตเองเดือนละครั้ง ต่อจากการ backup (ดูขั้นที่ 10)

### 1.4 Autologon พร้อมล็อกหน้าจอ
1. ดาวน์โหลด **Autologon** จาก Microsoft Sysinternals แล้วตั้งให้บัญชี `aiserver` (เครื่องมือนี้เก็บรหัสผ่านแบบเข้ารหัสใน LSA)
2. สั่งล็อกหน้าจอทันทีหลังล็อกอิน เพื่อไม่ให้ใครที่เดินผ่านใช้เครื่องได้ (PowerShell):
   ```powershell
   schtasks /Create /TN "Lock after autologon" /TR "rundll32.exe user32.dll,LockWorkStation" /SC ONLOGON /RU aiserver /DELAY 0002:00
   ```

### 1.5 Remote Desktop สำหรับจัดการจาก MacBook
- Settings > System > Remote Desktop > **On**
- บน MacBook ติดตั้ง **Windows App** (ชื่อเดิม Microsoft Remote Desktop) จาก App Store แล้วเชื่อมไปที่ IP ของ Tailscale (ขั้นที่ 4)

## 2. ติดตั้ง WSL2 และ Docker Desktop

```powershell
wsl --install          # รีสตาร์ตเมื่อติดตั้งเสร็จ
```

สร้างไฟล์ `C:\Users\aiserver\.wslconfig`:

```ini
[wsl2]
memory=96GB
processors=32
swap=16GB
```

```powershell
wsl --shutdown
```

ติดตั้ง **Docker Desktop** แล้วตั้งค่า:
- General: ✅ **Start Docker Desktop when you sign in** · ✅ Use the WSL 2 based engine
- เพิ่ม `aiserver` เข้ากลุ่ม `docker-users`

> **License:** Docker Desktop ใช้ฟรีได้เฉพาะองค์กรขนาดเล็ก (มีเงื่อนไขเรื่องจำนวนพนักงานและรายได้) ให้ตรวจเงื่อนไขปัจจุบันก่อนใช้

ทดสอบว่า container มองเห็น GPU:

```powershell
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

## 3. ติดตั้ง Stack

คัดลอกโฟลเดอร์นี้ไปไว้ที่ `C:\ai\stack` แล้วรัน:

```powershell
cd C:\ai\stack
Copy-Item .env.example .env
notepad .env          # ใส่ WEBUI_SECRET_KEY, POSTGRES_PASSWORD, N8N_ENCRYPTION_KEY (วิธีสุ่มค่าอยู่ในไฟล์)
docker compose up -d
docker compose ps
```

ดาวน์โหลดโมเดล (เช็กชื่อรุ่นล่าสุดที่ https://ollama.com/library ก่อน):

```powershell
docker compose exec ollama ollama pull qwen3:30b-a3b     # ตัวหลัก
docker compose exec ollama ollama pull qwen3-coder:30b   # เขียนโค้ด
docker compose exec ollama ollama pull bge-m3            # embedding
```

## 4. Tailscale: เข้าใช้งานจากข้างนอก

1. ติดตั้ง Tailscale บน **5820** และบน **MacBook** แล้วล็อกอินด้วยบัญชีเดียวกัน
2. ที่ Tailscale admin console > DNS: เปิด **MagicDNS** และ **HTTPS Certificates**
3. ตั้งชื่อเครื่อง 5820 เป็น `ai-server` แล้วรันบน 5820:
   ```powershell
   tailscale serve --bg 3000
   ```
4. จะได้ URL แบบ `https://ai-server.<tailnet>.ts.net` ให้นำไปใส่ `WEBUI_URL` ใน `.env` แล้วรัน `docker compose up -d`

ผลที่ได้:
- เปิด Open WebUI ผ่าน HTTPS ได้จากทุกที่ ไม่ต้องเปิดพอร์ตบน router
- Remote Desktop เข้า 5820 ผ่าน Tailscale ได้

> **ผู้ใช้คนอื่น:** แพ็กเกจฟรีของ Tailscale จำกัดจำนวนผู้ใช้ ถ้าคนอื่นต้องเข้าจากนอกออฟฟิศด้วย ให้ตรวจแพ็กเกจปัจจุบัน หรือให้ใช้แค่ใน LAN ที่ `http://<IP-5820>:3000`

## 5. ตั้งค่า NAS (DS918+)

1. สร้าง Shared Folder `ai-docs` และ `ai-backup`
2. สร้างบัญชี `ai-backup` บน NAS:
   - `ai-docs`: Read only
   - `ai-backup`: Read/Write
   - **ห้ามให้บัญชีอื่นเข้า `ai-backup`** เพราะในนั้นมีไฟล์ `.env`
3. Snapshot Replication: ตั้ง snapshot ทั้งสองโฟลเดอร์ทุกชั่วโมง เก็บ 14 วัน และเปิด immutable ถ้า DSM ของคุณรองรับ
4. Control Panel > Hardware & Power: ✅ **Restart automatically when power supply issue is fixed**
5. Storage Manager > HDD แต่ละลูก > Settings: **ปิด Write cache** (แนะนำถ้าไม่มี UPS: ลดความเสียหายเมื่อไฟดับ)
6. บน 5820 ในบัญชี `aiserver` บันทึกรหัสผ่านของ NAS:
   ```powershell
   cmdkey /add:192.168.1.10 /user:ai-backup /pass
   ```

## 6. ตั้งค่า Open WebUI ครั้งแรก

1. เปิด `http://localhost:3000` บน 5820 (หรือ URL ของ Tailscale) แล้วสมัครบัญชีแรก บัญชีนี้จะเป็น **admin**
2. ให้พนักงานสมัครเข้ามา แล้วอนุมัติที่ Admin Panel > Users เมื่อครบแล้ว**ปิด Enable New Sign Ups**
3. สร้าง **Groups** ตามแผนก และสร้าง **Knowledge** แยกตามแผนกพร้อมกำหนดสิทธิ์
4. Admin Settings > Documents: ตรวจว่า Content Extraction เป็น **Docling** และ Embedding เป็น **bge-m3**
5. เปิดใช้ **API Keys** สำหรับเครื่องมือเขียนโค้ดและงานอัตโนมัติ

## 7. n8n: งานอัตโนมัติ

- เปิด `http://<IP-5820>:5678` แล้วสร้างบัญชี owner
- เพิ่ม Credential ชนิด **Ollama** แล้วตั้ง Base URL = `http://ollama:11434` (n8n อยู่ใน network เดียวกับ Ollama จึงเรียกได้ตรง)
- workflow แรกที่แนะนำ: ทุกเช้า ดึงอีเมลหรือ log มาให้ LLM สรุป แล้วส่งเข้า LINE หรือ Teams

## 8. ComfyUI: สร้างภาพ เสียง และ 3D (ใช้ GPU ร่วมกัน)

- ติดตั้ง **ComfyUI Desktop** สำหรับ Windows (ใช้งานง่ายกว่ารันใน Docker บน Windows) แล้วเก็บโมเดลไว้บน **C: (NVMe)**
- การแบ่ง VRAM: Ollama คืน VRAM เองหลังว่าง 10 นาที (`OLLAMA_KEEP_ALIVE=10m`) ให้ใช้ ComfyUI ในช่วงที่ไม่มีคนแชท หรือสั่งคืน VRAM ทันทีด้วย:
  ```powershell
  docker compose exec ollama ollama stop qwen3:30b-a3b
  ```
- ถ้าต้องการเปิดจาก MacBook ให้รัน `tailscale serve --bg --https=8443 8000` (เปลี่ยน 8000 เป็นพอร์ตที่ ComfyUI ใช้จริง)
- **ตรวจ license ของแต่ละโมเดลก่อนใช้ภาพในงานเชิงพาณิชย์**

## 9. Backup อัตโนมัติ

แก้ IP ของ NAS ในสคริปต์ทั้งสองไฟล์ แล้วลงทะเบียน Task (PowerShell ในบัญชี `aiserver`):

```powershell
schtasks /Create /TN "AI backup to NAS" /SC DAILY /ST 02:00 /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\stack\scripts\backup-to-nas.ps1"
schtasks /Create /TN "Mirror NAS docs"  /SC DAILY /ST 02:30 /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\ai\stack\scripts\mirror-nas-docs.ps1"
schtasks /Run /TN "AI backup to NAS"      # ทดสอบรันทันที
Get-Content E:\ai-backup.log -Tail 20
```

| ข้อมูล | ต้นฉบับ | สำเนา |
|---|---|---|
| แชท, ผู้ใช้, Knowledge, workflow n8n, config | C: (Docker volume) | NAS `ai-backup` (เก็บ 14 วัน) + Snapshot ของ NAS |
| เอกสารองค์กร | NAS `ai-docs` | E:\nas-docs-mirror + Snapshot ของ NAS |
| โมเดล | C: (Docker volume) | ไม่ต้อง backup เพราะดาวน์โหลดใหม่ได้ |

**ทดสอบการกู้คืนอย่างน้อยเดือนละครั้ง**

## 10. ดูแลระบบเดือนละครั้ง

1. รัน backup ด้วยตัวเอง แล้วตรวจ log ว่าขึ้น `OK`
2. อัปเดต container:
   ```powershell
   cd C:\ai\stack
   docker compose pull; docker compose up -d; docker image prune -f
   ```
3. ติดตั้ง Windows Update แล้วรีสตาร์ต จากนั้นตรวจว่า `docker compose ps` ขึ้นครบทุกตัว
4. อัปเดต NVIDIA driver และ Docker Desktop ถ้ามีเวอร์ชันใหม่ ให้ทำทีละอย่าง แล้วทดสอบหลังแต่ละขั้น

สำหรับระบบที่ใช้งานจริง ควร pin เวอร์ชันของ image แทน `latest`/`main` เพื่อไม่ให้การอัปเดตทำระบบเสียโดยไม่รู้ตัว

## ความปลอดภัย

- **Ollama ไม่เปิดพอร์ตออกนอก Docker เลย** เพราะไม่มีระบบยืนยันตัวตน ให้แอปอื่นเรียกผ่าน API ของ Open WebUI ที่ใช้ API key แทน
- Windows Firewall: ตั้ง network profile ของ LAN เป็น **Private** และไม่ forward พอร์ตใดๆ บน router
- พอร์ต 3000 (Open WebUI) และ 5678 (n8n) เปิดเฉพาะใน LAN ส่วนจากข้างนอกให้เข้าผ่าน Tailscale เท่านั้น
