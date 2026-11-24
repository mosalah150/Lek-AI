#!/usr/bin/env bash
# สำรองเอกสารจาก NAS (ai-docs) ลง HDD 2TB เป็น snapshot รายวัน เก็บ 30 วัน
# ไฟล์ที่ไม่เปลี่ยนจะเป็น hard link จึงแทบไม่กินพื้นที่เพิ่ม
set -euo pipefail

SRC="/mnt/nas-docs/"
DEST_ROOT="/mnt/hdd/nas-docs"
KEEP_DAYS=30

for m in /mnt/nas-docs /mnt/hdd; do
  if ! mountpoint -q "$m"; then
    echo "$(date) ERROR: $m is not mounted, skipping" >&2
    exit 1
  fi
done

TODAY="$(date +%Y-%m-%d)"
mkdir -p "$DEST_ROOT"
LINK_DEST=()
[ -d "$DEST_ROOT/latest" ] && LINK_DEST=(--link-dest="$DEST_ROOT/latest")

rsync -a --delete "${LINK_DEST[@]}" "$SRC" "$DEST_ROOT/$TODAY/"
ln -sfn "$DEST_ROOT/$TODAY" "$DEST_ROOT/latest"
find "$DEST_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20??-??-??' -mtime +"$KEEP_DAYS" -exec rm -rf {} +
echo "$(date) OK: nas-docs snapshot $TODAY"
