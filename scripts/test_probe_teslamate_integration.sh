#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_script="$repo_root/scripts/probe_teslamate_integration.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_curl="$tmp_dir/fake-curl"
cat >"$fake_curl" <<'FAKECURL'
#!/usr/bin/env bash
set -euo pipefail

output=""
write_out=""
args=()
original_args=("$@")
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    -w)
      write_out="$2"
      shift 2
      ;;
    -sS|--max-time|-H|-u)
      if [ "$1" = "--max-time" ] || [ "$1" = "-H" ] || [ "$1" = "-u" ]; then
        shift 2
      else
        shift
      fi
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [ "${#args[@]}" -gt 0 ]; then
  url="${args[$((${#args[@]} - 1))]}"
else
  url=""
fi
printf '%s\n' "${original_args[@]}" >>"${MATEDRIVE_FAKE_CURL_ARGS:?}"
printf '%s\n' "$url" >>"${MATEDRIVE_FAKE_CURL_URL:?}"

status="${MATEDRIVE_FAKE_CURL_STATUS:-200}"
if [[ "$url" == */api/v1/globalsettings ]]; then
  status="${MATEDRIVE_FAKE_CURL_GLOBALSETTINGS_STATUS:-$status}"
fi
if [[ "$url" == */api/v1/cars/*/battery-health ]]; then
  status="${MATEDRIVE_FAKE_CURL_BATTERY_HEALTH_STATUS:-$status}"
fi

body="${MATEDRIVE_FAKE_CURL_BODY:-}"
if [ -z "$body" ]; then
  case "$url" in
    */api/v1/cars)
      body='{"data":{"cars":[{"carId":1,"displayName":"Blue 3","carDetails":{"model":"3"},"carExterior":{"exteriorColor":"PBSB","wheelType":"W39B"}}]}}'
      ;;
    */api/v1/cars/*/charges\?*)
      body='{"data":{"charges":[{"chargeId":10}]}}'
      ;;
    */api/v1/cars/*/drives\?*)
      body='{"data":{"drives":[{"driveId":20}]}}'
      ;;
    *)
      body='{"data":{}}'
      ;;
  esac
fi

case "$status" in
  000)
    echo "connection refused" >&2
    exit 7
    ;;
  *)
    printf '%s' "$body" >"$output"
    if [ "$write_out" = "%{http_code}" ]; then
      printf '%s' "$status"
    fi
    ;;
esac
FAKECURL
chmod +x "$fake_curl"

run_probe() {
  local status="$1"
  shift
  env -i \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin" \
    TMPDIR="$tmp_dir" \
    MATEDRIVE_FAKE_CURL_STATUS="$status" \
    MATEDRIVE_FAKE_CURL_GLOBALSETTINGS_STATUS="${MATEDRIVE_FAKE_CURL_GLOBALSETTINGS_STATUS:-}" \
    MATEDRIVE_FAKE_CURL_BATTERY_HEALTH_STATUS="${MATEDRIVE_FAKE_CURL_BATTERY_HEALTH_STATUS:-}" \
    MATEDRIVE_FAKE_CURL_BODY="${MATEDRIVE_FAKE_CURL_BODY:-}" \
    MATEDRIVE_FAKE_CURL_ARGS="$tmp_dir/args" \
    MATEDRIVE_FAKE_CURL_URL="$tmp_dir/url" \
    MATEDRIVE_INTEGRATION_CURL="$fake_curl" \
    MATEDRIVE_INTEGRATION_DEFAULT_BASE_URL="http://default.example" \
    MATEDRIVE_INTEGRATION_ENV_FILE="/dev/null" \
    "$@" \
    bash "$probe_script"
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq "$expected" "$file"; then
    echo "Expected '$expected' in $file" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_exit() {
  local expected_code="$1"
  local output="$2"
  shift 2
  set +e
  "$@" >"$output" 2>&1
  local actual_code="$?"
  set -e
  if [ "$actual_code" -ne "$expected_code" ]; then
    echo "Expected exit $expected_code, got $actual_code" >&2
    cat "$output" >&2
    exit 1
  fi
}

assert_exit 1 "$tmp_dir/no-auth.out" run_probe 401
assert_contains "$tmp_dir/no-auth.out" "TeslaMate API is reachable at http://default.example, but it requires authentication."

assert_exit 0 "$tmp_dir/token.out" run_probe 200 MATEDRIVE_INTEGRATION_BASE_URL=" http://teslamate.example " MATEDRIVE_INTEGRATION_API_TOKEN=" token "
assert_contains "$tmp_dir/token.out" "TeslaMate API preflight passed at http://teslamate.example."
assert_contains "$tmp_dir/token.out" "TeslaMate API preflight identified vehicle metadata for 3."
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/globalsettings"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars/1/status"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars/1/charges?page=1&show=1"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars/1/charges/10"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars/1/drives?page=1&show=1"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars/1/drives/20"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars/1/battery-health"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars/1/updates?page=1&show=1"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars/1/charges/current"
assert_contains "$tmp_dir/args" "Authorization: Bearer token"

MATEDRIVE_FAKE_CURL_BODY='{"meta":{"request":"ok"},"data":{"cars":[{"id":"7","displayName":"Model 3","car_details":{"model":"3"},"car_exterior":{"exterior_color":"PBSB","wheel_type":"W39B"}}]}}' assert_exit 0 "$tmp_dir/string-id.out" run_probe 200 MATEDRIVE_INTEGRATION_BASE_URL="http://teslamate.example" MATEDRIVE_INTEGRATION_API_TOKEN="token"
assert_contains "$tmp_dir/string-id.out" "TeslaMate API preflight passed at http://teslamate.example."
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars/7/status"

MATEDRIVE_FAKE_CURL_BODY='{"data":{"cars":[{"carId":1,"displayName":"Home Car"}]}}' assert_exit 0 "$tmp_dir/vehicle-name-only.out" run_probe 200 MATEDRIVE_INTEGRATION_BASE_URL="http://teslamate.example" MATEDRIVE_INTEGRATION_API_TOKEN="token"
assert_contains "$tmp_dir/vehicle-name-only.out" "vehicle name 'Home Car' is readable, but model is missing."

MATEDRIVE_FAKE_CURL_BODY='{"data":{"cars":[{"carId":1,"displayName":"MateDrive"}]}}' assert_exit 1 "$tmp_dir/vehicle-metadata-failure.out" run_probe 200 MATEDRIVE_INTEGRATION_BASE_URL="http://teslamate.example" MATEDRIVE_INTEGRATION_API_TOKEN="token"
assert_contains "$tmp_dir/vehicle-metadata-failure.out" "model and usable vehicle name are missing"

assert_exit 0 "$tmp_dir/trailing-slash.out" run_probe 200 MATEDRIVE_INTEGRATION_BASE_URL="http://teslamate.example/" MATEDRIVE_INTEGRATION_API_TOKEN="token"
assert_contains "$tmp_dir/trailing-slash.out" "TeslaMate API preflight passed at http://teslamate.example."
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/cars"
assert_contains "$tmp_dir/url" "http://teslamate.example/api/v1/globalsettings"

assert_exit 1 "$tmp_dir/basic.out" run_probe 200 MATEDRIVE_INTEGRATION_BASIC_USERNAME=" user "
assert_contains "$tmp_dir/basic.out" "Basic Auth requires both MATEDRIVE_INTEGRATION_BASIC_USERNAME and MATEDRIVE_INTEGRATION_BASIC_PASSWORD."

assert_exit 0 "$tmp_dir/basic-success.out" run_probe 200 MATEDRIVE_INTEGRATION_BASE_URL="http://teslamate.example" MATEDRIVE_INTEGRATION_BASIC_USERNAME=" user " MATEDRIVE_INTEGRATION_BASIC_PASSWORD=" pass "
assert_contains "$tmp_dir/basic-success.out" "TeslaMate API preflight passed at http://teslamate.example."
assert_contains "$tmp_dir/args" "user:pass"

env_file="$tmp_dir/integration.env"
cat >"$env_file" <<'ENVFILE'
MATEDRIVE_INTEGRATION_BASE_URL=http://envfile.example
MATEDRIVE_INTEGRATION_API_TOKEN=env-token
ENVFILE
assert_exit 0 "$tmp_dir/env-file.out" run_probe 200 MATEDRIVE_INTEGRATION_ENV_FILE="$env_file"
assert_contains "$tmp_dir/env-file.out" "TeslaMate API preflight passed at http://envfile.example."
assert_contains "$tmp_dir/args" "Authorization: Bearer env-token"

MATEDRIVE_FAKE_CURL_GLOBALSETTINGS_STATUS=404 assert_exit 1 "$tmp_dir/globalsettings-failure.out" run_probe 200 MATEDRIVE_INTEGRATION_BASE_URL="http://teslamate.example" MATEDRIVE_INTEGRATION_API_TOKEN="token"
assert_contains "$tmp_dir/globalsettings-failure.out" "TeslaMate API preflight returned HTTP 404 from http://teslamate.example/api/v1/globalsettings."

MATEDRIVE_FAKE_CURL_BATTERY_HEALTH_STATUS=404 assert_exit 1 "$tmp_dir/battery-health-failure.out" run_probe 200 MATEDRIVE_INTEGRATION_BASE_URL="http://teslamate.example" MATEDRIVE_INTEGRATION_API_TOKEN="token"
assert_contains "$tmp_dir/battery-health-failure.out" "TeslaMate API preflight returned HTTP 404 from http://teslamate.example/api/v1/cars/1/battery-health."

MATEDRIVE_FAKE_CURL_BODY='{"data":{"cars":[]}}' assert_exit 1 "$tmp_dir/no-car-id.out" run_probe 200 MATEDRIVE_INTEGRATION_BASE_URL="http://teslamate.example" MATEDRIVE_INTEGRATION_API_TOKEN="token"
assert_contains "$tmp_dir/no-car-id.out" "TeslaMate API preflight could not find a vehicle id in http://teslamate.example/api/v1/cars."

assert_exit 1 "$tmp_dir/offline.out" run_probe 000 MATEDRIVE_INTEGRATION_BASE_URL="http://offline.example"
assert_contains "$tmp_dir/offline.out" "TeslaMate API preflight could not connect to http://offline.example while checking vehicle list."

echo "probe_teslamate_integration tests passed"
