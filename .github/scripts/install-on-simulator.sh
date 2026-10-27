#!/usr/bin/env bash
# Installs a built app on a simulator, launches it, then shuts the simulator down (#77, #138, #287).
#
# Usage: install-on-simulator.sh <platform> <device-name-prefix> <app>
#   platform            watchOS or iOS, as in the CoreSimulator runtime id
#   device-name-prefix  such as "Apple Watch" or "iPhone"
#   app                 the built .app bundle
#
# watchOS gets a fresh simulator each run (#287): `simctl create` on the exact runtime and device type
# the build step used (ci.yml builds for "Apple Watch Series 12 (42mm)", OS 27.0), read from
# `simctl list -j runtimes devicetypes`. The image's stock watch device isn't used: CoreSimulator has
# reported it not Booted after a successful bootstatus, and not available at all, in the same job that
# built against it. A retry replaces the created device with a new one, first restarting CoreSimulator
# if the runtime itself is no longer listed. The created device is shut down and deleted on exit; a
# failed cleanup is only logged.
# iOS still picks an available stock device, preferring the 27.2 runtime, else the newest 27.x.
#
# The simulator is booted, bootstatus is waited for, and then the state is polled until it reads Booted.
# If it never does, the boot is retried once: shut down, wait until the state reads Shutdown (or, for a
# created device, replace it), boot, wait.
# A boot that runs out of time isn't retried. CoreSimulator sometimes shuts the simulator down or dies
# during the install (SimError 405, Mach error -308). Then the install is retried once the same way, and
# installed again. The boot retry and the install retry share one retry per platform, so neither stacks
# on the other. Any other install error, an install that times out while the simulator is still Booted,
# or a failure with the retry already spent, fails the step, and then simctl diagnostics are printed.
#
# Logs name only the platform, the simulator's UDID, runtime, device type, state and the attempt, never a
# path or user data.
set -euo pipefail

# A first boot on an older runtime can include a slow data migration (221 s seen on iOS 27.1).
readonly boot_timeout=600
readonly install_timeout=300
# Shutdown, launch, terminate, create and delete normally take seconds.
readonly command_timeout=120
# How long the state may take to settle to Booted after bootstatus, or to Shutdown after a shutdown.
readonly state_timeout=60
# How long a runtime that isn't listed as available yet is waited for, first and after a CoreSimulator
# restart.
readonly runtime_timeout=60
readonly recovery_runtime_timeout=180

# The watch simulator the build step used (ci.yml, "LittleOrbit watchOS" destination). Keep in step.
readonly watch_device_type="Apple Watch Series 12 (42mm)"
readonly watch_os_version="27.0"

platform="$1"
name_prefix="$2"
app="$3"
udid=""
created_udid=""
# One retry per platform, shared by the boot retry and the install retry.
retries_left=1

log() {
  echo "${platform} ${udid}: $*"
}

# Runs a command with a time limit in seconds; a command that runs out is killed and exits 142.
# perl ships with macOS, and coreutils' timeout doesn't.
with_timeout() {
  local seconds="$1"
  shift
  perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
}

# Prints the simulator's state (Booted, Shutdown, Booting, ShuttingDown...), "missing" when CoreSimulator
# doesn't list the UDID, or "unknown" when simctl can't be read.
device_state() {
  local state
  state="$(with_timeout "$command_timeout" xcrun simctl list -j devices 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    print("unknown")
    sys.exit()
for devices in data.get("devices", {}).values():
    for device in devices:
        if device.get("udid") == sys.argv[1]:
            print(device.get("state", "unknown"))
            sys.exit()
print("missing")
' "$udid")" || true
  echo "${state:-unknown}"
}

# Polls until the simulator's state is the one wanted, for at most the given seconds.
wait_for_state() {
  local wanted="$1" seconds="$2" state deadline
  deadline=$((SECONDS + seconds))
  while :; do
    state="$(device_state)"
    if [ "$state" = "$wanted" ]; then
      return 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      log "state is ${state}, not ${wanted}, after ${seconds} s"
      return 1
    fi
    sleep 2
  done
}

# Prints what CoreSimulator reports for this platform: its runtimes, its devices and their states, and
# this simulator's state, then a short CoreSimulator log tail. Only names, versions, UDIDs, identifiers
# and states are printed; paths in the log tail are masked. Output is bounded.
dump_diagnostics() {
  echo "::group::simctl diagnostics (${platform} ${udid})"
  with_timeout "$command_timeout" xcrun simctl list -j devices runtimes 2>/dev/null | python3 -c '
import json, sys
platform, udid = sys.argv[1], sys.argv[2]
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit("simctl list -j devices runtimes: no readable output")
print("runtimes:")
for r in data.get("runtimes", []):
    if r.get("platform") == platform or (".SimRuntime.%s-" % platform) in r.get("identifier", ""):
        print("  %s %s available=%s %s" % (r.get("identifier"), r.get("version"),
              r.get("isAvailable"), r.get("availabilityError", "")))
print("devices:")
for key, devices in sorted(data.get("devices", {}).items()):
    if (".SimRuntime.%s-" % platform) not in key and not any(d.get("udid") == udid for d in devices):
        continue
    for d in devices:
        print("  %s %s %s %s available=%s %s" % (key.rsplit(".", 1)[-1], d.get("udid"), d.get("name"),
              d.get("state"), d.get("isAvailable"), d.get("availabilityError", "")))
' "$platform" "$udid" 2>&1 | head -n 80 || true
  if [ -n "$udid" ]; then
    echo "state of ${udid}: $(device_state)"
  fi
  echo "simctl runtime list:"
  with_timeout "$command_timeout" xcrun simctl runtime list 2>&1 |
    sed -E 's#(/(Users|private|var|Library|Applications|System|tmp|opt)/)[^ ]*#<path>#g' |
    head -n 40 || true
  echo "CoreSimulator log, last 3 minutes (tail):"
  with_timeout 30 log show --last 3m --style compact \
    --predicate 'subsystem BEGINSWITH "com.apple.CoreSimulator"' 2>/dev/null |
    sed -E 's#(/(Users|private|var|Library|Applications|System|tmp|opt)/)[^ ]*#<path>#g' |
    tail -n 40 || true
  echo "::endgroup::"
}

on_exit() {
  local status=$?
  set +e
  if [ "$status" -ne 0 ]; then
    dump_diagnostics
  fi
  if [ -n "$created_udid" ]; then
    with_timeout "$command_timeout" xcrun simctl shutdown "$created_udid" >/dev/null 2>&1
    if with_timeout "$command_timeout" xcrun simctl delete "$created_udid" >/dev/null 2>&1; then
      echo "${platform} ${created_udid}: deleted"
    else
      echo "warning: ${platform} ${created_udid}: couldn't delete the created simulator."
    fi
  fi
  exit "$status"
}
trap on_exit EXIT

# Prints "<runtime id> <device type id>" for the newest available runtime whose version matches the
# pinned version (27.0 matches 27.0 and 27.0.x), and the pinned device type it supports. If the runtime
# doesn't support that device type, falls back to the last supported device type named <prefix>*, with a
# warning. Fails when no such runtime is available.
resolve_runtime_and_type() {
  local version="$1" type_name="$2"
  with_timeout "$command_timeout" xcrun simctl list -j runtimes devicetypes | python3 -c '
import json, sys
platform, version, type_name, prefix = sys.argv[1:5]

def parts(text):
    return tuple(int(p) for p in text.split(".") if p.isdigit())

data = json.load(sys.stdin)
wanted = parts(version)
runtimes = [
    r for r in data.get("runtimes", [])
    if r.get("isAvailable")
    and (r.get("platform") == platform or (".SimRuntime.%s-" % platform) in r.get("identifier", ""))
    and parts(r.get("version", ""))[: len(wanted)] == wanted
]
if not runtimes:
    sys.exit("error: no available %s %s runtime." % (platform, version))
runtime = max(runtimes, key=lambda r: parts(r["version"]))
known = {t["identifier"]: t for t in data.get("devicetypes", []) if "identifier" in t}
types = runtime.get("supportedDeviceTypes") or list(known.values())
if known:
    types = [t for t in types if t.get("identifier") in known]
exact = [t for t in types if t.get("name") == type_name]
if exact:
    device_type = exact[0]
else:
    similar = sorted((t for t in types if t.get("name", "").startswith(prefix)), key=lambda t: t["name"])
    if not similar:
        sys.exit("error: %s %s supports no device type named %s*." % (platform, runtime["version"], prefix))
    device_type = similar[-1]
    print("warning: %s %s has no %s; using %s." % (platform, runtime["version"], type_name,
          device_type["name"]), file=sys.stderr)
print(runtime["identifier"], device_type["identifier"])
' "$platform" "$version" "$type_name" "$name_prefix"
}

# Creates a fresh simulator on the pinned runtime and device type, and prints its UDID. A runtime that
# isn't listed as available yet is waited for, for at most the given seconds.
create_simulator() {
  local version="$1" type_name="$2" seconds="$3" resolved runtime_id type_id deadline name
  deadline=$((SECONDS + seconds))
  until resolved="$(resolve_runtime_and_type "$version" "$type_name")"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "error: no usable ${platform} ${version} runtime after ${seconds} s." >&2
      return 1
    fi
    echo "${platform}: waiting for the ${version} runtime" >&2
    sleep 5
  done
  read -r runtime_id type_id <<<"$resolved"
  name="little-orbit-ci-${platform}-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-$$"
  echo "${platform}: creating a simulator, ${type_id##*.} on ${runtime_id##*.}" >&2
  with_timeout "$command_timeout" xcrun simctl create "$name" "$type_id" "$runtime_id"
}

# Prints the UDID of an available simulator for the platform, preferring the 27.2 runtime and otherwise
# the newest 27.x runtime installed. Devices are sorted by name, then UDID, so the pick is stable.
pick_simulator() {
  with_timeout "$command_timeout" xcrun simctl list devices available -j | python3 -c '
import json, re, sys

platform, name_prefix = sys.argv[1], sys.argv[2]
wanted = (27, 2)
runtimes = {}
for key, devices in json.load(sys.stdin)["devices"].items():
    # Exact runtime id, optionally with a device-specific suffix such as
    # iOS-27-2-iPhone19-4. Runtimes with the same version merge their devices.
    match = re.fullmatch(
        r"com\.apple\.CoreSimulator\.SimRuntime\.%s-(\d+)-(\d+)(?:-.+)?" % re.escape(platform), key
    )
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    if version[0] != wanted[0]:
        continue
    matching = [d for d in devices if d["name"].startswith(name_prefix)]
    if matching:
        runtimes.setdefault(version, []).extend(matching)
if not runtimes:
    sys.exit("error: no available %s 27.x simulator named %s*." % (platform, name_prefix))
version = wanted if wanted in runtimes else max(runtimes)
if version != wanted:
    print("warning: no %s 27.2 runtime; using %d.%d." % ((platform,) + version), file=sys.stderr)
device = sorted(runtimes[version], key=lambda d: (d["name"], d["udid"]))[0]
print(device["udid"])
' "$platform" "$name_prefix"
}

# Shuts the simulator down and waits until the state reads Shutdown, so a following boot starts clean.
shutdown_and_wait() {
  with_timeout "$command_timeout" xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  wait_for_state Shutdown "$state_timeout"
}

# Replaces the created watch simulator with a new one on the same pinned runtime. CoreSimulator has
# dropped the watchOS 27.0 runtime mid-step ("runtime profile not found"), leaving every device on it
# unavailable. If the runtime is no longer listed, CoreSimulatorService is restarted so it registers
# the runtime again, and the runtime is waited for under the recovery limit.
recreate_simulator() {
  log "replacing the simulator"
  shutdown_and_wait || true
  with_timeout "$command_timeout" xcrun simctl delete "$created_udid" >/dev/null 2>&1 ||
    log "warning: couldn't delete the old simulator"
  created_udid=""
  if ! resolve_runtime_and_type "$watch_os_version" "$watch_device_type" >/dev/null 2>&1; then
    log "the ${watch_os_version} runtime is no longer available; restarting CoreSimulator"
    with_timeout "$command_timeout" xcrun simctl shutdown all >/dev/null 2>&1 || true
    killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
  fi
  created_udid="$(create_simulator "$watch_os_version" "$watch_device_type" "$recovery_runtime_timeout")" ||
    return 1
  udid="$created_udid"
  log "created"
}

# Gets ready for the one retry: a created simulator is replaced, and a stock one is shut down and must
# reach Shutdown before it's booted again.
prepare_retry() {
  if [ -n "$created_udid" ]; then
    recreate_simulator
  else
    shutdown_and_wait
  fi
}

# Boots the simulator if needed, waits until bootstatus says it's ready, under the boot limit, then polls
# until the state reads Booted. Returns 1 when bootstatus failed or ran out of time, and 2 when it
# succeeded but the state never read Booted.
boot_and_wait() {
  log "booting"
  if ! with_timeout "$boot_timeout" xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1; then
    log "boot didn't finish"
    return 1
  fi
  wait_for_state Booted "$state_timeout" || return 2
}

# Boots and waits. If the state never reads Booted, and the retry isn't spent, shuts the simulator down,
# waits for Shutdown, and boots and waits once more. A boot that runs out of time fails with no retry.
boot() {
  local status=0
  boot_and_wait || status=$?
  if [ "$status" -eq 0 ]; then
    return 0
  fi
  if [ "$status" -ne 2 ]; then
    return 1
  fi
  if [ -z "$created_udid" ] && [ "$(device_state)" = "missing" ]; then
    log "simulator is no longer listed"
    return 1
  fi
  if [ "$retries_left" -eq 0 ]; then
    log "not Booted after bootstatus, retry already used"
    return 1
  fi
  retries_left=0
  log "boot retry: not Booted after bootstatus"
  prepare_retry || return 1
  if ! boot_and_wait; then
    log "not Booted after boot retry"
    return 1
  fi
}

# One install attempt. Returns 0 when it worked, 1 when the simulator failed under it (CoreSimulator's
# SimError 405, Mach error -308, or no longer Booted), which is worth one retry, and 2 for any other error.
install_once() {
  local attempt="$1" errors status=0 cause
  errors="$(mktemp)"
  log "install, attempt ${attempt}"
  with_timeout "$install_timeout" xcrun simctl install "$udid" "$app" >/dev/null 2>"$errors" || status=$?
  if [ "$status" -eq 0 ]; then
    rm -f "$errors"
    return 0
  fi
  # Only CoreSimulator's error domain and code are logged: the rest of its message can name paths.
  cause="$(grep -oE 'domain=[A-Za-z.]+, code=-?[0-9]+' "$errors" | head -n 1 || true)"
  rm -f "$errors"
  log "install attempt ${attempt} failed: exit ${status}${cause:+, ${cause}}"
  case "$cause" in
    "domain=com.apple.CoreSimulator.SimError, code=405" | "domain=NSMachErrorDomain, code=-308") return 1 ;;
  esac
  if [ "$(device_state)" != "Booted" ]; then
    log "simulator is no longer Booted"
    return 1
  fi
  return 2
}

if [ ! -d "$app" ]; then
  echo "error: the ${platform} app wasn't built." >&2
  exit 1
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app}/Info.plist")"
if [ "$platform" = "watchOS" ]; then
  created_udid="$(create_simulator "$watch_os_version" "$watch_device_type" "$runtime_timeout")"
  udid="$created_udid"
  log "created"
else
  udid="$(pick_simulator)"
fi

boot
result=0
install_once 1 || result=$?
if [ "$result" -eq 1 ] && [ "$retries_left" -eq 0 ]; then
  log "no install retry: retry already used"
elif [ "$result" -eq 1 ]; then
  retries_left=0
  log "retrying once after a fresh boot"
  prepare_retry
  boot
  result=0
  install_once 2 || result=$?
fi
if [ "$result" -ne 0 ]; then
  log "install failed"
  exit 1
fi

log "launch"
status=0
with_timeout "$command_timeout" xcrun simctl launch "$udid" "$bundle_id" >/dev/null 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
  log "launch failed: exit ${status}"
  exit 1
fi
with_timeout "$command_timeout" xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
with_timeout "$command_timeout" xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
log "installed and launched"
