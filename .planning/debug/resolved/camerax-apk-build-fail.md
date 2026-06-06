---
slug: camerax-apk-build-fail
status: resolved
trigger: "Phase-4 dev APK build fails at :camera_android_camerax:compileReleaseJavaWithJavac (camera_android_camerax-0.6.8+2 PreviewHostApiImpl.java compile errors), introduced by flutter_zxing 2.2.1 pulling the camera plugin on Flutter 3.22.2"
created: 2026-06-06
updated: 2026-06-06
phase: 04-qr-barcode-scan-to-dismiss-task
---

# Debug session: camerax-apk-build-fail

## Symptoms

- **Expected:** `flutter build apk --release --flavor dev` (and `--flavor prod`) produces an installable APK. Before Phase 4 this worked (last green dev-APK build 2026-05-30).
- **Actual:** The build fails during `:camera_android_camerax:compileReleaseJavaWithJavac` → "Gradle task assembleDevRelease failed with exit code 1". (The BUILD-02 `flutter build apk --config-only` path SUCCEEDS — `--config-only` does not compile native/java, so it does not exercise this.)
- **Error (verbatim, from CI run 27050905352, job "Analyze + Test + Release APK"):**
  ```
  .../camera_android_camerax-0.6.8+2/android/src/main/java/io/flutter/plugins/camerax/PreviewHostApiImpl.java:84: error: cannot find symbol
  .../PreviewHostApiImpl.java:85: error: method does not override or implement a method from a supertype
  .../PreviewHostApiImpl.java:91: error: method does not override or implement a method from a supertype
  3 errors
  Execution failed for task ':camera_android_camerax:compileReleaseJavaWithJavac'.
  ```
- **Timeline:** Started in Phase 4 when `flutter_zxing: 2.2.1` (exact pin) was added in plan 04-01. `flutter pub get` resolved the transitive Flutter `camera` plugin's Android impl to `camera_android_camerax 0.6.8+2`.
- **Reproduction:** Build the dev (or prod) APK. Locally the Flutter/Dart toolchain is ABSENT — reproduce/verify only in CI: `gh workflow run test-apk.yml --ref master --repo thomas-quant/chrono`, then watch the "Build release dev APK" step.

## Constraints (must hold for any fix)

1. **F-Droid-clean:** the BUILD-02 CI gate greps the prod release runtime classpath for `mlkit|play-services|gms` and currently PASSES. Any fix must keep it passing — do NOT introduce ML Kit / Play Services / gms (rules out swapping to a gms-based camera/scanner).
2. **No local toolchain:** every build attempt is verified in CI only (test-apk.yml on `thomas-quant/chrono`, `workflow_dispatch`). `tests.yml` is already green (212/212) and unaffected.
3. **Stack is pinned:** Flutter 3.22.2, Dart 3.4, compileSdk 34, minSdk 23, Kotlin 1.8, Java 17, AGP/Gradle 7.6.4, NDK 27.0.12077973. `flutter_zxing` is pinned 2.2.1 (the F-Droid-clean line; 2.3.0 needs Flutter ≥3.41 — out of reach).

## Current Focus

- hypothesis (REFINED): The failure is a **Flutter-engine/plugin API skew**, not a Pigeon/platform-interface skew. `flutter_zxing 2.2.1 → camera → camera_android_camerax` is constrained `^0.6.5` (= `>=0.6.5 <0.7.0`). The committed `pubspec.lock` is **stale** (predates the Phase-4 flutter_zxing add; contains zero camera/zxing entries), so CI `flutter pub get` floats `camera_android_camerax` to the highest match → `0.6.8+2`. That release adopted the Flutter engine `TextureRegistry.SurfaceProducer` API in `PreviewHostApiImpl.java`; that API does NOT exist in the Flutter **3.22.2** Android embedding engine → `cannot find symbol` (the `SurfaceProducer` type, line 84) and `does not override a supertype method` (the surface-availability callbacks, lines 85/91). The fix is to cap `camera_android_camerax` to the pre-SurfaceProducer `0.6.5.x` line (contemporaneous with Flutter 3.22.2) via `dependency_overrides`. Capping `camera` itself does NOT help (pub would still float camerax up under `^0.6.5`); the upper bound must be on `camera_android_camerax` directly.
- test: applied `dependency_overrides: camera_android_camerax: '>=0.6.5 <0.6.6'`; verify via CI test-apk.yml "Build release dev APK" + BUILD-02 gate.
- expecting: dev APK builds (camerax javac compiles against the 3.22.2 engine) AND the BUILD-02 zero-ML-Kit gate still PASSES (0.6.5.x is pure androidx.camera, FOSS).
- next_action: RESOLVED — CI confirmed the fix on the first round (see Evidence + Resolution). No further action.

## Evidence

- timestamp: 2026-06-06 — CI run 27050905352 "Build release dev APK" failed with the 3 javac errors above; the sibling BUILD-02 zero-ML-Kit job in the same run PASSED (so config/resolution is fine; only the camerax java compile breaks).
- timestamp: 2026-06-06 — `flutter build apk --config-only` (BUILD-02 job) succeeds, confirming the failure is in native/java compilation of the camera plugin, not Gradle configuration or dependency resolution.
- timestamp: 2026-06-06 — Inspected committed `pubspec.lock`: it contains **zero** `flutter_zxing` / `camera` / `camera_android_camerax` / `camera_platform_interface` entries and was last written by an old commit (pre-Phase-4, "Add analog clock"). CONCLUSION: the lock is stale; CI `flutter pub get` resolves the camera federation fresh and floats `camera_android_camerax` to the latest under `^0.6.5` (= 0.6.8+2). This explains why a build that was green 2026-05-30 broke purely from adding flutter_zxing.
- timestamp: 2026-06-06 — Resolver reasoning verified: `camera`'s `^0.6.5` on camera_android_camerax means a `camera` pin alone cannot pin the impl down; an explicit upper-bounded `dependency_overrides` on `camera_android_camerax` is required. (No local toolchain/network: pub.dev version dates not re-confirmed online; pin chosen from the package being contemporaneous with Flutter 3.22.2 and is robust to over-conservatism since 0.6.5.x predates the SurfaceProducer migration regardless of whether it landed at 0.6.6/0.6.7/0.6.8.)
- timestamp: 2026-06-06 — APPLIED FIX: added to `pubspec.yaml` `dependency_overrides`: `camera_android_camerax: '>=0.6.5 <0.6.6'`. Only `pubspec.yaml` changed (commit 21a7f11); `pubspec.lock` regenerated by CI `flutter pub get`.
- timestamp: 2026-06-06 — **CI CONFIRMED (hypothesis verified, first round).** test-apk.yml run 27051911373 (commit 21a7f11): overall conclusion=success; "Build release dev APK" step=success; "Upload APK artifact"=success (chrono-dev-release-apk, 59.7 MB); BUILD-02 "Verify zero ML Kit in prod release dependency graph"=success (F-Droid-clean preserved). tests.yml run 27051911662=success, 212/212. The camerax cap eliminated the SurfaceProducer javac errors with zero regression.

## Eliminated

- Pinning `camera` (the app-facing package) as the fix knob — REJECTED by resolver analysis: `camera`'s `^0.6.5` constraint still lets pub float `camera_android_camerax` to 0.6.8+2. The override must target `camera_android_camerax` directly.
- "Gradle configuration / dependency resolution" as the fault location — ELIMINATED: BUILD-02 `--config-only` and `tests.yml` are green; only javac of the camerax plugin fails.

## Resolution

- root_cause: A Flutter-engine ↔ plugin API skew surfaced by a stale `pubspec.lock`. The committed lock predated the Phase-4 `flutter_zxing: 2.2.1` add and contained no camera/zxing entries, so CI `flutter pub get` resolved the camera federation fresh. `flutter_zxing 2.2.1 → camera → camera_android_camerax` is constrained `^0.6.5`, so pub floated the impl to `0.6.8+2`, which adopted the engine `TextureRegistry.SurfaceProducer` API in `PreviewHostApiImpl.java`. That API does not exist in the Flutter 3.22.2 Android embedding → `cannot find symbol` (line 84) + `does not override a supertype` (lines 85/91). `--config-only` (BUILD-02 job) never compiled the plugin java, so it didn't surface the skew.
- fix: Capped the transitive impl to the pre-SurfaceProducer line via `pubspec.yaml` `dependency_overrides: camera_android_camerax: '>=0.6.5 <0.6.6'`. Pinning `camera` itself does not work (pub still floats camerax up under `^0.6.5`); the bound must target `camera_android_camerax` directly. `0.6.5.x` is pure `androidx.camera` (FOSS) — no ML Kit / Play Services introduced.
- verification: CI test-apk.yml run 27051911373 (commit 21a7f11) — "Build release dev APK" success, APK artifact uploaded; BUILD-02 zero-ML-Kit gate success; tests.yml run 27051911662 — 212/212. No local toolchain (CI is authoritative).
- files_changed: `pubspec.yaml` (commit 21a7f11). `pubspec.lock` regenerated by CI (not committed locally — see follow-up note).
- follow_up: Consider committing the CI-regenerated `pubspec.lock` so the camerax pin is hardened against future float (CI re-resolves each run today). Out of scope for this fix; tracked in MANUAL-VERIFICATION-LOG.md.
