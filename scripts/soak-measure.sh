#!/usr/bin/env bash
# soak-measure.sh — samples KindleWall's resting cost over time.
#
# Why this exists: "minimum system load" is unfalsifiable without numbers, and the
# numbers that matter (leaks, wakeups, fd/port growth) only appear over hours, not
# in a single snapshot. This writes one CSV row per interval so a trend is visible.
#
# Usage:
#   scripts/soak-measure.sh --out /tmp/soak.csv            # auto-detect the running app
#   scripts/soak-measure.sh --pid 1234 --interval 30 --out /tmp/soak.csv
#
# Always measure a Release build: Debug is -Onone and its timings are not the ones
# the user sees. Stop with Ctrl-C (or kill); the CSV stays usable at any point.
#
# CPU is the true average over each interval (cputime delta / wall delta), not ps's
# since-launch average and not a 1-second instantaneous sample — a menu-bar app that
# wakes for 200 ms every 30 minutes must not read as "0%" nor as a spike.

set -o pipefail

INTERVAL=60
OUT=""
PID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pid)      PID="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --out)      OUT="$2"; shift 2 ;;
    *) echo "Bilinmeyen seçenek: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$OUT" ]; then
  echo "--out <dosya.csv> zorunlu" >&2
  exit 2
fi

if [ -z "$PID" ]; then
  PID=$(pgrep -f "KindleWall.app/Contents/MacOS/KindleWall" | head -1)
fi

if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
  echo "KindleWall süreci bulunamadı (--pid ile verebilirsiniz)" >&2
  exit 1
fi

SUPPORT="$HOME/Library/Application Support/KindleWall"
WALLPAPERS="$SUPPORT/wallpapers"

# macOS ps prints cputime as [DD-]HH:MM:SS or MM:SS.ss — normalise to seconds.
cpu_seconds() {
  ps -o cputime= -p "$1" 2>/dev/null | tr -d ' ' | awk -F'[-:]' '
    NF==4 { print $1*86400 + $2*3600 + $3*60 + $4; next }
    NF==3 { print $1*3600 + $2*60 + $3; next }
    NF==2 { print $1*60 + $2; next }
    { print 0 }'
}

# THREADS and PORTS come from top; a Mach port or thread that never comes back is a
# leak that RSS alone will not show.
top_stats() {
  top -l 1 -pid "$1" -stats threads,ports -n 1 2>/dev/null \
    | awk 'NR>1 && $1 ~ /^[0-9]+$/ { print $1, $2; found=1 } END { if (!found) print "NA NA" }' \
    | tail -1
}

echo "PID $PID · aralık ${INTERVAL}s · çıktı $OUT"
echo "Durdurmak için Ctrl-C. CSV her satırda diske yazılır."

if [ ! -f "$OUT" ]; then
  echo "iso_time,elapsed_s,cpu_pct,cpu_total_s,rss_mb,threads,ports,fds,wallpaper_files,support_mb" > "$OUT"
fi

START_WALL=$(date +%s)
PREV_WALL=$START_WALL
PREV_CPU=$(cpu_seconds "$PID")

while kill -0 "$PID" 2>/dev/null; do
  sleep "$INTERVAL"
  kill -0 "$PID" 2>/dev/null || break

  NOW_WALL=$(date +%s)
  NOW_CPU=$(cpu_seconds "$PID")
  WALL_DELTA=$(( NOW_WALL - PREV_WALL ))
  [ "$WALL_DELTA" -le 0 ] && WALL_DELTA=1

  CPU_PCT=$(awk -v a="$NOW_CPU" -v b="$PREV_CPU" -v d="$WALL_DELTA" \
            'BEGIN { printf "%.3f", (a-b) / d * 100 }')

  RSS_MB=$(ps -o rss= -p "$PID" 2>/dev/null | awk '{ printf "%.1f", $1/1024 }')
  read -r THREADS PORTS <<< "$(top_stats "$PID")"
  FDS=$(lsof -p "$PID" 2>/dev/null | wc -l | tr -d ' ')
  WP_FILES=$(ls -1 "$WALLPAPERS" 2>/dev/null | wc -l | tr -d ' ')
  SUPPORT_MB=$(du -sm "$SUPPORT" 2>/dev/null | awk '{ print $1 }')

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(( NOW_WALL - START_WALL ))" \
    "$CPU_PCT" "$NOW_CPU" "${RSS_MB:-NA}" "${THREADS:-NA}" "${PORTS:-NA}" \
    "${FDS:-NA}" "${WP_FILES:-NA}" "${SUPPORT_MB:-NA}" >> "$OUT"

  PREV_WALL=$NOW_WALL
  PREV_CPU=$NOW_CPU
done

echo "Süreç sonlandı — ölçüm bitti: $OUT"
