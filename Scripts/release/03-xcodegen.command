#!/bin/bash
cd "$(dirname "$0")/../.."
xcodegen generate 2>&1 | tail -5 | tee Scripts/release/03-xcodegen.log
ls WidgetApp.xcodeproj/xcshareddata/xcschemes/ >> Scripts/release/03-xcodegen.log 2>&1
