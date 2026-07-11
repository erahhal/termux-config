# OnePlus 13 GCam camera-freeze — diagnosis & fix

Investigation notes for the intermittent camera freeze on this phone. Written
2026-07-11. The one-line takeaway: **it's a vendor camera-HAL bug, fixed by a
Magisk overlay of `/odm/etc/camera/CameraHWConfiguration.config`; HDR+ stays on.**

## Environment

- **Device:** OnePlus 13, `CPH2655`, codename **`dodge`**, Snapdragon 8 Elite.
- **ROM:** LineageOS (`ro.build.flavor=lineage_dodge-userdebug`), Android 16. Rooted (Magisk).
- **Camera app:** BSG **MGC 9.7.047**, distributed under the decoy package
  **`com.ss.android.ugc.aweme`** (NOT the `fishfood` package, which is installed
  but unused). Config lives in that app's `shared_prefs`.

## Symptom

Top zoom / lens-selector buttons (0.7 / 1.0 / 3.2) and/or the preview freeze
intermittently. Mild case: preview stalls but buttons still work. Bad case: the
whole camera wedges and only force-killing the app recovers it. Triggers looked
random (lens switch, taking a photo, app-switch-and-return) because they're all
just *camera-session lifecycle events*.

## Root cause (confirmed)

From GCam's own process log + a SIGQUIT Java thread dump + the HAL log, every
freeze shows the same chain:

```
java.lang.IllegalStateException: CameraDevice was already closed
    at CameraDeviceImpl.stopRepeating / createCaptureRequest
CAM_RequestQueue: Unable to invoke setRepeating, requestProcessor is unavailable
ChiX SynchronizeBody() Async_MMF_PLUS_Create: Flush/Sync TimedWait 2147483647 ms   <-- infinite wait
```

The app's **Java main thread is NOT deadlocked** (idle in `Looper.loop`; no
monitor contention). The wedge is in the **native HAL**: the HDR+ multi-frame
merge job (`MMF_PLUS`) is on the **synchronous** job list and gets flushed
synchronously when the session tears down, orphaning it with an effectively
infinite wait (`2147483647 ms` = INT_MAX). The preview's repeating request then
never re-establishes.

Verified in `/odm/etc/camera/CameraHWConfiguration.config` (`[CHIThrMgrOPT]`):

```
SyncUadThrJobList  = ...; JPEG; MMF_PLUS; AnchorSync; ...   <-- merge job is synchronous
DisableSyncJobList = Async_Features_Destroy;                <-- nothing merge-related disabled
```

**This is a vendor-HAL bug, not a GCam or LineageOS bug.** It reproduces on
stock OxygenOS (the OP13 camera mod "OCVM" lists "uwide to main camera switching
in photo modes hangs camera" as a known bug), and LineageOS ships the stock
`dodge` camx/chi blobs + this config essentially unmodified. The scary-looking
`VIULL is not supported`, `Preallocate config failed`, and `DMI_STATUS polling
timed out` lines are all **benign noise** — Aperture (LineageOS's CameraX app)
logs them too and works perfectly, which is also what proved the tele hardware
and HAL are fine and the problem is app/HAL stream-handling, not hardware.

## The fix (what the Magisk module does)

Move the two jobs that block the camera on teardown into `DisableSyncJobList`:

```
DisableSyncJobList = Async_MMF_PLUS_Create; Async_RealtimePostProcessor_Create; Async_Features_Destroy;
```

- **`Async_MMF_PLUS_Create`** — the HDR+ merge job. Its sync flush orphaned with
  `TimedWait 2147483647 ms` (INT_MAX) = the **permanent** freeze / force-kill.
- **`Async_RealtimePostProcessor_Create`** — the realtime post-processor. Its
  sync flush blocks for `TimedWait 1000/1000 ms` per teardown = a **transient**
  lens-switch stall that recovers on its own after ~1s (or several stacked).
  More noticeable with the IRIS/Kepler RAW engines on (more post-processing in
  flight). Found only after the MMF_PLUS fix removed the louder freeze.
- **HDR+ (and IRIS/Kepler) stay fully enabled** — this is the only fix that
  doesn't sacrifice image quality.
- **Minimal edit, on purpose.** The broader OCVM edit also desyncs
  `Async_ViewFinderPreview_Create` and ~8 other jobs; on this device that made
  *preview* hangs MORE frequent. Desyncing only these two fixes both freezes
  without destabilizing preview.

Implemented as `modules/50-gcam-camhal-fix.sh` → deploys the Magisk module in
`assets/gcam/camhal-fix/`. The module's `post-fs-data.sh` regenerates the patch
from the *current* stock config on every boot (OTA-resilient) and bind-mounts
it. `/odm` is a read-only EROFS partition, so bind-mount is the delivery method;
the file's SELinux label (`vendor_configs_file`) is preserved.

Revert: disable the module in Magisk (or `touch .../op13_cam_mmf_fix/disable`)
and reboot. Stock config is also backed up at
`/data/adb/op13_cam_fix_backup/` on the phone this was developed on.

## GCam-side settings (secondary)

Before the HAL root cause was found, several GCam `shared_prefs` changes were
tried as mitigations. They are applied by `install-gcam-config.sh` via
`bsg-gcam-oneplus13-config.xml`. Current state and status:

- `pref_camera_enable_iris=0`, `pref_camera_kepler_enabled_key=0` — reduced but
  did NOT eliminate the freeze. **With the HAL module installed these are likely
  re-enable-able for full quality — untested.** Left off to match the
  confirmed-good state.
- Fully disabling HDR+ merge (`pref_camera_hdr_plus_key=off` + `mn_enabled=false`)
  DID stop the freeze but kills HDR+ — this was the fallback before the HAL fix.
  Not needed once the HAL module is active.
- Dead ends (reverted, no effect on the freeze): `use_physical_raw=false` /
  `raw_key_*=0`; `bento_zsl_disable`; `pref_camera_id_list_key` reorder;
  swapping to the `org.codeaurora.snapcam` package.

## Telephoto (3.2x) note

The 3x periscope works fine in Aperture. In GCam the *lens-toggle button* drives
a direct physical-camera switch (the fragile path); the *zoom pill / pinch* rides
the logical-camera zoom curve (the good path, same as Aperture). `camera.fake_zoom_toggle=true`
makes the toggle buttons use the zoom path. Most of the "tele won't select"
reports turned out to be the same MMF_PLUS freeze, so the HAL fix is the real
answer here too.

## References

- OP13-OCVM (stock-OOS mod, confirms the vendor bug + the `DisableSyncJobList` edit):
  https://github.com/ObyeBoss/OP13-OCVM — `system/odm/etc/camera/CameraHWConfiguration.config`
- Stock dodge blobs: https://github.com/TheMuppets/proprietary_vendor_oneplus_dodge
- BSG GCam ports: https://www.celsoazevedo.com/files/android/google-camera/dev-bsg/
