---
phase: 04-qr-barcode-scan-to-dismiss-task
plan: 01
subsystem: build-enablement
tags: [build, gradle, manifest, ci, f-droid, flutter_zxing, scanner]
requires: []
provides:
  - "flutter_zxing 2.2.1 exact pin (BUILD-02)"
  - "minSdkVersion 23 (BUILD-01) — gates the native ZXing build for all scan-task plans"
  - "CAMERA permission + camera/autofocus/flash uses-feature required=false (SCAN-08 manifest half)"
  - "BUILD-02 zero-ML-Kit CI gate on the prod (F-Droid) release classpath"
affects:
  - "all downstream Phase-4 plans (02 spike, 03 seams, 04 task type, 05 registration card, 06 ring widget) — they cannot compile/run without the pin + minSdk bump + CAMERA permission"
tech-stack:
  added:
    - "flutter_zxing 2.2.1 (exact pin) — native ZXing barcode/QR scanner via Dart FFI; only F-Droid-clean Flutter scanner"
  patterns:
    - "git-fork/exact-pin dependency style (mirrors existing aamp/foreground_task pins)"
    - "blocking CI job mirroring the existing test-apk.yml Java 17 + Flutter 3.22.2 setup"
key-files:
  created: []
  modified:
    - "pubspec.yaml — flutter_zxing 2.2.1 exact pin"
    - "android/app/build.gradle — minSdkVersion 21 -> 23"
    - "android/app/src/main/AndroidManifest.xml — CAMERA + 3 uses-feature required=false"
    - ".github/workflows/test-apk.yml — new dependency-graph BUILD-02 gate job"
decisions:
  - "Exact pin 2.2.1 (no caret): a caret ^2.2.0 would let pub resolve into 2.3.0, which requires Flutter >=3.41 and breaks Chrono's 3.22.2."
  - "ndkVersion left as flutter.ndkVersion (NOT preemptively set to 27.0.12077973) — align only if the CI native build complains about an NDK mismatch (contingency, currently unused)."
  - "BUILD-02 gate is a separate blocking job (not continue-on-error), targeting prodReleaseRuntimeClasspath — the F-Droid-shipped artifact."
metrics:
  duration: "~6 min"
  completed: "2026-06-06"
  tasks: 3
  files: 4
---

# Phase 04 Plan 01: QR/Barcode Build Enablement Gate Summary

Landed the foundation build gate every other scan-task plan depends on: pinned `flutter_zxing: 2.2.1` (exact, no caret), bumped `minSdkVersion` 21 → 23, declared `CAMERA` + camera/autofocus/flash `uses-feature required="false"` in the manifest, and added a blocking CI job that proves the prod (F-Droid) release Gradle graph contains zero `mlkit`/`gms`/`play-services`. Pure config + CI wiring — no Dart production code.

## What Was Built

| Task | Requirement | Change | Commit |
|------|-------------|--------|--------|
| 1 | BUILD-01, BUILD-02 | `flutter_zxing: 2.2.1` exact pin in `pubspec.yaml`; `minSdkVersion 21 → 23` in `android/app/build.gradle` | `afea34a` |
| 2 | SCAN-08 (manifest half) | `android.permission.CAMERA` + `uses-feature` camera/autofocus/flash, all `required="false"`, in `AndroidManifest.xml` | `0fd17c1` |
| 3 | BUILD-02 (exit criterion) | New blocking `dependency-graph` job in `test-apk.yml` greps `prodReleaseRuntimeClasspath` for `mlkit\|play-services\|gms` and `exit 1`s on any match | `bf18b1a` |

## Why These Choices

- **Exact pin `2.2.1`, not `^2.2.0`:** pub.dev confirms `2.2.1` declares `flutter: >=3.3.0` (compatible with Chrono's 3.22.2) while `2.3.0` declares `flutter: >=3.41.0` (incompatible). A caret would silently upgrade into `2.3.0` and break the build. The pin carries an inline comment to that effect.
- **minSdk 23 driver:** `flutter_zxing 2.2.1`'s own `android/build.gradle` hard-codes `minSdkVersion 23`; the app's minSdk must meet it. This is the real driver of BUILD-01 (Android 5.0/5.1 was already an accepted drop — PROJECT.md Out of Scope).
- **`required="false"` on every camera feature:** keeps the Play listing from being camera-gated — devices without a camera can still install; the default-on escape hatch (later plans) covers them. Matches the SCAN-08 verbatim shape.
- **BUILD-02 as a separate hard job:** targets `prodReleaseRuntimeClasspath` specifically (the F-Droid-shipped artifact), and is NOT `continue-on-error` (unlike the informational analyze/test steps), because BUILD-02 is a hard exit criterion. No emulator/integration_test job was added (RESEARCH explicitly recommends against it — a secure-keyguard + real-camera condition is not reproducible in an emulator job).

## NDK-Alignment Contingency (unused, recorded per plan)

`ndkVersion flutter.ndkVersion` (`android/app/build.gradle:38`) was deliberately **left as-is**. `flutter_zxing 2.2.1`'s `android/build.gradle` declares `ndkVersion "27.0.12077973"` with a CMake `externalNativeBuild`; mismatched NDK across modules can trigger Gradle's "module requests NDK 27, app uses Y" error in newer AGP (RESEARCH Pitfall 4). **Contingency:** if the CI native build (the dev-APK build in `test-apk.yml`, or the prod-classpath resolution) complains about an NDK/CMake mismatch, set the app's `ndkVersion` to `27.0.12077973`. Do NOT apply this preemptively — it is only needed if CI surfaces the mismatch. This surfaces only in a real native compile; neither `flutter analyze` nor headless `flutter test` exercises it.

## Deviations from Plan

None — plan executed exactly as written. No Rules 1–4 deviations were triggered; all three tasks were pure config/CI edits with no discovered bugs, missing functionality, or blockers.

(Note: the BUILD-02 job generates an ephemeral keystore + `key.properties` before resolving the classpath, mirroring the existing build job. This is not a deviation — dependency resolution does not assemble or sign, but generating the throwaway signing material keeps the `signingConfigs.release` configuration phase clean and the job self-contained, exactly as the existing `build` job does it.)

## Owed CI / On-Device Gates (NOT run locally — toolchain absent)

Per CLAUDE.md and STATE.md, the Flutter/Dart/Android toolchain is absent in this environment. The following were **authored and statically verified (grep/read + YAML parse), NOT executed**, and are the authoritative gates:

- **BUILD-02 zero-ML-Kit graph proof** — runs only in CI via the new `dependency-graph` job (`gh workflow run test-apk.yml --ref <branch>`). It resolves `prodReleaseRuntimeClasspath` and fails on any `mlkit`/`play-services`/`gms` match. This requires the Android SDK + network and **was not and cannot be run locally**. It is the deterministic proof of the F-Droid FOSS-clean constraint. **OWED on push (user-authorized only — remotes are outward-facing).**
- **Lockfile resolution (`flutter pub get`)** — `pubspec.lock` was deliberately NOT hand-edited. The first CI `flutter pub get` regenerates it and is where `flutter_zxing 2.2.1` + its transitive `camera`/`image_picker`/`ffi`/`image` resolve. Confirm the resolved `camera`/`camera_android*` versions are AndroidX (no Play Services) in the lockfile (RESEARCH A1).
- **Native ZXing build (BUILD-01/02)** — the dev-APK build (`test-apk.yml` `build` job) is the earliest gate that actually compiles the native `.so` libs under minSdk 23. If it fails on NDK/CMake, apply the NDK-alignment contingency above (RESEARCH A2). **OWED via CI.**
- **YAML structural check** was run locally (PyYAML): `test-apk.yml` parses cleanly into two jobs (`build`, `dependency-graph`); the new job has all 7 steps in order. This confirms structure only, not that the gradle command succeeds.

## Verification Performed (static, local)

- BUILD-01: `grep minSdkVersion android/app/build.gradle` → `23` (count 1); `minSdkVersion 21` count 0.
- BUILD-02 pin: `flutter_zxing: 2.2.1` count 1; `flutter_zxing: ^` count 0 (no caret).
- SCAN-08: `android.permission.CAMERA` count 1; camera/autofocus/flash `uses-feature` present; `required="false"` count 3.
- BUILD-02 gate: `test-apk.yml` contains `./gradlew :app:dependencies --configuration prodReleaseRuntimeClasspath`, greps `mlkit|play-services|gms`, `exit 1`s on match; not `continue-on-error`; no emulator job.
- No Dart production code changed; no `.kt`/`.dart` files touched (no runtime permission request added — that lives at setup in Plan 05).
- No file deletions in any commit; no stubs introduced (config/CI only).

## Notes for Downstream Plans

- The minSdk bump + pin are now in place — Plan 02 (lock-screen camera spike) can render `ReaderWidget`, Plans 03–06 can build against `flutter_zxing`.
- The **runtime CAMERA permission REQUEST** is intentionally NOT here — it belongs at setup in Plan 05's registration card (SCAN-08: permission requested at setup, never fire time).
- The `print(setting.value)` leak at `dynamic_toggle_setting_card.dart:39` (STATE.md todo) was NOT touched — no settings-card code was modified in this plan; resolve when working in that file (Plan 05).

## Self-Check: PASSED

All 4 modified files exist on disk; all 3 task commit hashes (`afea34a`, `0fd17c1`, `bf18b1a`) exist in git history. SUMMARY.md created at `.planning/phases/04-qr-barcode-scan-to-dismiss-task/04-01-SUMMARY.md`.
