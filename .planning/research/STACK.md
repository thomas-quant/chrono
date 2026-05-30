# Technology Stack — Milestone: QR/Barcode Scan-to-Dismiss + Reliability Fixes

**Project:** Chrono (FOSS Android alarm app, Flutter)
**Researched:** 2026-05-30
**Scope:** ADDITIVE only. Existing stack (Flutter 3.22.2 / Dart 3.4+, Android-only, minSdk 21 / compileSdk 34, no state-mgmt lib, JSON-file/`get_storage` persistence, alarm firing in background Dart isolate) is treated as fixed and is NOT re-researched.
**Overall confidence:** HIGH for the scanner library choice, F-Droid verdict, and the version/minSdk facts (all source-verified from pub.dev API + the package's git tags). HIGH for the reliability root-cause (confirmed against Chrono's actual manifest).

---

## TL;DR (the decisive calls)

- **Scanner library: `flutter_zxing`.** It is the only mainstream, maintained Flutter scanner that is **F-Droid-clean** — pure native ZXing-C++ via Dart FFI; zero Google Play Services, zero ML Kit, zero proprietary blobs. This is decisive because Chrono ships on F-Droid.
- **Version is NOT free — there is a real fork in the road on minSdk (source-verified):**
  - **flutter_zxing `2.1.0`** → minSdk **21**, needs Dart `>=3.3.3` / Flutter `>=3.3.0`. **Fully compatible with Chrono as-is (Dart 3.4, Flutter 3.22.2, minSdk 21).** ← pick this if you must keep minSdk 21.
  - **flutter_zxing `2.2.0`–`2.2.1`** → **minSdk bumped to 23**, Dart `>=3.3.3` / Flutter `>=3.3.0`. Toolchain-compatible, but **requires raising Chrono's minSdk 21 → 23** (drops Android 5.0/5.1). Pick only if a minSdk bump is acceptable.
  - **flutter_zxing `2.3.0` (latest)** → requires **Dart `>=3.11.0` / Flutter `>=3.41.0`** → **INCOMPATIBLE** with Chrono's Flutter 3.22.2. Do NOT use this milestone.
- **Recommendation: pin `flutter_zxing: 2.1.0`** to preserve Chrono's minSdk 21 with zero collateral changes. (If the team independently decides to raise minSdk to 23, upgrade to `2.2.1`.)
- **Do NOT use `mobile_scanner`, `ai_barcode_scanner`, or `google_mlkit_barcode_scanning`** — all three depend on **Google ML Kit** (proprietary → breaks F-Droid). Independently, **mobile_scanner 7.x also raised minSdk to 23**. Double disqualification.
- **`qr_code_scanner` is dead** (last release ~3 yrs ago; maintainer points to mobile_scanner; breaks on modern Gradle) — do not use.
- **Camera permission: no new dependency.** Reuse existing `permission_handler ^11.3.1` (`Permission.camera`) + one `<uses-permission android:name="android.permission.CAMERA"/>` and `<uses-feature ... required="false"/>` in the manifest.
- **Reliability / boot-isolate crash: no new dependency — it is a code + manifest fix.** Confirmed root cause: Chrono's manifest marks `MainActivity`, the alarm services, and BOTH boot receivers `android:directBootAware="true"` AND registers them for `LOCKED_BOOT_COMPLETED`. So alarm/boot code runs **before first unlock**, then touches `get_storage` (credential-encrypted storage), which is not yet decrypted → crash. Fix = stop running storage work pre-unlock (narrow Direct-Boot surface + guard/defer + non-fatal load), not a storage-library swap.

---

## Recommended Stack (additions only)

### Barcode / QR scanner

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `flutter_zxing` | **`2.1.0`** (keeps minSdk 21) — or `2.2.1` if minSdk→23 is accepted | QR + 1D barcode scan-to-dismiss capture | Only maintained Flutter scanner with **no Google/ML Kit/Play Services dependency** → F-Droid-clean. Native ZXing-C++ via Dart FFI. 2.1.0 keeps minSdk 21 and satisfies Dart 3.4 / Flutter 3.22.2. |

### Camera permission (reuse existing)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `permission_handler` | `^11.3.1` (already a dep) | Runtime CAMERA permission request | Already in `pubspec.yaml`; `Permission.camera` maps to Android CAMERA. No new dep. |

### Reliability fixes

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| *(none)* | — | Boot-isolate / pre-unlock crash | Code + manifest fix, not a library. Existing `get_storage` stays. See reliability section. |

---

## Detailed scanner comparison

### flutter_zxing version compatibility (SOURCE-VERIFIED — pub.dev API + git tags)

| flutter_zxing | minSdk (android/build.gradle) | Dart SDK | Flutter | Compatible with Chrono (Dart 3.4 / Flutter 3.22.2 / minSdk 21)? |
|---------------|-------------------------------|----------|---------|----------------------------------------------------------------|
| 2.0.0 – 2.0.2 | **21** | `>=3.3.3` | `>=3.3.0` | YES (minSdk 21) — older zxing-cpp |
| **2.1.0** | **21** | `>=3.3.3` | `>=3.3.0` | **YES — recommended (keeps minSdk 21)** |
| 2.2.0 | **23** | `>=3.3.3` | `>=3.3.0` | Toolchain yes, but **forces minSdk 23** |
| 2.2.1 | **23** | `>=3.3.3` | `>=3.3.0` | Toolchain yes, but **forces minSdk 23** (best if 23 OK) |
| 2.3.0 (latest) | 23 | **`>=3.11.0`** | **`>=3.41.0`** | **NO — needs newer Flutter/Dart** |

This is the crux: the newest flutter_zxing is gated behind a Flutter/Dart upgrade Chrono hasn't taken, and the minSdk-21-preserving line ends at **2.1.0**. (HIGH confidence — read directly from the pub.dev package API `environment` blocks and from each git tag's `android/build.gradle`.)

### Candidate matrix (all libraries)

| Library | Latest | Maintained? | Engine (Android) | F-Droid clean? | minSdk vs Chrono=21 | Dart/Flutter fit | Formats (QR/EAN/UPC/Code128) | Verdict |
|---------|--------|-------------|------------------|----------------|---------------------|------------------|------------------------------|---------|
| **flutter_zxing** | 2.3.0 | YES (main updated Oct 2025) | Native ZXing C++ (FFI) | **YES — clean** | **2.1.0 = 21 ✅; 2.2.x = 23; 2.3.0 = 23** | **2.1.0/2.2.x ✅ (Dart 3.3.3/Flutter 3.3); 2.3.0 ❌ (Dart 3.11)** | All four + Data Matrix, Aztec, PDF417, ITF, Codabar, Code39/93, GS1 DataBar | ✅ **RECOMMENDED @ 2.1.0** |
| mobile_scanner | 7.2.0 | YES (very active) | Google ML Kit | **NO — proprietary** | **23** | compileSdk 34 ok | QR + all common | ❌ Breaks F-Droid AND minSdk 21 |
| ai_barcode_scanner | 7.1.0 | YES | Wraps mobile_scanner → ML Kit | **NO — inherits ML Kit** | inherits 23 | via mobile_scanner | same as mobile_scanner | ❌ Breaks F-Droid AND minSdk 21 |
| google_mlkit_barcode_scanning | 0.14.2 | YES (official) | Google ML Kit | **NO — proprietary** | 21 | targetSdk 35 | QR + common | ❌ Breaks F-Droid |
| qr_code_scanner | 1.0.1 (~3 yrs) | **NO — dead; maintainer points to mobile_scanner** | Android ZXing + iOS MTBBarcodeScanner (both unmaintained) | was clean-ish | n/a | breaks on AGP 8 | QR-centric | ❌ Dead, do not use |

**Confidence: HIGH** on F-Droid verdicts, maintenance status, version numbers, minSdk, and Dart/Flutter constraints (all verified from pub.dev API / GitHub tags, not training data).

### Why each non-recommended option is out

**mobile_scanner (the popular default) — REJECTED, on two independent grounds.**
1. **F-Droid:** On Android it is built entirely on **Google ML Kit Barcode Scanning** (closed-source binary). There is **no ZXing/FOSS build flavor** — the "bundled vs unbundled" toggle (`dev.steenbakker.mobile_scanner.useUnbundled=true`) only changes whether the ML Kit *model* ships in-APK (3-10 MB) or is fetched via **Google Play Services** (~600 KB, adds a hard Play-Services runtime dependency). Both link proprietary ML Kit. F-Droid explicitly does not accept mobile_scanner because of ML Kit (triggers the `NonFreeDep` anti-feature; the reproducible-from-source pipeline won't pull the proprietary Maven artifact). The open "add a ZXing backend" request (juliansteenbakker/mobile_scanner #1394) is **not implemented**.
2. **minSdk:** mobile_scanner **7.x bumped minSdk 21 → 23**, so even ignoring F-Droid it would force a minSdk bump. Otherwise an excellent library (CameraX, `MobileScannerController`, torch) — but disqualified for Chrono.

**ai_barcode_scanner — REJECTED.** Thin UI wrapper around mobile_scanner (^7.1.x); inherits both the ML Kit F-Droid blocker and minSdk-23 floor.

**google_mlkit_barcode_scanning — REJECTED.** Raw ML Kit binding; proprietary by definition; same F-Droid blocker, no camera/UI convenience.

**qr_code_scanner — REJECTED (dead).** Last meaningful release ~3 years ago; maintainer built mobile_scanner as its successor; underlying engines unmaintained; breaks against AGP 8 / namespaces in a Flutter 3.22.x toolchain. flutter_zxing is the maintained successor.

### Why flutter_zxing is the right choice

1. **F-Droid-clean by construction (HIGH).** Compiles upstream ZXing-C++ (Apache-2.0) and talks to it via Dart FFI. No Google Maven artifact, no Play Services, no ML Kit, no proprietary blob — exactly what F-Droid requires. Real FOSS reference app exists (**ZXScanner**, same author). The QRAlarm FOSS app on F-Droid proves the "scan-a-code-to-dismiss-alarm on F-Droid" pattern is viable.
2. **Format coverage exceeds the requirement (HIGH).** Milestone needs QR + EAN/UPC/Code128; flutter_zxing supports QR, EAN-8/13, UPC-A/E, Code39/93/128, ITF, Codabar, Data Matrix, Aztec, PDF417, GS1 DataBar. Restrict enabled formats at scan time for faster, more reliable decode (matches the "register any physical product code" requirement).
3. **Can keep minSdk 21 (HIGH).** Version **2.1.0** keeps minSdk 21 (verified from its `android/build.gradle`), unlike mobile_scanner. No minSdk bump needed if you pin 2.1.0.
4. **Maintained (MEDIUM-HIGH).** Active repo (main updated Oct 2025); note ZXing upstream is "maintenance mode," so be prepared to carry the occasional fix — acceptable for a stable, well-scoped scan use case.
5. **Ships its own camera widget** (`ReaderWidget`: camera view, scan frame, torch, zoom) so you do NOT also need the `camera` plugin — one permission surface, one lifecycle to manage on the dismiss screen.

### flutter_zxing — integration notes & costs (read before committing)

- **CRITICAL version decision (source-verified):**
  - To keep **minSdk 21**: pin **`flutter_zxing: 2.1.0`**. (Last line on minSdk 21; satisfies Dart 3.4 / Flutter 3.22.2.)
  - If raising **minSdk to 23** is acceptable: use **`2.2.1`** (newer zxing-cpp, 16KB page-size support, still Dart 3.3.3 / Flutter 3.3 floor).
  - **Never** `^2.x` or `2.3.0`: `2.3.0` requires **Dart `>=3.11` / Flutter `>=3.41`**, which Chrono cannot satisfy without a Flutter upgrade out of scope for this milestone. Use an exact pin.
- **Native build requirement: CMake + NDK.** FFI to C++ means the Android build compiles native code via CMake/NDK. Main cost vs a pure-Dart wrapper. Flutter provisions the NDK (`ndkVersion flutter.ndkVersion` is already in `android/app/build.gradle`); pin a specific `ndkVersion` only if the default fails the ZXing CMake build. First clean build is slower; APK gains per-ABI native `.so`. Chrono already builds `--split-per-abi` for release and F-Droid builds per-ABI, so the size hit is contained. (HIGH this is required; MEDIUM on exact NDK version — resolve in the build phase.)
- **compileSdk 34 / Gradle 7.6.4 / Kotlin 1.8 / Java 17:** compatible. The native build is the only realistic friction point. (MEDIUM-HIGH — verify on first build.)
- **Camera lifecycle:** `ReaderWidget` manages the camera internally with a result callback, running on the **alarm-dismiss UI screen (`alarm_notification_screen.dart`, main isolate / foreground Activity)** — NOT the firing background isolate. No isolate/camera conflict: alarm fires in the background isolate; the dismiss screen is normal foreground UI where camera APIs are valid (matches PROJECT.md constraint). Release the camera on screen dispose and on app-background (Chrono already has `flutter_fgbg` to detect FG/BG); re-acquire on resume. (HIGH on architecture; dispose/resume is standard plugin hygiene.)
- **Note:** flutter_zxing 2.3.0 fixed `CameraController` disposal / `stopImageStream()` issues and improved multi-isolate handling. Since you're pinned below 2.3.0, watch for camera-disposal edge cases and apply defensive dispose handling on the dismiss screen.

### Installation

```bash
# Keep minSdk 21 (recommended):
flutter pub add flutter_zxing:2.1.0
# OR, if minSdk -> 23 is accepted:
# flutter pub add flutter_zxing:2.2.1
# permission_handler already present (^11.3.1) — no action
```

`pubspec.yaml` (pin exactly — a caret could resolve to the Dart-3.11 release):
```yaml
dependencies:
  flutter_zxing: 2.1.0   # minSdk 21, Dart >=3.3.3 / Flutter >=3.3.0. Do NOT use ^ (2.3.0 needs Dart 3.11).
```

`android/app/build.gradle` (only if the NDK default mismatches the native build):
```gradle
android {
    // ndkVersion "<pin if flutter.ndkVersion default fails the ZXing CMake build>"
    defaultConfig { minSdk 21 }   // satisfied by 2.1.0; would need 23 for 2.2.x
}
```

---

## Camera permission (Android) — no new dependency

**Manifest** (`android/app/src/main/AndroidManifest.xml`) — add (Chrono currently has NO camera permission/feature lines, confirmed):
```xml
<uses-permission android:name="android.permission.CAMERA" />
<!-- Camera optional for the app overall; only QR-dismiss alarms need it -->
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
```
Use `required="false"` so the app still installs on camera-less devices (only QR-dismiss alarms unavailable there) and so F-Droid metadata doesn't over-claim hardware.

**Runtime request flow** (existing `permission_handler ^11.3.1`):
- CAMERA is a runtime (dangerous) permission on API 23+. On Chrono's API 21-22 floor it's install-time granted and the runtime prompt is a no-op — `permission_handler` handles both transparently.
- **Where to request:** during **alarm setup**, when the user picks the "scan to dismiss" task and registers a specific code — NOT at alarm-fire time. Never block alarm dismissal on a permission dialog.
  ```dart
  final status = await Permission.camera.request();
  if (status.isGranted) { /* let user register a code */ }
  else if (status.isPermanentlyDenied) { openAppSettings(); }
  ```
- **Confidence: HIGH.** `permission_handler` `Permission.camera` ↔ Android CAMERA is stable and documented; already a project dependency.

**Design flag (safety-critical, ties to the milestone's "escape hatch ON by default"):** define the fail-safe when camera permission is revoked / hardware fails *at fire time*. PROJECT.md already requires an escape-hatch fallback after a threshold of failed attempts/elapsed time — make sure that path also covers "camera unavailable," so a scan-to-dismiss alarm can never become un-dismissable. UX/safety requirement, not a dependency.

---

## Reliability fixes — storage before unlock / boot isolate

### Root cause — CONFIRMED against the actual manifest (HIGH confidence)
Not speculative. `android/app/src/main/AndroidManifest.xml` currently declares `android:directBootAware="true"` on:
- `.MainActivity` (line 38)
- `AlarmService` and `AlarmBroadcastReceiver` (android_alarm_manager_plus)
- `RebootBroadcastReceiver`, `BootHandlerService`, `BootBroadcastReceiver` (flutter_boot_receiver)

and registers the boot receivers for **`LOCKED_BOOT_COMPLETED`** (lines 105, 137) alongside `BOOT_COMPLETED`.

`LOCKED_BOOT_COMPLETED` is delivered **before first unlock**, in Direct Boot mode, and `directBootAware="true"` is what lets these components run then. At that point **credential-encrypted (CE) storage is not yet decrypted**. Chrono's boot/alarm code then reads `get_storage` (CE storage by default) → throws `SharedPreferences/credential-encrypted storage not available until user is unlocked` (a documented Android failure) → boot crash + half-written state → next launch hangs on splash. Matches PROJECT.md's reliability epic (#442, #420, #448, #489, #498, #516, #514, #483, #289) exactly.

### Android storage facts (HIGH — official Android docs)
- **Credential-encrypted (CE) storage** — default; available **only after first unlock**. Files, default `SharedPreferences`, normal app data dir live here.
- **Device-encrypted / device-protected (DE) storage** — available **immediately at boot, before unlock**, via `Context.createDeviceProtectedStorageContext()`. Only `directBootAware` components run before unlock.
- `LOCKED_BOOT_COMPLETED` = pre-unlock (Direct Boot). `BOOT_COMPLETED` = post-unlock. `ACTION_USER_UNLOCKED` / `UserManager.isUserUnlocked()` tell you when CE storage is safe.

### Storage-library behavior (MEDIUM-HIGH)
- **`get_storage`** (Chrono's settings store) writes a JSON file under the app's normal **CE** data dir → **not readable before first unlock**. No DE fallback.
- **`shared_preferences`** → Android `SharedPreferences` in CE storage → same restriction (relevant because the bug reports describe "encrypted SharedPreferences"; both share the CE limitation).
- Neither plugin exposes a device-protected mode out of the box.

### Recommendation: code + manifest fix, NO new dependency (HIGH for diagnosis; HIGH this needs no new dep)
Minimal, correct fix — four moves, zero new packages:

1. **Stop doing storage-dependent work before unlock.** Simplest durable fix: don't let the alarm-reschedule path run on the pre-unlock `LOCKED_BOOT_COMPLETED` / Direct-Boot path; do rescheduling on `BOOT_COMPLETED` (post-unlock). Practically: reconsider the blanket `directBootAware="true"` + `LOCKED_BOOT_COMPLETED` registration on Chrono's own boot receiver(s). **Caveat:** some of these manifest lines come from the **forked plugins'** manifests (android_alarm_manager_plus, flutter_boot_receiver), not Chrono's own code — verify which are Chrono-owned vs plugin-supplied (and whether the plugin truly needs pre-unlock execution) before editing.
2. **Guard every early storage access.** Before reading `get_storage` in any boot/isolate path, check `UserManager.isUserUnlocked()` (platform channel) OR wrap in try/catch and **defer**: retry once `ACTION_USER_UNLOCKED` fires (or on next app foreground). The isolate must **fail soft, not crash.** Directly satisfies PROJECT.md's "guard storage until user-unlocked."
3. **Make load non-fatal.** Null-guard before `json.decode`; treat partial/corrupt state as recoverable (PROJECT.md / CONCERNS.md flag missing null-guards and silent GetStorage fallbacks). This fixes the "next launch hangs on splash" half.
4. **Only if alarms genuinely must ring before first unlock** (e.g., overnight reboot, ring before owner ever unlocks) do you need **DE/device-protected storage**: store the minimal "next alarm schedule" in DE storage via a small platform channel calling `createDeviceProtectedStorageContext()`, keep those receivers `directBootAware`, and read only DE data pre-unlock. **This is a feature decision, not the bug fix** — flag it for the roadmap; don't assume it. For most alarm apps, firing after unlock (or relying on OS exact-alarm delivery, which itself wakes the device) is acceptable.

**Verdict:** Fixing the crash needs **no new dependency** — (a) narrow the Direct-Boot surface in the manifest, (b) guard/defer CE-storage reads until unlocked, (c) make load non-fatal. Device-protected storage is an optional, heavier enhancement, scoped separately only if pre-unlock firing is required.

---

## Alternatives Considered (summary)

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Scanner | **flutter_zxing 2.1.0** | mobile_scanner 7.2.0 | ML Kit proprietary → breaks F-Droid (decisive); also minSdk 23 > Chrono's 21 |
| Scanner | flutter_zxing 2.1.0 | ai_barcode_scanner | Wraps mobile_scanner → inherits ML Kit + minSdk 23 |
| Scanner | flutter_zxing 2.1.0 | google_mlkit_barcode_scanning | Proprietary ML Kit by definition |
| Scanner | flutter_zxing 2.1.0 | qr_code_scanner | Discontinued; breaks on modern Gradle |
| Scanner version | flutter_zxing **2.1.0** | 2.2.1 | 2.2.x forces minSdk 21→23; choose 2.2.1 only if a minSdk bump is accepted |
| Scanner version | flutter_zxing **2.1.0 / 2.2.1** | 2.3.0 | 2.3.0 needs Dart ≥3.11 / Flutter ≥3.41; Chrono is Dart 3.4 / Flutter 3.22.2 |
| Camera perm | permission_handler (existing) | new perm lib / `camera` plugin | Already a dep; ReaderWidget bundles camera; no reason to add |
| Pre-unlock storage | code guard + defer + narrow Direct-Boot surface | device-protected storage channel | Heavier; only if pre-unlock firing is required |
| Pre-unlock storage | code guard | swap get_storage → other plugin | No KV plugin fixes CE-before-unlock; it's a code/manifest issue |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| mobile_scanner / ai_barcode_scanner / google_mlkit_barcode_scanning | Google ML Kit = proprietary → F-Droid rejects (NonFreeDep); mobile_scanner 7.x also forces minSdk 23 | flutter_zxing 2.1.0 |
| flutter_zxing **2.3.0** (and any `^` range that resolves it) | Requires Dart ≥3.11 / Flutter ≥3.41; incompatible with Flutter 3.22.2 | flutter_zxing **2.1.0** (or 2.2.1 if minSdk→23) |
| flutter_zxing 2.2.x **while keeping minSdk 21** | 2.2.0 bumped minSdk to 23 | flutter_zxing **2.1.0** |
| qr_code_scanner | Dead (~3 yrs), unmaintained engines, breaks on AGP 8 | flutter_zxing 2.1.0 |
| Adding `camera` plugin separately | flutter_zxing's `ReaderWidget` already provides camera + scan UI | flutter_zxing `ReaderWidget` |
| New storage dependency for the boot crash | No KV plugin makes CE storage readable pre-unlock | Code guard (`isUserUnlocked` / defer) + narrow Direct-Boot manifest surface |

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| flutter_zxing **2.1.0** | Dart 3.4 / Flutter 3.22.2, **minSdk 21**, compileSdk 34 | ✅ Recommended. Requires CMake/NDK native build (`ndkVersion flutter.ndkVersion` already set). |
| flutter_zxing 2.2.1 | Dart 3.4 / Flutter 3.22.2, **minSdk 23**, compileSdk 34 | Toolchain OK, but raises minSdk floor to 23. |
| flutter_zxing 2.3.0 | Dart ≥3.11 / Flutter ≥3.41 ONLY | ❌ Incompatible with current toolchain. |
| permission_handler ^11.3.1 | already resolved in pubspec.lock | `Permission.camera` ready; no version change. |
| mobile_scanner 7.x | minSdk 23, compileSdk 34 | ❌ minSdk floor too high + ML Kit. |

---

## Risks / flags for the roadmap

1. **minSdk decision (highest-leverage call).** To keep **minSdk 21**, pin flutter_zxing **2.1.0**. If the team would rather take newer zxing-cpp / 16KB page-size support (Android 15 requirement on some devices), accept **minSdk 23** and use 2.2.1 — but that drops Android 5.0/5.1 users. Make this an explicit product decision. (HIGH — affects pin + manifest + audience.)
2. **Version pin discipline.** Use an **exact** pin (`flutter_zxing: 2.1.0`), never `^`, to avoid resolving the Dart-3.11 2.3.0 release. (HIGH — easy to get wrong; a `flutter pub upgrade` could silently break the build.)
3. **Native build (NDK/CMake).** First build slower; per-ABI `.so` added. Mitigated by Chrono's existing `--split-per-abi` release build and F-Droid's per-ABI builds. Budget a small spike to green the native build in CI (Java 17 / Gradle 7.6.4). (HIGH — real but contained.)
4. **Camera disposal on the pre-2.3.0 line.** 2.3.0 fixed `CameraController` disposal / `stopImageStream()` issues you won't get on 2.1.0/2.2.x. Add defensive dispose/resume handling (leverage existing `flutter_fgbg`). (MEDIUM.)
5. **Scan-to-dismiss fail-safe.** Define behavior when camera permission/hardware is unavailable at fire time; fold into PROJECT.md's mandatory escape hatch. Safety-critical. (HIGH.)
6. **Direct-Boot surface ownership.** Some `directBootAware`/`LOCKED_BOOT_COMPLETED` lines come from forked plugin manifests, not Chrono's own code. Confirm ownership and necessity before editing. (MEDIUM — needs code/manifest tracing in the fix phase.)
7. **Pre-unlock firing in scope?** Explicit product call: must alarms ring before first unlock after reboot? Yes → DE/device-protected storage work; no → pure code guard. (MEDIUM — product decision.)

---

## Sources

- **pub.dev package API (`/api/packages/flutter_zxing`)** — per-version `environment` blocks: 2.0.0–2.2.1 = `sdk >=3.3.3 / flutter >=3.3.0`; 2.3.0 = `sdk >=3.11.0 / flutter >=3.41.0`; latest = 2.3.0 (HIGH, authoritative)
- **flutter_zxing git tags `android/build.gradle`** (raw.githubusercontent.com, tags v2.0.0/v2.1.0/v2.2.0/v2.2.1/v2.3.0) — minSdk: 21 through 2.1.0, **23 from 2.2.0 onward** (HIGH, authoritative)
- github.com/khoren93/flutter_zxing (+ CHANGELOG) — active maintenance (main updated Oct 2025); 2.2.0 "16KB page size + minSdk 23"; 2.3.0 SPM migration + camera-disposal fixes; CMake/NDK build; ReaderWidget; ZXScanner reference app (HIGH)
- pub.dev/packages/mobile_scanner + GitHub README/issues — v7.2.0, ML Kit engine, bundled/unbundled = model location only (unbundled needs Play Services), no ZXing flavor; issue #1394 (ZXing backend) unimplemented (HIGH)
- mobile_scanner 7.0.0 notes / issue #922 — minSdk raised 21→23, compileSdk 34 required (HIGH)
- pub.dev/packages/ai_barcode_scanner — v7.1.0, wraps mobile_scanner ^7.1.x (HIGH)
- pub.dev/packages/google_mlkit_barcode_scanning — v0.14.2, proprietary ML Kit, minSdk 21 / targetSdk 35 (HIGH)
- pub.dev/packages/qr_code_scanner — v1.0.1, maintenance-only, maintainer points to mobile_scanner; engines unmaintained (HIGH)
- F-Droid Anti-Features (NonFreeDep) + forum/issue threads — ML Kit apps not accepted; mobile_scanner excluded for ML Kit (HIGH for policy; MEDIUM-HIGH for the specific mobile_scanner exclusion)
- developer.android.com/privacy-and-security/direct-boot — CE vs DE storage, availability pre/post first unlock, directBootAware, createDeviceProtectedStorageContext, isUserUnlocked (HIGH)
- orhanobut/hawk issue #224 — real-world "SharedPreferences in credential encrypted storage not available until user unlocked" on LOCKED_BOOT_COMPLETED (MEDIUM-HIGH corroboration)
- pub.dev/packages/permission_handler — Permission.camera ↔ Android CAMERA (HIGH)
- Chrono repo: `android/app/build.gradle` (minSdk 21, compileSdk 34, ndkVersion flutter.ndkVersion), `android/app/src/main/AndroidManifest.xml` (directBootAware + LOCKED_BOOT_COMPLETED on MainActivity/alarm/boot components; no camera permission present), `pubspec.yaml` (Dart 3.4, permission_handler ^11.3.1, get_storage ^2.1.1), `.planning/codebase/STACK.md`, `.planning/PROJECT.md`, `.planning/codebase/INTEGRATIONS.md` (HIGH, from repo)

---
*Stack research for: Chrono QR/barcode scan-to-dismiss + reliability milestone*
*Researched: 2026-05-30*
