#!/system/bin/sh
#
# OP13 (dodge) camera-HAL freeze fix.
#
# Root cause: OnePlus 13's Qualcomm/Oplus CamX-CHI HAL keeps the HDR+
# multi-frame-merge job MMF_PLUS on the SYNCHRONOUS job list
# (SyncUadThrJobList) in /odm/etc/camera/CameraHWConfiguration.config, and
# disables the sync-wait on almost nothing (DisableSyncJobList =
# Async_Features_Destroy;). On a lifecycle event (capture / lens switch /
# app resume) the merge job's async-create is flushed synchronously and
# orphans with an effectively-infinite wait --
#   ChiX SynchronizeBody() Async_MMF_PLUS_Create: TimedWait 2147483647 ms
# -- so the preview's repeating request never re-establishes and the camera
# hangs (mild = frozen preview, bad = force-kill). Reproduces on stock
# OxygenOS too (see OP13-OCVM known bugs), i.e. it is a vendor-HAL bug, not
# a GCam or LineageOS bug.
#
# Fix: add Async_MMF_PLUS_Create AND Async_RealtimePostProcessor_Create to
# DisableSyncJobList so the HAL does NOT block on their teardown. MMF_PLUS
# (HDR+ merge) orphaned with an infinite TimedWait = the permanent freeze;
# RealtimePostProcessor does a 1000 ms sync flush = a transient lens-switch
# stall (more noticeable with the IRIS/Kepler RAW engines on). HDR+ stays
# fully enabled (unlike the GCam-side workaround of disabling HDR+ merge).
# This is the minimal edit -- the broader OP13-OCVM edit also desyncs the
# preview-create job and made preview hangs *more* frequent on this device.
#
# We regenerate the patch from the CURRENT stock config on every boot, so an
# OTA that rewrites CameraHWConfiguration.config can't silently un-patch us
# or leave a stale copy bind-mounted.

MODDIR=${0%/*}
TARGET=/odm/etc/camera/CameraHWConfiguration.config
PATCHED="$MODDIR/CameraHWConfiguration.config.patched"

[ -f "$TARGET" ] || exit 0

# Already fully patched (this module ran a prior boot, or a future OTA)?
# Keyed on RealtimePostProcessor (the last job we add) so an upgrade from an
# older MMF_PLUS-only version of this module still re-patches.
if grep -q 'DisableSyncJobList[^=]*=.*Async_RealtimePostProcessor_Create' "$TARGET"; then
  exit 0
fi

# Move both synchronous jobs that block the camera on teardown into the
# disable list: Async_MMF_PLUS_Create (HDR+ merge -> infinite TimedWait ->
# permanent freeze) and Async_RealtimePostProcessor_Create (realtime
# post-processor -> 1000 ms TimedWait -> transient lens-switch stall, worse
# with IRIS/Kepler on). We do NOT touch Async_ViewFinderPreview_Create etc.
# (the broad OCVM edit desyncs those and destabilizes preview on this device).
sed 's/^\( *\)DisableSyncJobList = /\1DisableSyncJobList = Async_MMF_PLUS_Create; Async_RealtimePostProcessor_Create; /' \
  "$TARGET" > "$PATCHED" 2>/dev/null

# Only bind if the edit actually changed the file (guards against a future
# config whose line format no longer matches -- in that case we no-op safely).
if cmp -s "$TARGET" "$PATCHED"; then
  rm -f "$PATCHED"
  exit 0
fi

chmod 0644 "$PATCHED"
# Match the target's SELinux label so cameraserver/the provider can read it.
chcon "$(ls -Z "$TARGET" 2>/dev/null | awk '{print $1}')" "$PATCHED" 2>/dev/null
mount -o bind "$PATCHED" "$TARGET"
