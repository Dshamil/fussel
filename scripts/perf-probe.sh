#!/bin/bash
# Launches Fussel on the build machine and reports its CPU use and memory as GitHub annotations.
# 1) window open (first launch shows the tutorial over the main screen)
# 2) menu bar only (window closed), which is how Fussel spends most of its life
set -uo pipefail

APP="dist/Fussel.app"
BIN="$APP/Contents/MacOS/Fussel"
DOMAIN="app.fussel.Fussel"

measure() {
  local label="$1"
  "$BIN" >/dev/null 2>&1 &
  local pid=$!
  sleep 15
  # 8 samples, 2 s apart; the first top sample is always 0, so drop it.
  local stats
  stats=$(top -l 9 -s 2 -pid "$pid" -stats pid,cpu,mem 2>/dev/null | awk -v p="$pid" '$1==p {print $2" "$3}' | tail -n 8)
  local cpu mem
  cpu=$(echo "$stats" | awk '{s+=$1; n++} END { if (n) printf "%.1f", s/n; else print "?" }')
  mem=$(echo "$stats" | tail -n 1 | awk '{print $2}')
  echo "::notice title=Performance ($label)::average CPU ${cpu}% · memory ${mem}"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 2
}

defaults delete "$DOMAIN" >/dev/null 2>&1 || true
defaults write "$DOMAIN" loginItemConfigured -bool YES
defaults write "$DOMAIN" weeklyFluffCheck -bool NO
measure "window open"

defaults write "$DOMAIN" tutorialSeen -bool YES
measure "menu bar only"

# Main window without the tutorial: launch, then "open" again, which shows the window.
measure_main() {
  local label="$1"
  shift
  env "$@" "$BIN" >/dev/null 2>&1 &
  local pid=$!
  sleep 6
  open -a "$PWD/$APP"
  sleep 10
  local stats
  stats=$(top -l 9 -s 2 -pid "$pid" -stats pid,cpu,mem 2>/dev/null | awk -v p="$pid" '$1==p {print $2" "$3}' | tail -n 8)
  local cpu mem
  cpu=$(echo "$stats" | awk '{s+=$1; n++} END { if (n) printf "%.1f", s/n; else print "?" }')
  mem=$(echo "$stats" | tail -n 1 | awk '{print $2}')
  echo "::notice title=Performance ($label)::average CPU ${cpu}% · memory ${mem}"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 2
}
measure_main "main window, animated" FUSSEL_PROBE=1
measure_main "main window, still" FUSSEL_STILL=1
measure_main "main window, animated again" FUSSEL_PROBE=1

defaults delete "$DOMAIN" >/dev/null 2>&1 || true
exit 0
