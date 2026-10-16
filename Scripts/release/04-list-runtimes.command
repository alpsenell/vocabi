#!/bin/bash
cd "$(dirname "$0")/../.."
{ xcrun simctl list runtimes; echo ----; xcrun simctl list devices available | grep -i "pro max\|plus"; } > Scripts/release/04-list-runtimes.log 2>&1
