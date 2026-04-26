#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-read}"
BASELINE_DOWN="${2:-500}"
FALLBACK_DOWN="${3:-500}"
MAX_DAYS="${4:-7}"
SERVER_ID="${5:-}"

XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_DIR="${CONKY_CACHE_DIR:-$XDG_CACHE_HOME/conky}"
OUT_JSON="$CACHE_DIR/speedtest_snapshot.json"
HISTORY="$CACHE_DIR/speedtest_snapshot.log"

mkdir -p "$CACHE_DIR"

if [[ "$CMD" == "run" ]]; then
  if command -v speedtest >/dev/null 2>&1; then
    if [[ -n "$SERVER_ID" ]]; then
      json="$(speedtest -f json --accept-license --accept-gdpr -s "$SERVER_ID" 2>/dev/null)" || {
        echo "speedtest failed" >&2
        exit 1
      }
    else
      json="$(speedtest -f json --accept-license --accept-gdpr 2>/dev/null)" || {
        echo "speedtest failed" >&2
        exit 1
      }
    fi
  else
    echo "speedtest (Ookla) not found" >&2
    exit 1
  fi

  printf '%s\n' "$json" > "$OUT_JSON"
  printf '%s\t%s\n' "$(date -u +%s)" "$json" >> "$HISTORY"
  echo "ok"
  exit 0
fi

if [[ "$CMD" == "bars" ]]; then
python3 - "$OUT_JSON" "$BASELINE_DOWN" "$FALLBACK_DOWN" <<'PY'
import json
import sys

path = sys.argv[1]
fallback_down = int(float(sys.argv[2]))
fallback_up = int(float(sys.argv[3]))

try:
  with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
except Exception:
  print(f"{fallback_down}|{fallback_up}")
  raise SystemExit(0)

def mbps(section, fallback):
  if isinstance(section, dict) and section.get("bandwidth") is not None:
    try:
      return int(round((float(section["bandwidth"]) * 8) / 1_000_000))
    except Exception:
      pass
  return fallback

down = mbps(data.get("download"), fallback_down)
up = mbps(data.get("upload"), fallback_up)
print(f"{down}|{up}")
PY
exit 0
fi

python3 - "$OUT_JSON" "$BASELINE_DOWN" "$FALLBACK_DOWN" "$MAX_DAYS" <<'PY'
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]
baseline_down = float(sys.argv[2])
fallback_down = float(sys.argv[3])
max_days = int(sys.argv[4])

def output(down, days, delta):
  print(f"{down}|{days}|{delta}")

try:
  with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
except Exception:
  output(int(fallback_down), "--", "---")
  raise SystemExit(0)

timestamp = None
if isinstance(data.get("result"), dict):
  timestamp = data["result"].get("timestamp") or data["result"].get("date")
if not timestamp:
  timestamp = data.get("timestamp")

down_mbps = None
dl = data.get("download")
if isinstance(dl, dict) and dl.get("bandwidth") is not None:
  try:
    down_bytes_per_s = float(dl["bandwidth"])
    down_mbps = int(round((down_bytes_per_s * 8) / 1_000_000))
  except Exception:
    down_mbps = None

if down_mbps is None or not timestamp:
  output(int(fallback_down), "--", "---")
  raise SystemExit(0)

try:
  ts = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
except Exception:
  output(int(fallback_down), "--", "---")
  raise SystemExit(0)

now = datetime.now(timezone.utc)
days = int((now - ts).total_seconds() // 86400)
if days < 0:
  days = 0
days_str = f"{days:02d}"

if days > max_days:
  output(int(fallback_down), days_str, "---")
  raise SystemExit(0)

delta = int(round(down_mbps - baseline_down))
delta_str = f"{delta:+04d}"
output(down_mbps, days_str, delta_str)
PY
