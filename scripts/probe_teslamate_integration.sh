#!/usr/bin/env bash
set -euo pipefail

first_non_empty() {
  for value in "$@"; do
    value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

env_file="${MATEDRIVE_INTEGRATION_ENV_FILE:-.matedrive-integration.env}"
if [ -f "$env_file" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
fi

base_url="$(first_non_empty "${MATEDRIVE_INTEGRATION_BASE_URL:-}" "${MATEDROID_INTEGRATION_BASE_URL:-}" || true)"
token="$(first_non_empty "${MATEDRIVE_INTEGRATION_API_TOKEN:-}" "${MATEDROID_INTEGRATION_API_TOKEN:-}" || true)"
basic_username="$(first_non_empty "${MATEDRIVE_INTEGRATION_BASIC_USERNAME:-}" "${MATEDROID_INTEGRATION_BASIC_USERNAME:-}" || true)"
basic_password="$(first_non_empty "${MATEDRIVE_INTEGRATION_BASIC_PASSWORD:-}" "${MATEDROID_INTEGRATION_BASIC_PASSWORD:-}" || true)"
curl_bin="${MATEDRIVE_INTEGRATION_CURL:-curl}"
default_base_url="${MATEDRIVE_INTEGRATION_DEFAULT_BASE_URL:-http://127.0.0.1:3030}"
default_base_url="${default_base_url%/}"
probe_body="${TMPDIR:-/tmp}/matedrive_integration_probe.out"
probe_error="${TMPDIR:-/tmp}/matedrive_integration_probe.err"

if { [ -n "$basic_username" ] && [ -z "$basic_password" ]; } || { [ -z "$basic_username" ] && [ -n "$basic_password" ]; }; then
  echo "Basic Auth requires both MATEDRIVE_INTEGRATION_BASIC_USERNAME and MATEDRIVE_INTEGRATION_BASIC_PASSWORD."
  exit 1
fi

if [ -z "$base_url$token$basic_username$basic_password" ]; then
  probe_url="$default_base_url/api/v1/cars"
  http_code="$("$curl_bin" -sS --max-time 3 -o "$probe_body" -w '%{http_code}' "$probe_url" 2>"$probe_error" || true)"
  if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
    echo "TeslaMate API is reachable at $default_base_url, but it requires authentication."
    echo "Run with Bearer auth: MATEDRIVE_INTEGRATION_BASE_URL=$default_base_url MATEDRIVE_INTEGRATION_API_TOKEN=... make integration-test"
    echo "Or Basic auth: MATEDRIVE_INTEGRATION_BASE_URL=$default_base_url MATEDRIVE_INTEGRATION_BASIC_USERNAME=... MATEDRIVE_INTEGRATION_BASIC_PASSWORD=... make integration-test"
    exit 1
  fi
  if [ "$http_code" = "200" ]; then
    echo "TeslaMate API is reachable at $default_base_url without auth."
    echo "Run: MATEDRIVE_INTEGRATION_BASE_URL=$default_base_url make integration-test"
    exit 1
  fi
  echo "Set MATEDRIVE_INTEGRATION_BASE_URL for a local unauthenticated TeslaMate API, or set token/basic auth variables."
  echo "No usable TeslaMate API was detected at $default_base_url (HTTP ${http_code:-000})."
  exit 1
fi

if [ -z "$base_url" ]; then
  base_url="$default_base_url"
fi
base_url="${base_url%/}"

curl_args=(-sS --max-time 5 -o "$probe_body" -w '%{http_code}')
if [ -n "$token" ]; then
  curl_args+=(-H "Authorization: Bearer $token")
fi
if [ -n "$basic_username" ]; then
  curl_args+=(-u "$basic_username:$basic_password")
fi

probe_endpoint() {
  local label="$1"
  local path="$2"
  local allowed_codes="${3:-200}"
  local url="$base_url/$path"
  local http_code

  http_code="$("$curl_bin" "${curl_args[@]}" "$url" 2>"$probe_error" || true)"
  if printf '%s\n' "$allowed_codes" | tr ',' '\n' | grep -Fxq "$http_code"; then
    return 0
  fi
  case "$http_code" in
    401|403)
      echo "TeslaMate API is reachable at $base_url, but authentication failed for $label with HTTP $http_code."
      echo "Check MATEDRIVE_INTEGRATION_API_TOKEN or Basic Auth credentials."
      exit 1
      ;;
    000|"")
      echo "TeslaMate API preflight could not connect to $base_url while checking $label."
      cat "$probe_error" 2>/dev/null || true
      exit 1
      ;;
    *)
      echo "TeslaMate API preflight returned HTTP $http_code from $url."
      head -c 240 "$probe_body" 2>/dev/null || true
      echo
      exit 1
      ;;
  esac
}

extract_first_number() {
  local file="$1"
  shift
  python3 - "$file" "$@" <<'PY'
import json
import sys

path = sys.argv[1]
keys = set(sys.argv[2:])

try:
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception:
    sys.exit(1)

def numeric_text(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.isdigit():
            return stripped
    return None

def walk(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in keys:
                found = numeric_text(child)
                if found is not None:
                    return found
        for child in value.values():
            found = walk(child)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = walk(child)
            if found is not None:
                return found
    return None

found = walk(payload)
if found is None:
    sys.exit(1)
print(found, end="")
PY
}

check_vehicle_metadata() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

path = sys.argv[1]

try:
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception:
    print("TeslaMate API preflight could not parse vehicle list JSON.")
    sys.exit(2)

def first_car(value):
    if isinstance(value, dict):
        for key in ("cars", "vehicles"):
            child = value.get(key)
            if isinstance(child, list) and child:
                return child[0]
        for key in ("car", "vehicle"):
            child = value.get(key)
            if isinstance(child, dict):
                return child
        for child in value.values():
            found = first_car(child)
            if found is not None:
                return found
    if isinstance(value, list) and value:
        return value[0] if isinstance(value[0], dict) else None
    return None

def text_at(value, *path):
    current = value
    for key in path:
        if not isinstance(current, dict):
            return ""
        current = current.get(key)
    if current is None:
        return ""
    text = str(current).strip()
    return text

car = first_car(payload)
if not isinstance(car, dict):
    print("TeslaMate API preflight could not find vehicle metadata in the vehicle list.")
    sys.exit(2)

display_name = text_at(car, "displayName") or text_at(car, "display_name") or text_at(car, "name")
model = (
    text_at(car, "model")
    or text_at(car, "carDetails", "model")
    or text_at(car, "car_details", "model")
    or text_at(car, "vehicleConfig", "car_type")
    or text_at(car, "vehicle_config", "car_type")
)
exterior_color = (
    text_at(car, "exteriorColor")
    or text_at(car, "exterior_color")
    or text_at(car, "carExterior", "exteriorColor")
    or text_at(car, "car_exterior", "exterior_color")
    or text_at(car, "vehicleConfig", "exterior_color")
    or text_at(car, "vehicle_config", "exterior_color")
)
wheel_type = (
    text_at(car, "wheelType")
    or text_at(car, "wheel_type")
    or text_at(car, "carExterior", "wheelType")
    or text_at(car, "car_exterior", "wheel_type")
    or text_at(car, "vehicleConfig", "wheel_type")
    or text_at(car, "vehicle_config", "wheel_type")
)

legacy_names = {"", "Tesla", "MateDroid", "MateDrive"}
has_model = model not in legacy_names
has_usable_name = display_name not in legacy_names

if not has_model and not has_usable_name:
    print("TeslaMate API preflight found a vehicle id, but model and usable vehicle name are missing.")
    print("The MateDrive dashboard may fall back to a generic Tesla image/name.")
    sys.exit(2)

if not has_model:
    print(f"TeslaMate API preflight warning: vehicle name '{display_name}' is readable, but model is missing.")
elif not exterior_color or not wheel_type:
    print(f"TeslaMate API preflight warning: vehicle model '{model}' is readable, but exterior color or wheel type is missing.")
else:
    print(f"TeslaMate API preflight identified vehicle metadata for {model}.")
PY
}

probe_endpoint "vehicle list" "api/v1/cars"
car_id="$(extract_first_number "$probe_body" carId car_id id || true)"
if [ -z "$car_id" ]; then
  echo "TeslaMate API preflight could not find a vehicle id in $base_url/api/v1/cars."
  head -c 240 "$probe_body" 2>/dev/null || true
  echo
  exit 1
fi
if ! check_vehicle_metadata "$probe_body"; then
  exit 1
fi

probe_endpoint "vehicle status" "api/v1/cars/$car_id/status"
probe_endpoint "charge list" "api/v1/cars/$car_id/charges?page=1&show=1"
charge_id="$(extract_first_number "$probe_body" chargeId charge_id id || true)"
if [ -n "$charge_id" ]; then
  probe_endpoint "charge detail" "api/v1/cars/$car_id/charges/$charge_id"
fi

probe_endpoint "drive list" "api/v1/cars/$car_id/drives?page=1&show=1"
drive_id="$(extract_first_number "$probe_body" driveId drive_id id || true)"
if [ -n "$drive_id" ]; then
  probe_endpoint "drive detail" "api/v1/cars/$car_id/drives/$drive_id"
fi

probe_endpoint "battery health" "api/v1/cars/$car_id/battery-health"
probe_endpoint "software updates" "api/v1/cars/$car_id/updates?page=1&show=1"
probe_endpoint "current charge" "api/v1/cars/$car_id/charges/current" "200,204"
probe_endpoint "global settings" "api/v1/globalsettings"
echo "TeslaMate API preflight passed at $base_url."
