#!/usr/bin/env bash
# Capture raw App Store screenshots of Vocabi from an iOS simulator.
#
# Usage:
#   scripts/screenshots/capture.sh <simulator-udid> <locale> [path/to/WidgetApp.app]
#     locale: en-US | tr | fr-FR | es-ES
#
# Output: scripts/screenshots/raw/<locale>/NN-<name>.png  (then run compose.py)
#
# Env:
#   INTERACTIVE=1   pause before each shot so you can arrange the screen by hand
#                   (adding widgets to the home screen can't be scripted)
#   STOP_AFTER_LAUNCH=1   boot + install + launch only, take no screenshots (smoke test)
#   DELAY=<sec>     wait after each navigation before capturing (default 3)
#
# The app language is forced per launch with -AppleLanguages/-AppleLocale launch
# arguments, and the simulator's global language is set with `defaults write` so
# the home screen and widget configuration UI match the locale too.
set -euo pipefail

BUNDLE_ID="com.alpsenel.wordwidget"
UDID="${1:?usage: capture.sh <udid> <locale> [app-path]}"
LOCALE="${2:?usage: capture.sh <udid> <locale> [app-path]}"
APP_PATH="${3:-}"
DELAY="${DELAY:-3}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/raw/$LOCALE"

case "$LOCALE" in
  en-US) LANG_CODE="en"; APPLE_LOCALE="en_US" ;;
  tr)    LANG_CODE="tr"; APPLE_LOCALE="tr_TR" ;;
  fr-FR) LANG_CODE="fr"; APPLE_LOCALE="fr_FR" ;;
  es-ES) LANG_CODE="es"; APPLE_LOCALE="es_ES" ;;
  *) echo "unsupported locale '$LOCALE' (en-US|tr|fr-FR|es-ES)" >&2; exit 2 ;;
esac

log() { printf '\033[35m▸\033[0m %s\n' "$*"; }

state() { xcrun simctl list devices | grep -F "$UDID" | sed -E 's/.*\((Booted|Shutdown|Shutting Down|Booting)\).*/\1/'; }

# 1. Boot
if [[ "$(state)" != "Booted" ]]; then
  log "booting $UDID"
  xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
log "simulator booted"

# 2. Global language so SpringBoard/widget gallery match (takes effect on next app launch;
#    SpringBoard picks it up after a respring, which `simctl` can't force, so for home-screen
#    shots in a new language reboot the simulator once after changing it).
xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array "$LANG_CODE"
xcrun simctl spawn "$UDID" defaults write -g AppleLocale -string "$APPLE_LOCALE"

# 3. Clean status bar (9:41, full battery)
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true

# 4. Install (optional)
if [[ -n "$APP_PATH" ]]; then
  log "installing $APP_PATH"
  xcrun simctl install "$UDID" "$APP_PATH"
fi
if ! xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "$BUNDLE_ID is not installed on $UDID; pass the .app path as the 3rd argument" >&2
  exit 1
fi

launch() {
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -AppleLanguages "($LANG_CODE)" -AppleLocale "$APPLE_LOCALE" "$@" >/dev/null
}

log "launching $BUNDLE_ID in $LOCALE"
launch
sleep "$DELAY"

if [[ "${STOP_AFTER_LAUNCH:-0}" == "1" ]]; then
  log "STOP_AFTER_LAUNCH=1, done (no screenshots taken)"
  exit 0
fi

mkdir -p "$OUT"
shot() {  # shot <file-stem> <hint for interactive mode>
  local name="$1" hint="$2"
  if [[ "${INTERACTIVE:-0}" == "1" ]]; then
    read -r -p "  → $hint  [Enter to capture $name] " _
  else
    sleep "$DELAY"
  fi
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null
  log "captured raw/$LOCALE/$name.png"
}

# Shot list: order must match captions.json (sorted by file name).
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true

# 01: home screen with a medium widget (arrange manually in INTERACTIVE mode)
# (simctl has no "home button"; in Simulator press Shift-Cmd-H, then add/arrange widgets)
open -a Simulator >/dev/null 2>&1 || true
shot "01-home-widget" "Go Home (Shift-Cmd-H) and show one Vocabi widget"

# 02: several widgets with different slots
shot "02-multi-widgets" "Show 2-3 Vocabi widgets with different slots"

# 03: refresh frequency setting (in-app)
launch
shot "03-frequency" "Open Settings, refresh frequency section"

# 04: language pair (onboarding/settings)
shot "04-languages" "Show the language pair picker"

# 05: quiz in progress (deep link)
xcrun simctl openurl "$UDID" "vocabi://quiz"
shot "05-quiz" "Answer a question so the result state shows"

# 06: leaderboard
shot "06-leaderboard" "Open the Leaderboard tab"

log "done → $OUT  (next: python3 scripts/screenshots/compose.py --locale $LOCALE)"
