#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

team_id="${MATEDRIVE_DEVELOPMENT_TEAM:-}"
device_id="${MATEDRIVE_DEVICE_ID:-}"

if [[ -z "$team_id" ]]; then
  echo "Set MATEDRIVE_DEVELOPMENT_TEAM to the Apple Developer Team ID shown in Xcode Settings > Accounts."
  exit 2
fi

if [[ -z "$device_id" ]]; then
  device_json="$(mktemp)"
  trap 'rm -f "$device_json"' EXIT
  if xcrun devicectl list devices \
    --filter "hardwareProperties.deviceType == 'iPhone' AND connectionProperties.pairingState == 'paired'" \
    --json-output "$device_json" \
    --quiet; then
    device_id="$(/usr/bin/plutil -extract result.devices.0.identifier raw "$device_json" 2>/dev/null || true)"
  fi
fi

if [[ -z "$device_id" ]]; then
  echo "No available iPhone was found. Unlock and trust the phone, enable Developer Mode, and use an Xcode version that supports its iOS version."
  exit 3
fi

command -v xcodegen >/dev/null || {
  echo "xcodegen is required. Install it with: brew install xcodegen"
  exit 4
}

xcodegen generate

derived_data="$root_dir/build/device-derived-data"
xcodebuild \
  -project MateDrive.xcodeproj \
  -scheme MateDrive \
  -configuration Debug \
  -destination "id=$device_id" \
  -derivedDataPath "$derived_data" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_STYLE=Automatic \
  build

app_path="$derived_data/Build/Products/Debug-iphoneos/MateDrive.app"
[[ -d "$app_path" ]] || {
  echo "Built app was not found at $app_path"
  exit 5
}

xcrun devicectl device install app --device "$device_id" "$app_path"
if xcrun devicectl device process launch --device "$device_id" com.matedrive.ios; then
  echo "MateDrive was installed and launched on $device_id."
else
  echo "MateDrive was installed on $device_id, but iOS did not allow automatic launch. Unlock the phone and open MateDrive manually."
fi
