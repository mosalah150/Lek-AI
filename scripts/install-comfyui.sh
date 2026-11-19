#!/usr/bin/env bash
# (ตัวเลือก) ติดตั้ง ComfyUI สำหรับสร้างภาพ/เสียง/3D ใช้ GPU ร่วมกับ Ollama
# วิธีใช้:  sudo bash scripts/install-comfyui.sh
# เปิดใช้ผ่าน Tailscale เท่านั้น เพราะ ComfyUI ไม่มีระบบล็อกอิน
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "กรุณารันด้วย: sudo bash scripts/install-comfyui.sh"; exit 1; fi
RUN_USER="${SUDO_USER:?รันด้วย sudo จากบัญชีผู้ใช้ปกติ}"
DIR="/opt/ai/comfyui"

apt-get install -y git python3-venv python3-dev build-essential

if [ ! -d "$DIR/.git" ]; then
  git clone https://github.com/comfyanonymous/ComfyUI.git "$DIR"
fi
chown -R "$RUN_USER":"$RUN_USER" "$DIR"

sudo -u "$RUN_USER" bash -c "
  set -e
  cd '$DIR'
  [ -d venv ] || python3 -m venv venv
  ./venv/bin/pip install --upgrade pip
  # PyTorch แบบ CUDA 12.6 รองรับการ์ดรุ่น Turing (RTX 6000)
  ./venv/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
  ./venv/bin/pip install -r requirements.txt
"

cat > /etc/systemd/system/comfyui.service <<EOF
[Unit]
Description=ComfyUI
After=network-online.target docker.service

[Service]
User=$RUN_USER
WorkingDirectory=$DIR
ExecStart=$DIR/venv/bin/python main.py --listen 127.0.0.1 --port 8188
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now comfyui
tailscale serve --bg --https=8443 8188 || echo "[!] ตั้ง tailscale serve ไม่สำเร็จ: ตรวจว่าเปิด HTTPS ใน Tailscale แล้ว"

TS_DNS="$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
cat <<EOF

✅ ติดตั้ง ComfyUI แล้ว
 เปิดจาก MacBook (ต้องเปิด Tailscale): https://${TS_DNS}:8443
 วางไฟล์โมเดลไว้ที่: $DIR/models/  (checkpoints, loras, vae ...)
 ก่อนสร้างภาพ ให้คืน VRAM จาก LLM ด้วย:  ai free-gpu
 ⚠️ ตรวจ license ของแต่ละโมเดลก่อนนำภาพไปใช้เชิงพาณิชย์
EOF
