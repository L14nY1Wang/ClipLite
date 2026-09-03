#!/bin/bash
# 测量运行中 ClipLite 的真实物理内存占用（Activity Monitor 口径：physical footprint）。
# 用法：先 `make app && open build/ClipLite.app`，再 `bash scripts/memaudit.sh`
PID=$(pgrep -f "ClipLite.app/Contents/MacOS/ClipLite" | head -1)
if [ -z "$PID" ]; then
  echo "ClipLite 未运行。请先： make app && open build/ClipLite.app"
  exit 1
fi
echo "ClipLite pid=$PID"
echo "--- Physical footprint（真实物理内存，Activity Monitor 口径）---"
vmmap --summary "$PID" 2>/dev/null | grep "Physical footprint"
echo "--- RSS（含共享框架映射，仅供对比，通常明显偏大）---"
ps -o rss= -p "$PID" | awk '{printf "%.1f MB\n", $1/1024}'
echo
echo "提示：截图/贴图的瞬时增量取决于像素分辨率，见 docs/MEMORY-AUDIT.md"
