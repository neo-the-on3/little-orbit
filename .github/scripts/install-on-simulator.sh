#!/usr/bin/env bash
# Installs a built app on a simulator, launches it, then shuts the simulator down (#77, #138).
#
# Usage: install-on-simulator.sh <platform> <device-name-prefix> <app>
#   platform            watchOS or iOS, as in the CoreSimulator runtime id
#   device-name-prefix  such as "Apple Watch" or "iPhone"
#   app                 the built .app bundle
#
# The simulator is booted and waited for, and must still be Booted before the install. If it reports
# not Booted right after bootstatus succeeded, the boot is retried once: shut down, boot, wait. A boot
# that runs out of time isn't retried. CoreSimulator sometimes shuts the simulator down or dies during
# the install (SimError 405, Mach error -308). Then the install is retried once: shut down, boot, wait,
# install again. The boot retry and the install retry share one retry per platform, so neither stacks on
# the other. Any other install error, an install that times out while the simulator is still Booted, or
# a failure with the retry already spent, fails the step.
#
# Logs name only the platform, the simulator's UDID and the attempt, never a path or user data.
set -euo pipefail

# A first boot on an older runtime can include a slow data migration (221 s seen on iOS 27.1).
readonly boot_timeout=600
readonly install_timeout=300
# Shutdown, launch and terminate normally take seconds.
readonly command_timeout=120

platform="$1"
name_prefix="$2"
app="$3"
udid=""
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

# Prints the UDID of an available simulator for the platform, preferring the 27.2 runtime and otherwise
# the newest 27.x runtime installed. Devices are sorted by name, then UDID, so the pick is stable.
pick_simulator() {
  xcrun simctl list devices available -j | python3 -c '
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

is_booted() {
  xcrun simctl list devices 2>/dev/null | grep -F "$udid" | grep -q "(Booted)"
}

# Boots the simulator if needed and waits until it's ready, under the boot limit.
boot_and_wait() {
  log "booting"
  if ! with_timeout "$boot_timeout" xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1; then
    log "boot didn't finish"
    return 1
  fi
}

# Boots and waits, then checks the simulator is still Booted. If it isn't, and the retry isn't spent,
# shuts it down and boots and waits once more. A boot that runs out of time fails with no retry.
boot() {
  boot_and_wait || return 1
  if is_booted; then
    return 0
  fi
  if [ "$retries_left" -eq 0 ]; then
    log "not Booted after bootstatus, retry already used"
    return 1
  fi
  retries_left=0
  log "boot retry: not Booted after bootstatus"
  with_timeout "$command_timeout" xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  boot_and_wait || return 1
  if ! is_booted; then
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
  if ! is_booted; then
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
udid="$(pick_simulator)"

boot
result=0
install_once 1 || result=$?
if [ "$result" -eq 1 ] && [ "$retries_left" -eq 0 ]; then
  log "no install retry: retry already used"
elif [ "$result" -eq 1 ]; then
  retries_left=0
  log "retrying once after a fresh boot"
  with_timeout "$command_timeout" xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
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
