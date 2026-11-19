# Local AI สำหรับองค์กร: คู่มือติดตั้ง (Ubuntu สำหรับมือใหม่)

Dell Precision 5820 เปิดทิ้งไว้เป็น server · จัดการทั้งหมดจาก MacBook · ไม่ต้องจำคำสั่ง Linux

> ภาพรวมโครงการอยู่ที่ [README](../README.md) · เวอร์ชัน Windows อยู่ที่ [`_windows-version/`](../_windows-version/)

## สิ่งที่จะได้

```
MacBook / ผู้ใช้ใน LAN ──► LAN (ในออฟฟิศ) / Tailscale (ข้างนอก)
                                │
┌──────────── Dell Precision 5820 · Ubuntu Server 24.04 ───────────────┐
│  Open WebUI :3000 ── แชท, ถามตอบเอกสาร, บัญชีผู้ใช้                        │
│  Ollama (GPU) ────── สมองของ AI (ไม่เปิดพอร์ตออกข้างนอก)                    │
│  Docling (CPU) ───── แปลง PDF/ตาราง                                   │
│  n8n :5678 + PostgreSQL ── งานอัตโนมัติ                                │
│  ComfyUI (ตัวเลือก) ── สร้างภาพ/เสียง/3D                                  │
│  Cockpit :9090 ───── หน้าเว็บจัดการเครื่อง (แทนการพิมพ์คำสั่ง)                  │
│  NVMe 1TB = ระบบ + โมเดล + ข้อมูล  ·  HDD 2TB = สำเนาเอกสาร              │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ NFS
             Synology DS918+ (RAID5 8TB): ai-docs · ai-backup · Snapshot
```

**คำสั่ง Linux ที่ต้องใช้จริงมีแค่ 4 คำสั่ง:** `ssh` (เข้าเครื่อง), `sudo bash setup.sh` (ติดตั้ง), `ai status` (ดูสถานะ) และ `ai update` (อัปเดต) ที่เหลือทำผ่านหน้าเว็บ

---

## ขั้นที่ 1: ติดตั้ง Ubuntu (ประมาณ 30 นาที)

> ⚠️ **การติดตั้งจะลบข้อมูลทั้งหมดบน NVMe** ถ้ามีไฟล์สำคัญ ให้สำรองออกก่อน

### 1.1 เตรียม USB บน MacBook
1. ดาวน์โหลด **Ubuntu Server 24.04 LTS** จาก https://ubuntu.com/download/server
2. ติดตั้ง **balenaEtcher** (https://etcher.balena.io) แล้วเขียนไฟล์ ISO ลง USB (ขนาด 4GB ขึ้นไป)

### 1.2 ตั้งค่า BIOS ของ 5820 (กด **F2** ตอนเปิดเครื่อง)
- **Storage > SATA/NVMe Operation** = **AHCI/NVMe** (ถ้าเป็น "RAID On" ตัวติดตั้งจะมองไม่เห็น NVMe)
- **Power Management > AC Recovery** = **Power On** (เปิดเครื่องเองเมื่อไฟกลับมา)
- **Secure Boot** = Disabled (ช่วยให้ติดตั้ง NVIDIA driver ได้ง่ายขึ้น)

### 1.3 ติดตั้ง
เสียบ USB แล้วกด **F12** ตอนเปิดเครื่อง เลือก USB จากนั้นทำตามตัวติดตั้ง:
- Language: English · Keyboard: English (US)
- Type of install: **Ubuntu Server** (ไม่ใช่แบบ minimized) · ไม่ต้องติ๊ก Search for third-party drivers เพราะ `setup.sh` ติดตั้ง driver ให้เอง
- Network: ปล่อยตามค่าเดิม (DHCP) แล้ว**จด IP** ที่แสดงไว้
- Proxy: เว้นว่าง · Mirror: ใช้ค่าเดิม
- Storage: **Use an entire disk** แล้วเลือก**ดิสก์ NVMe 1TB** ระวังอย่าเลือก HDD 2TB
  - ⚠️ **เอาติ๊ก "Set up this disk as an LVM group" ออก** ไม่อย่างนั้นตัวติดตั้งอาจแบ่งพื้นที่ให้ระบบแค่บางส่วนของดิสก์ ทำให้โมเดลวางได้ไม่เต็ม 1TB
  - หน้าสรุปต้องเห็น `/` ขนาดเกือบ 1TB ก่อนกด Done
- Profile: ตั้งชื่อเครื่อง `ai-server` และตั้ง username/รหัสผ่านของคุณเอง
- Ubuntu Pro: **Skip for now**
- ✅ **Install OpenSSH server** (สำคัญมาก) · ถ้ามี SSH key อยู่บน GitHub เลือก Import SSH identity: from GitHub เพื่อเข้าเครื่องได้โดยไม่ต้องพิมพ์รหัสผ่าน
- Featured snaps: ไม่ต้องเลือกอะไร

เสร็จแล้วถอด USB และรีสตาร์ต จากนี้ไปถอดจอและคีย์บอร์ดออกได้เลย

> **แนะนำ:** จอง IP ของ 5820 ไว้ใน router (DHCP reservation) เพื่อให้ IP ไม่เปลี่ยน

## ขั้นที่ 2: รันสคริปต์ติดตั้งจาก MacBook (ประมาณ 30–40 นาที)

เปิด **Terminal** บน MacBook แล้วรันทีละบรรทัด (แก้ `user` และ IP ให้ตรงกับของคุณ)

ส่งโฟลเดอร์นี้ไปที่ server:

```bash
gh repo clone mosalah150/Lek-AI ~/Lek-AI
```

```bash
scp -r ~/Lek-AI user@192.168.1.50:~/local-ai
```

(คำสั่งแรกดาวน์โหลด repo มาที่ MacBook ก่อน ถ้ามีโฟลเดอร์อยู่แล้วก็ข้ามได้)

เข้าไปที่ server:

```bash
ssh user@192.168.1.50
```

รันสคริปต์ติดตั้ง (ตอนนี้คุณอยู่บน server แล้ว):

```bash
cd ~/local-ai && sudo bash setup.sh
```

สคริปต์จะ**หยุดหนึ่งครั้ง**หลังติดตั้ง NVIDIA driver ให้รีสตาร์ต รอราว 2 นาที แล้วเข้าใหม่และรันซ้ำ:

```bash
sudo reboot
```

```bash
ssh user@192.168.1.50
```

```bash
cd ~/local-ai && sudo bash setup.sh
```

ระหว่างทาง สคริปต์จะแสดง**ลิงก์ล็อกอิน Tailscale** ให้คัดลอกไปเปิดในเบราว์เซอร์บน MacBook แล้วล็อกอิน (สมัครฟรีด้วยบัญชี Google หรือ Microsoft ได้)

## ขั้นที่ 3: Tailscale สำหรับเข้าใช้จากข้างนอก

1. ติดตั้ง **Tailscale** บน MacBook (จาก App Store) แล้วล็อกอิน**บัญชีเดียวกัน**
2. เปิด https://login.tailscale.com/admin/dns แล้วเปิด **MagicDNS** และ **HTTPS Certificates**
3. ถ้าตอนรัน setup.sh มีข้อความเตือนเรื่อง `tailscale serve` ให้รัน `sudo bash setup.sh` อีกรอบหลังเปิดสองอย่างนี้

ผลที่ได้:
- เปิด Open WebUI ได้จากทุกที่ที่ `https://ai-server.<ชื่อ-tailnet>.ts.net`
- SSH เข้าเครื่องจากข้างนอกได้ด้วย `ssh user@ai-server`

> แพ็กเกจฟรีของ Tailscale จำกัดจำนวนผู้ใช้ เพื่อนร่วมงานที่ใช้ในออฟฟิศให้เข้าผ่าน LAN ที่ `http://<IP>:3000`

## ขั้นที่ 4: ตั้งค่า NAS (DS918+) และ backup

### บนหน้าเว็บ DSM
1. Control Panel > File Services > NFS: ✅ **Enable NFS**
2. สร้าง Shared Folder `ai-docs` และ `ai-backup`
3. Shared Folder > Edit > **NFS Permissions** > Create โดยใส่ Hostname/IP = IP ของ 5820:
   - `ai-docs`: Privilege = **Read Only**
   - `ai-backup`: Privilege = **Read/Write**, Squash = **Map all users to admin**
4. **Snapshot Replication** (ติดตั้งจาก Package Center): ตั้ง snapshot ทั้งสองโฟลเดอร์ทุกชั่วโมง เก็บ 14 วัน
5. Control Panel > Hardware & Power: ✅ **Restart automatically when power supply issue is fixed**
6. Storage Manager > HDD แต่ละลูก > Settings: **ปิด Write cache** (แนะนำถ้าไม่มี UPS: ลดความเสียหายเมื่อไฟดับ)

### บน server
```bash
cd ~/local-ai && sudo bash scripts/setup-backup.sh
```
สคริปต์จะถาม IP ของ NAS แล้วเชื่อมต่อ ตั้ง backup ทุกคืนตอนตีสอง และทดลอง backup ให้หนึ่งครั้ง

## ขั้นที่ 5: ใช้ HDD 2TB (ผ่านหน้าเว็บ Cockpit)

1. เปิด `https://<IP>:9090` บน MacBook (เบราว์เซอร์จะเตือนเรื่อง certificate ให้กด Advanced > Proceed) แล้วล็อกอินด้วย user ของ Ubuntu
2. เมนู **Storage** > เลือก HDD 2TB
   - ⚠️ **ถ้าในดิสก์มีข้อมูลสำคัญ ให้สำรองออกก่อน** เพราะการ Format จะลบทุกอย่าง
   - กด **Create partition table** แล้ว **Create partition**: Type = ext4, Mount point = `/mnt/hdd`, ✅ Mount at boot
3. หลังจากนั้น การสำรองเอกสารจาก NAS ลง HDD จะเริ่มทำงานเองทุกคืน

## ขั้นที่ 6: ตั้งค่า Open WebUI ครั้งแรก

1. เปิด `http://<IP>:3000` แล้วสมัครบัญชีแรก บัญชีนี้จะเป็น **admin**
2. ให้เพื่อนร่วมงานสมัครเข้ามา แล้วอนุมัติที่ Admin Panel > Users เมื่อครบแล้ว Admin Settings > General > **ปิด Enable New Sign Ups**
3. Admin Panel > Users > **Groups**: สร้างกลุ่มตามแผนก
4. Workspace > **Knowledge**: สร้างคลังเอกสารแยกตามแผนก อัปโหลดเอกสาร แล้วกำหนดสิทธิ์รายกลุ่ม
5. Admin Settings > Models: ตั้ง `qwen3:30b-a3b` เป็นโมเดลเริ่มต้น

## ขั้นที่ 7: n8n สำหรับงานอัตโนมัติ

1. เปิด `http://<IP>:5678` แล้วสร้างบัญชี owner
2. Credentials > New > **Ollama** แล้วตั้ง Base URL = `http://ollama:11434`
3. ไอเดีย workflow แรก: ทุกเช้าดึงอีเมลหรือรายงานมาให้ AI สรุป แล้วส่งเข้า LINE หรือ Slack

## ขั้นที่ 8 (ตัวเลือก): ComfyUI สำหรับสร้างภาพ marketing และ asset เกม

```bash
cd ~/local-ai && sudo bash scripts/install-comfyui.sh
```

- เปิดจาก MacBook (ต้องเปิด Tailscale ไว้) ที่ `https://ai-server.<tailnet>.ts.net:8443`
- **ก่อนสร้างภาพ ให้รัน `ai free-gpu`** เพื่อคืน VRAM จาก LLM
- ตรวจ license ของแต่ละโมเดลก่อนนำภาพไปใช้เชิงพาณิชย์

---

## ใช้งานประจำวัน: คำสั่ง `ai`

SSH เข้าเครื่องแล้วพิมพ์:

| คำสั่ง | ใช้เมื่อ |
|---|---|
| `ai status` | อยากรู้ว่าระบบปกติไหม |
| `ai logs open-webui` | มีอะไรผิดปกติ และอยากดู log (กด Ctrl+C เพื่อออก) |
| `ai restart` | ระบบค้าง ให้รีสตาร์ตทุกบริการ |
| `ai pull <ชื่อ>` / `ai remove <ชื่อ>` | เพิ่มหรือลบโมเดล (ดูชื่อที่ ollama.com/library) |
| `ai free-gpu` | ก่อนใช้ ComfyUI |
| `ai backup` | อยากสำรองข้อมูลทันที |
| `ai update` | อัปเดตทุกอย่าง (ระบบจะ backup ให้ก่อนอัตโนมัติ) |

**Cockpit** (`https://<IP>:9090`) ใช้ดู CPU, RAM, ดิสก์, ติดตั้ง update ของ Ubuntu และรีสตาร์ตเครื่องผ่านหน้าเว็บได้ มีเมนู Terminal ในตัวด้วย

## ดูแลเดือนละครั้ง (ประมาณ 15 นาที)

1. `ai update`
2. Cockpit > **Software Updates** > Install all updates > Restart
3. หลังเครื่องบูตขึ้นมา รอราว 3 นาที แล้วรัน `ai status` ตรวจว่าทุกบริการขึ้นครบ
4. ตรวจ backup ด้วย `tail /var/log/ai-backup.log` ต้องเห็นคำว่า `OK` ของเมื่อคืน

ผลที่ตั้งไว้ให้แล้ว: Ubuntu ติดตั้งอัปเดตความปลอดภัยเองอัตโนมัติ แต่**ไม่รีสตาร์ตเอง**

## แก้ปัญหาเบื้องต้น

| อาการ | ลองทำ |
|---|---|
| เปิดหน้าเว็บไม่ได้ | `ai status` ถ้ามีบริการไหนไม่ขึ้น ให้ `ai restart` |
| หลังไฟดับ เข้าไม่ได้ | รอ 3–5 นาที เพราะเครื่องและ NAS ต้องบูต ถ้ายังไม่ได้ ให้ตรวจว่า 5820 เปิดอยู่ไหม |
| AI ตอบช้ามากผิดปกติ | `ai status` ดูว่า GPU ถูกใช้งานไหม ถ้า `nvidia-smi` error ให้รีสตาร์ตเครื่อง |
| `nvidia-smi` ขึ้น `Driver/library version mismatch` | NVIDIA driver เพิ่งถูกอัปเดต ให้รีสตาร์ตเครื่องหนึ่งครั้ง (ปกติจะเกิดหลังอัปเดตรายเดือนเท่านั้น) |
| ดิสก์เต็ม | `ai models` แล้ว `ai remove` โมเดลที่ไม่ใช้ |
| backup ไม่ทำงาน | `tail /var/log/ai-backup.log` ส่วนใหญ่เกิดจาก NAS ไม่ได้เชื่อมต่อ |
| ไม่แน่ใจ | คัดลอกผลของ `ai status` และ `ai logs <บริการ>` มาถาม Claude ได้เลย |

## ความปลอดภัย

- Ollama **ไม่เปิดพอร์ต**ออกนอก Docker เพราะไม่มีระบบยืนยันตัวตน
- ComfyUI เปิดเฉพาะผ่าน Tailscale เพราะไม่มีระบบล็อกอิน
- **ไม่ต้อง forward พอร์ตใดๆ บน router** การเข้าจากข้างนอกทั้งหมดผ่าน Tailscale
- รหัสลับทั้งหมดถูกสุ่มให้อัตโนมัติ เก็บไว้ที่ `/opt/ai/stack/.env` และถูก backup ไป NAS ทุกคืน ห้ามให้ใครอื่นเข้าถึง share `ai-backup`
- ระบบที่ใช้งานจริงควร pin เวอร์ชันของ image แทน `latest`/`main` เพื่อไม่ให้การอัปเดตทำระบบเสียโดยไม่รู้ตัว

## แนะนำเพิ่มเติม: UPS

**UPS ขนาด 1000VA/600W ขึ้นไป** (ราว 3,000–5,000 บาท) คือของที่ควรซื้อเป็นอย่างแรก เพราะช่วยป้องกัน RAID5 ของ NAS และข้อมูลเสียหายจากไฟดับ
