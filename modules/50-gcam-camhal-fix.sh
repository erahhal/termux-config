#!/data/data/com.termux/files/usr/bin/bash
# Module: GCam OnePlus 13 camera-HAL freeze fix (Magisk module).
#
# Installs a small Magisk module that patches the vendor camera HAL config
# (/odm/etc/camera/CameraHWConfiguration.config) so the HDR+ multi-frame-merge
# job MMF_PLUS is no longer flushed synchronously on teardown. That sync-flush
# is what orphaned the merge with an infinite TimedWait and froze the camera
# preview / lens switching. See assets/gcam/CAMERA-FREEZE-FINDINGS.md for the
# full diagnosis.
#
# The Magisk module regenerates its patch from the CURRENT stock config at
# each boot, so it survives OTA updates. This termux-config module just deploys
# the module files; the fix activates on the next reboot. Idempotent.

GCAM_HAL_MODID="op13_cam_mmf_fix"
GCAM_HAL_MOD="/data/adb/modules/$GCAM_HAL_MODID"
GCAM_HAL_CFG="/odm/etc/camera/CameraHWConfiguration.config"

run_gcam_camhal_fix() {
  step "GCam OP13 camera-HAL freeze fix (Magisk module)"

  if ! su -c 'id' 2>/dev/null | grep -q 'uid=0'; then
    warn "root (su) not available; skipping camera-HAL fix."
    warn "Grant Termux root in Magisk, then re-run: ./install.sh gcam-camhal-fix"
    return 0
  fi

  # The edit is specific to the OnePlus 13 (codename 'dodge') camera config.
  local flavor
  flavor=$(su -c 'getprop ro.build.flavor' 2>/dev/null | tr -d '\r')
  if ! printf '%s' "$flavor" | grep -qi 'dodge'; then
    warn "Device flavor '$flavor' is not OnePlus 13 (dodge)."
    warn "This camera-HAL patch is device-specific; skipping to avoid breaking your camera."
    return 0
  fi

  local src="$SCRIPT_DIR/assets/gcam/camhal-fix"
  [ -f "$src/module.prop" ] && [ -f "$src/post-fs-data.sh" ] \
    || fail "camhal-fix assets missing under $src"

  info "Installing Magisk module '$GCAM_HAL_MODID'..."
  su -c "mkdir -p $GCAM_HAL_MOD"
  su -c "cp '$src/module.prop' '$GCAM_HAL_MOD/module.prop'"
  su -c "cp '$src/post-fs-data.sh' '$GCAM_HAL_MOD/post-fs-data.sh'"
  su -c "chmod 0644 '$GCAM_HAL_MOD/module.prop'; chmod 0755 '$GCAM_HAL_MOD/post-fs-data.sh'"
  # Ensure the module is enabled (no leftover disable flag from a prior toggle).
  su -c "rm -f '$GCAM_HAL_MOD/disable' '$GCAM_HAL_MOD/remove'"

  # Is the fix already live (patch present in the running config)?
  if su -c "grep -q 'DisableSyncJobList[^=]*=.*Async_MMF_PLUS_Create' '$GCAM_HAL_CFG'" 2>/dev/null; then
    ok "Camera-HAL fix already active (config is patched)."
  else
    ok "Module deployed; it activates on the next boot."
    cat <<'EOF'

        Reboot to apply, then confirm with:
            su -c "grep DisableSyncJobList /odm/etc/camera/CameraHWConfiguration.config"
        You should see 'Async_MMF_PLUS_Create;' in that line.

        To revert: disable the module in the Magisk app (or
        `su -c 'touch /data/adb/modules/op13_cam_mmf_fix/disable'`) and reboot.
EOF
  fi
}
