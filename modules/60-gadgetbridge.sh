#!/data/data/com.termux/files/usr/bin/bash
# Module: Gadgetbridge — keep a Garmin watch connected (auto-reconnect).
#
# Symptom: Gadgetbridge syncs fine but never reconnects on its own. You open the
# app and connect by hand every single time. Find My Phone (which the watch
# initiates, so it only works if the link is already up) is therefore dead.
#
# The cause is NOT an Android background restriction. The Doze allowlist,
# "unrestricted battery use", the app-standby bucket and the companion-device
# association are all red herrings — they were already correct, and setting them
# changes nothing. The block is inside Gadgetbridge:
#
#   prefs_key_device_reconnect_on_acl   ("Connect back to device", per-device)
#
# defaults to FALSE. Every reconnect trigger — the ACL_CONNECTED broadcast the
# watch raises when it reconnects itself, and the CompanionDeviceManager "device
# appeared" callback — funnels into BluetoothConnectReceiver.observedDevice(),
# which bails out unless the device is already in a WAITING_FOR_* state or
# DEVICE_CONNECT_BACK is true. After a boot it is in neither, so every trigger
# was being dropped on the floor.
#
# This module also turns OFF prefs_general_key_auto_reconnect_scan. Turning that
# ON is widespread advice and it is actively counterproductive: per BtLEQueue it
# makes Gadgetbridge *skip* mBluetoothGatt.connect() — the controller
# accept-list reconnect that survives Doze and screen-off — and wait on an
# app-level BLE scan instead. That scan filters on MAC, and a Garmin advertises
# under rotating Resolvable Private Addresses (its bond record carries an IRK),
# so the filter can never match it.
#
# Root only. Idempotent: it no-ops when the prefs are already correct, and only
# stops/restarts Gadgetbridge when something actually needs changing.

GB_PKG="nodomain.freeyourgadget.gadgetbridge"
GB_ACTIVITY="$GB_PKG/.activities.ControlCenterv2"

# Emit the root-side prefs script. Takes "check" (exit 1 if changes are needed)
# or "apply" (rewrite the prefs).
#
# Two rules this script exists to enforce:
#
#   1. NEVER `sed -i` a file under /data/data/<pkg>/. sed -i writes a temp file
#      and renames it over the target, which drops the app's per-UID SELinux MLS
#      categories (app_data_file:s0:c168,c257,... -> app_data_file:s0) and can
#      change the owner. The app is then walled off from its own preferences.
#      Instead we `cat tmp > target`, which truncates the existing inode in
#      place and so preserves owner, mode and SELinux label.
#
#   2. Only touch device-settings files that are actually Garmin
#      (devicesettings_<MAC>.xml containing garmin_* keys), so headphones and
#      other paired gadgets are left alone.
_gb_root_script() {
  cat <<'ROOTEOF'
set -eu
PKG=nodomain.freeyourgadget.gadgetbridge
SP=/data/data/$PKG/shared_prefs
MAIN=$SP/${PKG}_preferences.xml
MODE=$1
NEEDED=0

# want <file> <key> <value> -> 0 if already correct
want() { grep -q "name=\"$2\" value=\"$3\"" "$1" 2>/dev/null; }

# set_bool <file> <key> <value>
set_bool() {
  f=$1; k=$2; v=$3
  [ -f "$f" ] || return 0
  want "$f" "$k" "$v" && return 0
  NEEDED=1
  [ "$MODE" = apply ] || { echo "  would set $k=$v in ${f##*/}"; return 0; }

  tmp=/data/local/tmp/.gbpref.$$
  if grep -q "name=\"$k\"" "$f"; then
    # Key present with the wrong value: rewrite that one line.
    sed "s|<boolean name=\"$k\" value=\"[a-z]*\" />|<boolean name=\"$k\" value=\"$v\" />|" "$f" >"$tmp"
  else
    # Key absent (sitting on its compiled-in default): insert before </map>.
    awk -v line="    <boolean name=\"$k\" value=\"$v\" />" \
        '/<\/map>/ { print line } { print }' "$f" >"$tmp"
  fi
  # Truncate-in-place: keeps the inode, so owner/mode/SELinux label survive.
  cat "$tmp" >"$f"
  rm -f "$tmp"
  echo "  set $k=$v in ${f##*/}"
}

# Repair an already-damaged label (e.g. from a previous sed -i), by copying the
# context and owner off the shared_prefs directory that installd labelled.
relabel() {
  [ -f "$1" ] || return 0
  ctx=$(ls -Zd "$SP" | awk '{print $1}')
  own=$(ls -ld "$SP" | awk '{print $3":"$4}')
  chcon "$ctx" "$1" 2>/dev/null || true
  chown "$own" "$1" 2>/dev/null || true
}

[ -f "$MAIN" ] || { echo "no Gadgetbridge prefs yet (open the app once)"; exit 0; }

# --- Global connection prefs -------------------------------------------------
set_bool "$MAIN" prefs_general_key_auto_reconnect_scan false
set_bool "$MAIN" general_autoconnectonbluetooth        true
set_bool "$MAIN" general_autostartonboot               true

# --- Per-Garmin-device prefs -------------------------------------------------
found_garmin=0
for f in "$SP"/devicesettings_*.xml; do
  [ -f "$f" ] || continue
  grep -qi 'garmin' "$f" || continue     # skip headphones etc.
  found_garmin=1
  set_bool "$f" prefs_key_device_reconnect_on_acl true
  set_bool "$f" prefs_key_device_auto_reconnect   true
done
[ "$found_garmin" = 1 ] || echo "  (no paired Garmin found; global prefs only)"

if [ "$MODE" = apply ]; then
  relabel "$MAIN"
  for f in "$SP"/devicesettings_*.xml; do relabel "$f"; done
fi

exit $NEEDED
ROOTEOF
}

run_gadgetbridge() {
  step "Gadgetbridge — Garmin auto-reconnect"

  if ! su -c 'id' 2>/dev/null | grep -q 'uid=0'; then
    warn "root (su) not available; skipping Gadgetbridge fix."
    warn "Grant Termux root in Magisk, then re-run: ./install.sh gadgetbridge"
    return 0
  fi

  if ! su -c "pm path $GB_PKG" >/dev/null 2>&1; then
    info "Gadgetbridge not installed; skipping."
    return 0
  fi

  # --- OS-level: safe to reassert every run, needs no app restart -------------
  # These were already correct on the diagnosed device; we set them so a fresh
  # phone lands in the same state rather than relying on the user having done it.
  su -c "dumpsys deviceidle whitelist +$GB_PKG" >/dev/null 2>&1 \
    && ok "Doze allowlist: exempt" \
    || warn "could not add $GB_PKG to the Doze allowlist"
  su -c "cmd appops set $GB_PKG RUN_ANY_IN_BACKGROUND allow" >/dev/null 2>&1 \
    && ok "appop RUN_ANY_IN_BACKGROUND: allow" \
    || warn "could not set RUN_ANY_IN_BACKGROUND"

  # --- App prefs: only stop the app if something actually needs changing -------
  local script="$TMPDIR/gb-prefs.$$.sh"
  _gb_root_script >"$script"

  if su -c "sh '$script'" check >/dev/null 2>&1; then
    ok "Connection prefs already correct; leaving Gadgetbridge running."
    rm -f "$script"
    return 0
  fi

  info "Connection prefs need updating; Gadgetbridge must be stopped to edit them."
  su -c "am force-stop $GB_PKG"
  su -c "sh '$script'" apply || true

  # force-stop parks the app in FLAG_STOPPED, where it receives no broadcasts —
  # including BOOT_COMPLETED. Leaving it there would disable the very
  # autostart-on-boot this module just turned on. Launching it clears the flag.
  su -c "am start -n $GB_ACTIVITY" >/dev/null 2>&1 \
    || warn "could not relaunch Gadgetbridge — open it once by hand, or it will not start on boot."

  rm -f "$script"
  ok "Gadgetbridge reconnect prefs applied and app relaunched."

  cat <<'EOF'

        Verify (no user interaction required):
            su -c 'cmd bluetooth_manager disable'; sleep 10
            su -c 'cmd bluetooth_manager enable'
            # wait ~15s, then:
            su -c 'dumpsys bluetooth_manager' | grep -A1 'appName: nodomain.freeyourgadget'
        A Connection<...> line means it reconnected on its own.

        The real test is a reboot: do NOT open the app, wait ~2 min, and check
        the watch connects by itself.
EOF
}
