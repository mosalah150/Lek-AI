#!/usr/bin/env bash
# ติดตั้ง Local AI ทั้งระบบบน Ubuntu 24.04 แบบคำสั่งเดียว
# วิธีใช้:  sudo bash setup.sh
# รันซ้ำได้อย่างปลอดภัย: ขั้นที่ทำไปแล้วจะถูกข้าม
set -euo pipefail

STACK_DIR="/opt/ai/stack"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

green() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

if [ "$(id -u)" -ne 0 ]; then echo "กรุณารันด้วย: sudo bash setup.sh"; exit 1; fi
TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
  echo "กรุณารันจากบัญชีผู้ใช้ปกติด้วย sudo (ไม่ใช่ล็อกอินเป็น root)"; exit 1
fi

# ---------------------------------------------------------------- 1. แพ็กเกจพื้นฐาน
green "1/8 อัปเดตระบบและติดตั้งเครื่องมือพื้นฐาน"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get install -y ca-certificates curl gnupg git jq openssl rsync nfs-common \
  ubuntu-drivers-common unattended-upgrades cockpit
systemctl enable --now cockpit.socket

# อัปเดตความปลอดภัยอัตโนมัติ แต่ห้ามรีสตาร์ตเอง
cat > /etc/apt/apt.conf.d/52local-ai-no-reboot <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# ---------------------------------------------------------------- 2. NVIDIA driver
green "2/8 ตรวจ NVIDIA driver"
if ! nvidia-smi >/dev/null 2>&1; then
  ubuntu-drivers install
  warn "ติดตั้ง NVIDIA driver แล้ว ต้องรีสตาร์ตเครื่องก่อน"
  warn "พิมพ์:  sudo reboot   แล้วรัน  sudo bash setup.sh  อีกครั้ง"
  exit 0
fi
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

# ---------------------------------------------------------------- 3. Docker
green "3/8 ติดตั้ง Docker"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
usermod -aG docker "$TARGET_USER"

# ---------------------------------------------------------------- 4. NVIDIA Container Toolkit
green "4/8 ติดตั้ง NVIDIA Container Toolkit (ให้ Docker ใช้ GPU ได้)"
if ! command -v nvidia-ctk >/dev/null 2>&1; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list
  apt-get update
  apt-get install -y nvidia-container-toolkit
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
fi

# ---------------------------------------------------------------- 5. ไฟล์ระบบและรหัสลับ
green "5/8 เตรียมโฟลเดอร์ /opt/ai และรหัสลับ"
mkdir -p "$STACK_DIR/scripts" /opt/ai/ollama /opt/ai/open-webui /opt/ai/postgres /opt/ai/n8n /opt/ai/tmp
chown 1000:1000 /opt/ai/n8n            # n8n รันใน container ด้วย uid 1000
if [ "$SRC_DIR" != "$STACK_DIR" ]; then
  cp "$SRC_DIR/docker-compose.yml" "$STACK_DIR/"
  cp "$SRC_DIR"/scripts/*.sh "$STACK_DIR/scripts/"
fi
chmod +x "$STACK_DIR"/scripts/*.sh
install -m 0755 "$SRC_DIR/ai" /usr/local/bin/ai

if [ ! -f "$STACK_DIR/.env" ]; then
  cat > "$STACK_DIR/.env" <<EOF
WEBUI_URL=
WEBUI_SECRET_KEY=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 24)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
EOF
  chmod 600 "$STACK_DIR/.env"
  warn "สร้างรหัสลับไว้ที่ $STACK_DIR/.env แล้ว (N8N_ENCRYPTION_KEY ห้ามหาย: backup จะเก็บไฟล์นี้ไว้ให้)"
fi

# ---------------------------------------------------------------- 6. Tailscale
green "6/8 ติดตั้ง Tailscale (เข้าใช้จากข้างนอก)"
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if ! tailscale status >/dev/null 2>&1; then
  warn "เปิดลิงก์ที่จะแสดงด้านล่างในเบราว์เซอร์ เพื่อล็อกอิน Tailscale"
  tailscale up --ssh --hostname=ai-server
fi
if tailscale serve --bg 3000 >/dev/null 2>&1; then
  TS_DNS="$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
  sed -i "s#^WEBUI_URL=.*#WEBUI_URL=https://${TS_DNS}#" "$STACK_DIR/.env"
else
  warn "tailscale serve ยังใช้ไม่ได้: เปิด MagicDNS และ HTTPS Certificates ที่ Tailscale admin console > DNS แล้วรัน setup.sh อีกครั้ง"
fi

# ---------------------------------------------------------------- 7. เริ่มระบบ
green "7/8 เริ่ม Open WebUI, Ollama, Docling, n8n, PostgreSQL"
cd "$STACK_DIR"
docker compose pull
docker compose up -d

# ---------------------------------------------------------------- 8. โมเดล
green "8/8 ดาวน์โหลดโมเดล"
read -rp "ดาวน์โหลดโมเดลเริ่มต้นเลยไหม (ราว 40GB, 10-20 นาที) [Y/n] " ans
if [[ ! "$ans" =~ ^[Nn] ]]; then
  for m in qwen3:30b-a3b qwen3-coder:30b bge-m3; do
    docker compose exec -T ollama ollama pull "$m" || warn "ดาวน์โหลด $m ไม่สำเร็จ: ตรวจชื่อรุ่นที่ ollama.com/library แล้วใช้คำสั่ง  ai pull <ชื่อ>"
  done
fi

LAN_IP="$(hostname -I | awk '{print $1}')"
WEBUI_URL="$(grep '^WEBUI_URL=' "$STACK_DIR/.env" | cut -d= -f2-)"
cat <<EOF

=============================================================
 ✅ ติดตั้งเสร็จแล้ว
-------------------------------------------------------------
 Open WebUI (ใน LAN)    : http://${LAN_IP}:3000
 Open WebUI (ข้างนอก)   : ${WEBUI_URL:-ยังไม่ได้ตั้ง Tailscale Serve}
 n8n                   : http://${LAN_IP}:5678
 Cockpit (จัดการเครื่อง)  : https://${LAN_IP}:9090
-------------------------------------------------------------
 ขั้นต่อไป:
  1. เปิด Open WebUI แล้วสมัครบัญชีแรก (จะเป็น admin)
  2. ตั้งค่า NAS และ backup:  sudo bash scripts/setup-backup.sh
  3. ดูคำสั่งลัดทั้งหมด:       ai help
 ล็อกเอาต์แล้วล็อกอินใหม่หนึ่งครั้ง เพื่อให้ใช้คำสั่ง docker ได้โดยไม่ต้อง sudo
=============================================================
EOF
