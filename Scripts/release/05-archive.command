#!/bin/bash
cd "$(dirname "$0")/../.."
{
echo "== $(date) archive"
xcodebuild -project WidgetApp.xcodeproj -scheme WidgetApp -configuration Release -destination "generic/platform=iOS" -allowProvisioningUpdates archive 2>&1 | grep -E "error:|warning: .*(sign|provision)|ARCHIVE|Archive at|\*\*" | tail -20
echo "== done"
} 2>&1 | tee Scripts/release/05-archive.log
