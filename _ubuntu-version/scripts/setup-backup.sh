#!/usr/bin/env bash
# เชื่อม NAS (NFS) และตั้ง backup อัตโนมัติทุกคืน
# วิธีใช้:  sudo bash scripts/setup-backup.sh
# ต้องตั้งค่าบน NAS ตาม README ขั้นที่ 4 ให้เสร็จก่อน
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "กรุณารันด้วย: sudo bash scripts/setup-backup.sh"; exit 1; fi

read -rp "IP ของ Synology DS918+ (เช่น 192.168.1.10): " NAS_IP
[[ "$NAS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "IP ไม่ถูกต้อง"; exit 1; }

mkdir -p /mnt/nas-docs /mnt/nas-backup

add_fstab() {  # เพิ่มบรรทัดใน /etc/fstab ถ้ายังไม่มี
  grep -qs " $2 " /etc/fstab || echo "$1 $2 nfs $3 0 0" >> /etc/fstab
}
add_fstab "${NAS_IP}:/volume1/ai-docs"   /mnt/nas-docs   "ro,nofail,_netdev,x-systemd.automount"
add_fstab "${NAS_IP}:/volume1/ai-backup" /mnt/nas-backup "rw,nofail,_netdev,x-systemd.automount"

systemctl daemon-reload
mount -a
ls /mnt/nas-docs >/dev/null && ls /mnt/nas-backup >/dev/null \
  || { echo "เชื่อม NAS ไม่สำเร็จ: ตรวจว่าเปิด NFS และให้สิทธิ์ IP ของเครื่องนี้แล้ว (README ขั้นที่ 4)"; exit 1; }
echo "เชื่อม NAS สำเร็จ"

cat > /etc/cron.d/local-ai-backup <<'EOF'
# Local AI: backup ทุกคืน (ผลอยู่ใน /var/log/ai-backup.log)
0 2 * * *  root /opt/ai/stack/scripts/backup-to-nas.sh   >> /var/log/ai-backup.log 2>&1
30 2 * * * root /opt/ai/stack/scripts/mirror-nas-docs.sh >> /var/log/ai-backup.log 2>&1
EOF
chmod 644 /etc/cron.d/local-ai-backup
echo "ตั้ง backup อัตโนมัติแล้ว (02:00 และ 02:30 ทุกคืน)"

if ! mountpoint -q /mnt/hdd; then
  echo "[!] ยังไม่ได้ mount HDD 2TB ที่ /mnt/hdd: การสำรองเอกสารลง HDD จะข้ามไปจนกว่าจะ mount (README ขั้นที่ 5)"
fi

read -rp "ทดลอง backup ตอนนี้เลยไหม [Y/n] " ans
if [[ ! "$ans" =~ ^[Nn] ]]; then
  /opt/ai/stack/scripts/backup-to-nas.sh && ls -lh /mnt/nas-backup | tail -3
fi
