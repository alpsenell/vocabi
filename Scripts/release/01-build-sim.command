#!/bin/bash
cd "$(dirname "$0")/../.."
LOG=Scripts/release/01-build-sim.log
{
echo "== $(date) build for simulator"
UDID=$(xcrun simctl list devices available | grep "iPhone 17 Pro Max" | head -1 | grep -oE '[0-9A-F-]{36}')
if [ -z "$UDID" ]; then UDID=$(xcrun simctl list devices available | grep -E "iPhone 1[5-7] Pro Max" | head -1 | grep -oE '[0-9A-F-]{36}'); fi
echo "UDID=$UDID"
echo "$UDID" > Scripts/release/udid.txt
xcodebuild -project WidgetApp.xcodeproj -scheme WidgetApp -sdk iphonesimulator -configuration Debug -derivedDataPath build build 2>&1 | tail -15
xcrun simctl boot "$UDID" 2>&1 || true
open -a Simulator
sleep 8
xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/WidgetApp.app && echo "INSTALL OK"
xcrun simctl launch "$UDID" com.alpsenel.wordwidget && echo "LAUNCH OK"
echo "== done"
} 2>&1 | tee "$LOG"
