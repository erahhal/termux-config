#!/data/data/com.termux/files/usr/bin/bash
# Module: GCam pixel-feature fix.
#
# Ensures /system/etc/sysconfig/pixel_experience_2019.xml exists so the BSG
# GCam mod's power-button double-tap camera shortcut works. That shortcut
# fires the STILL_IMAGE_CAMERA intent; the mod NPEs on non-Pixel devices
# unless the com.google.android.feature.PIXEL_2019_EXPERIENCE system feature
# is present.
#
# /system is wiped by every OTA, so this file must be re-applied after each
# system update — which is exactly what re-running this module does. It is
# idempotent: if the feature is already registered, it no-ops.
#
# The one-time GCam config-merge (installs camera prefs into the app's
# shared_prefs) is a SEPARATE manual step — that config lives in /data and
# survives OTA, so it doesn't belong in this recurring fix. See:
#     assets/gcam/install-gcam-config.sh

GCAM_FEATURE="com.google.android.feature.PIXEL_2019_EXPERIENCE"
GCAM_SYSCONFIG="/system/etc/sysconfig/pixel_experience_2019.xml"

run_gcam() {
  step "GCam pixel-feature fix"

  # Root is required. Skip cleanly (don't abort the whole install) if su isn't
  # granted — matches how the rest of termux-config degrades on non-root.
  if ! su -c 'id' 2>/dev/null | grep -q 'uid=0'; then
    warn "root (su) not available; skipping GCam pixel-feature fix."
    warn "Grant Termux root in Magisk, then re-run: ./install.sh gcam"
    return 0
  fi

  # Already registered with the framework? Survives until the next OTA.
  if su -c 'pm list features' 2>/dev/null | grep -q "$GCAM_FEATURE"; then
    ok "Pixel feature already active; nothing to do."
    return 0
  fi

  # File on disk already (correct content) but pending a framework restart?
  if su -c "grep -q '$GCAM_FEATURE' '$GCAM_SYSCONFIG'" 2>/dev/null; then
    ok "Feature file already written; pending a reboot to register."
    _gcam_reboot_hint
    return 0
  fi

  info "Writing $GCAM_SYSCONFIG (remounting system rw)..."
  # On this device '/' is the mount backing /system (no separate /system entry).
  su -c 'mount -o remount,rw /' 2>/dev/null \
    || su -c 'mount -o remount,rw /system' 2>/dev/null \
    || warn "remount returned non-zero; attempting the write anyway."

  su -c "mkdir -p $(dirname "$GCAM_SYSCONFIG")"
  su -c "cat > '$GCAM_SYSCONFIG'" <<XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<config>
    <feature name="$GCAM_FEATURE" />
</config>
XMLEOF
  su -c "chmod 644 '$GCAM_SYSCONFIG'; chown root:root '$GCAM_SYSCONFIG'; restorecon '$GCAM_SYSCONFIG' 2>/dev/null || true"

  if su -c "grep -q '$GCAM_FEATURE' '$GCAM_SYSCONFIG'" 2>/dev/null; then
    ok "Feature file written."
    _gcam_reboot_hint
  else
    fail "Failed to write $GCAM_SYSCONFIG."
  fi
}

# The feature registers only when the Android framework (re)starts; we never
# reboot from inside install.sh — just tell the user how to activate it.
_gcam_reboot_hint() {
  cat <<'EOF'

        The feature registers only when the Android framework starts. To
        activate it now with a fast framework restart (no full boot):
            su -c 'stop && start'      # ~10-20s; restarts SystemUI + apps
        or reboot normally. Confirm afterward with:
            su -c 'pm list features' | grep PIXEL_2019

        One-time GCam config-merge (separate; survives OTA):
            bash ~/termux-config/assets/gcam/install-gcam-config.sh
EOF
}
