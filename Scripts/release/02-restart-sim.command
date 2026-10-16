#!/bin/bash
cd "$(dirname "$0")/../.."
UDID=$(cat Scripts/release/udid.txt)
{
echo "== $(date) restart simulator $UDID"
for d in $(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}'); do
  if [ "$d" != "$UDID" ]; then echo "shutdown other $d"; xcrun simctl shutdown "$d"; fi
done
xcrun simctl shutdown "$UDID" 2>/dev/null
sleep 3
xcrun simctl boot "$UDID" && echo "booted"
open -a Simulator
sleep 10
xcrun simctl launch "$UDID" com.alpsenel.wordwidget && echo "LAUNCH OK"
echo "== done"
} 2>&1 | tee Scripts/release/02-restart-sim.log
