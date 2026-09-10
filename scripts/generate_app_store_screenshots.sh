#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

simulator_name="${MATEDRIVE_SCREENSHOT_SIMULATOR_NAME:-MateDrive App Store 6.5}"
device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max"
runtime="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
derived_data="${MATEDRIVE_SCREENSHOT_DERIVED_DATA:-/tmp/MateDrive-AppStore-Screenshot-DerivedData}"
output_directory="${MATEDRIVE_SCREENSHOT_OUTPUT:-build/app-store-screenshots/zh-Hans}"

simulator_udid="$(
  xcrun simctl list devices available |
    awk -v name="$simulator_name" 'index($0, name) {gsub(/[()]/, "", $5); print $5; exit}'
)"
if [[ -z "$simulator_udid" ]]; then
  simulator_udid="$(xcrun simctl create "$simulator_name" "$device_type" "$runtime")"
fi

xcrun simctl boot "$simulator_udid" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_udid" -b
xcrun simctl status_bar "$simulator_udid" override \
  --time 09:41 \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4
xcrun simctl ui "$simulator_udid" appearance light

python3 - "$derived_data" "$output_directory" <<'PY'
from pathlib import Path
import shutil
import sys

for raw in sys.argv[1:]:
    path = Path(raw)
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
PY

xcodegen generate
xcodebuild \
  -project MateDrive.xcodeproj \
  -scheme MateDrive \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${simulator_udid}" \
  -derivedDataPath "$derived_data" \
  build

app_path="$derived_data/Build/Products/Debug-iphonesimulator/MateDrive.app"
xcrun simctl uninstall "$simulator_udid" com.matedrive.ios 2>/dev/null || true
xcrun simctl install "$simulator_udid" "$app_path"

# Complete first-launch database and cache initialization before any store image
# is captured. Each later launch still keeps the product's three-second splash.
SIMCTL_CHILD_MATEDRIVE_UI_TEST_MODE=1 \
SIMCTL_CHILD_MATEDRIVE_STORE_SCREENSHOT_MODE=1 \
SIMCTL_CHILD_MATEDRIVE_STORE_SCREENSHOT_ROUTE=dashboard \
SIMCTL_CHILD_MATEDRIVE_SKIP_LAUNCH_EXPERIENCE=1 \
  xcrun simctl launch --terminate-running-process \
    "$simulator_udid" \
    com.matedrive.ios >/dev/null
sleep "${MATEDRIVE_SCREENSHOT_WARMUP_SECONDS:-20}"

routes=(
  dashboard
  activity
  features
  drive-detail
  charge-detail
  battery
)
names=(
  01-dashboard
  02-activity
  03-features
  04-drive-detail
  05-charge-detail
  06-battery
)

for index in "${!routes[@]}"; do
  SIMCTL_CHILD_MATEDRIVE_UI_TEST_MODE=1 \
  SIMCTL_CHILD_MATEDRIVE_STORE_SCREENSHOT_MODE=1 \
  SIMCTL_CHILD_MATEDRIVE_STORE_SCREENSHOT_ROUTE="${routes[$index]}" \
  SIMCTL_CHILD_MATEDRIVE_SKIP_LAUNCH_EXPERIENCE=1 \
    xcrun simctl launch --terminate-running-process \
      "$simulator_udid" \
      com.matedrive.ios >/dev/null
  sleep "${MATEDRIVE_SCREENSHOT_SETTLE_SECONDS:-8}"
  xcrun simctl io "$simulator_udid" screenshot \
    "$output_directory/${names[$index]}.png" >/dev/null
done

python3 scripts/validate_app_store_screenshots.py "$output_directory"
printf 'App Store screenshots: %s\n' "$output_directory"
