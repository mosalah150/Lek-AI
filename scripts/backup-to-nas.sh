#!/usr/bin/env bash
# สำรอง Open WebUI, n8n, ฐานข้อมูล PostgreSQL และ config ไปที่ NAS
# cron (ตั้งโดย setup-backup.sh): ทุกวัน 02:00
set -euo pipefail

STACK_DIR="/opt/ai/stack"
NAS_MOUNT="/mnt/nas-backup"
KEEP_DAYS=14
STAMP="$(date +%Y%m%d-%H%M)"
WORK="/opt/ai/tmp/backup-$STAMP"

if ! mountpoint -q "$NAS_MOUNT"; then
  echo "$(date) ERROR: $NAS_MOUNT is not mounted, skipping backup" >&2
  exit 1
fi

mkdir -p "$WORK"
cd "$STACK_DIR"

# 1) dump ฐานข้อมูล n8n ขณะยังทำงานอยู่
docker compose exec -T postgres pg_dump -U n8n -F c n8n > "$WORK/n8n-db.dump"

# 2) หยุด Open WebUI และ n8n ชั่วคราว (~1 นาที) แล้วเก็บโฟลเดอร์ข้อมูล
docker compose stop open-webui n8n
trap 'docker compose start open-webui n8n >/dev/null' EXIT
tar -czf "$WORK/data.tgz" -C /opt/ai open-webui n8n stack
docker compose start open-webui n8n >/dev/null
trap - EXIT

# 3) ย้ายไป NAS แล้วลบชุดที่เก่ากว่า KEEP_DAYS
mv "$WORK" "$NAS_MOUNT/$STAMP"
find "$NAS_MOUNT" -mindepth 1 -maxdepth 1 -type d -name '20[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]' \
  -mtime +"$KEEP_DAYS" -exec rm -rf {} +
echo "$(date) OK: backup $STAMP"
