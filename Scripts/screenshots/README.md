# App Store screenshot pipeline

1. **Capture** raw screenshots from the simulator (6.9"-class iPhone recommended):
   ```sh
   INTERACTIVE=1 scripts/screenshots/capture.sh <udid> en-US [path/to/WidgetApp.app]
   ```
   Repeat for `tr`, `fr-FR` and `es-ES`. In interactive mode the script pauses before each shot so you can place widgets on the home screen and navigate (iOS doesn't let a script add widgets). If you set `STOP_AFTER_LAUNCH=1`, it only boots, installs and launches, as a smoke test.
2. **Compose** framed 1290×2796 images:
   ```sh
   python3 scripts/screenshots/compose.py            # every locale in raw/
   python3 scripts/screenshots/compose.py --locale tr
   ```
   Output goes to `scripts/screenshots/out/<locale>/`. The captions are in `captions.json`. They are matched to the files in sorted file-name order, or by file stem if a locale's value is an object instead of a list.

Requirements: Xcode command-line tools, and python3 with Pillow (`pip3 install Pillow`).
Fonts: SF Pro (`/System/Library/Fonts/SFNS.ttf`) on macOS, falling back to Arial Bold or DejaVu Sans Bold.
`raw/` and `out/` are generated. Keep them out of git if you don't want binaries in the repo.
