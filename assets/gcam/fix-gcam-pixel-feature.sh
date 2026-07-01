#!/data/data/com.termux/files/usr/bin/env bash
#
# fix-gcam-pixel-feature.sh  (Termux / on-device edition)
#
# Adds the com.google.android.feature.PIXEL_2019_EXPERIENCE system feature by
# writing /system/etc/sysconfig/pixel_experience_2019.xml. BSG GCam mods crash
# on the STILL_IMAGE_CAMERA intent (the power-button double-tap camera
# shortcut) on non-Pixel devices unless this flag is present -- their
# CameraImageActivity skips device-config init when the feature is absent and
# then hits a NullPointerException.
#
# The file lives in /system, so every OTA system update wipes it and it must
# be re-run afterward (then reboot). THIS is the file that needs reapplying
# after each update.
#
# On-device port of the original ADB script: no adb, no laptop. Root is taken
# directly on the phone via Termux `su` (Magisk). Run it as:
#     bash ~/gcam/fix-gcam-pixel-feature.sh
#
# Requirements:
#   - Termux with root (su) granted to Termux in your superuser app
#   - A reboot after running for the feature to register

set -euo pipefail

FEATURE_NAME="com.google.android.feature.PIXEL_2019_EXPERIENCE"
SYSCONFIG_DIR="/system/etc/sysconfig"
SYSCONFIG_PATH="$SYSCONFIG_DIR/pixel_experience_2019.xml"

echo "=== GCam Pixel Feature Fix (Termux) ==="
echo ""

# Check root is available via su
if ! su -c 'id' 2>/dev/null | grep -q 'uid=0'; then
    echo "ERROR: root not available via 'su'."
    echo "Grant Termux root access in your Magisk / superuser app, then re-run."
    exit 1
fi

echo "Device: $(su -c 'getprop ro.product.model' | tr -d '\r')"
echo ""

# Already present? (registers only after a reboot, so this is the post-reboot check)
if su -c 'pm list features' 2>/dev/null | grep -q "$FEATURE_NAME"; then
    echo "Feature '$FEATURE_NAME' is already active. Nothing to do."
    exit 0
fi

# Remount /system read-write. On this device '/' is the mount that backs
# /system (there is no separate /system entry in /proc/mounts).
echo "Remounting system read-write..."
su -c 'mount -o remount,rw /' 2>/dev/null \
    || su -c 'mount -o remount,rw /system' 2>/dev/null \
    || echo "  (remount returned non-zero; continuing -- write may still succeed)"

# Write the feature config as root. Redirecting inside the su command string
# makes root's shell open the file, so it can write under /system.
echo "Writing feature config to $SYSCONFIG_PATH ..."
su -c "mkdir -p '$SYSCONFIG_DIR'"
su -c "cat > '$SYSCONFIG_PATH'" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<config>
    <feature name="com.google.android.feature.PIXEL_2019_EXPERIENCE" />
</config>
XMLEOF

# Normalise perms + SELinux label to the standard system-file context.
su -c "chmod 644 '$SYSCONFIG_PATH'; chown root:root '$SYSCONFIG_PATH'; restorecon '$SYSCONFIG_PATH' 2>/dev/null || true"

# Verify on disk
if su -c "cat '$SYSCONFIG_PATH'" 2>/dev/null | grep -q "$FEATURE_NAME"; then
    echo "Feature config written successfully:"
    su -c "ls -Z '$SYSCONFIG_PATH'"
else
    echo "ERROR: failed to write feature config." >&2
    exit 1
fi

echo ""
echo "NOTE: the feature is only read when the Android framework starts, so it"
echo "needs at least a framework restart to register. Options:"
echo "  [s] soft reboot  -- restart the framework only (stop && start): faster"
echo "                      (~10-20s), restarts SystemUI and all apps, no full boot."
echo "  [f] full reboot  -- normal reboot."
echo "  [n] nothing now  -- apply later."
read -rp "Choose (s/f/N): " answer
case "$answer" in
    [Ss])
        echo "Soft-rebooting the framework..."
        # Restarts Zygote -> system_server, which re-reads /system/etc/sysconfig.
        su -c 'stop && start' || su -c 'setprop ctl.restart zygote'
        echo "Framework is restarting. Give it ~20s, then confirm with:"
        echo "    su -c 'pm list features' | grep PIXEL_2019"
        ;;
    [Ff])
        echo "Rebooting..."
        su -c 'reboot'
        ;;
    *)
        echo "Nothing done. Apply later with a soft reboot:"
        echo "    su -c 'stop && start'"
        echo "or a full reboot. Afterwards confirm with:"
        echo "    su -c 'pm list features' | grep PIXEL_2019"
        echo "Then the power-button double-tap should launch GCam."
        ;;
esac
