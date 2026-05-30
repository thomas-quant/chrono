# Project Research Summary

**Project:** Chrono
**Domain:** FOSS Android alarm app (Flutter) — adding a QR/barcode scan-to-dismiss alarm task + fixing reliability bugs (boot crash, snooze, date off-by-one, rising volume)
**Researched:** 2026-05-30
**Confidence:** HIGH

## Executive Summary

This milestone has two thrusts on an existing, mature Flutter alarm app: (1) add an Alarmy-style **scan-a-pre-registered-QR/barcode-to-dismiss** alarm task, and (2) fix a cluster of **reliability bugs** that are actively losing users (boot black-screen, broken snooze, specific-date off-by-one, rising volume that won't stop). The research is unusually high-confidence because the reliability root causes were confirmed at the line level against Chrono's own source and manifest — these are not hypotheses, they are diagnosed defects with named files and line numbers. The product decisions for the feature (match a *specific* registered code, gate *dismiss only*, escape-hatch ON by default, accept QR + common 1D barcodes, alarms-only, clean-room) are already locked in PROJECT.md, so research focused on *how* to build them safely rather than *whether*.

The recommended approach is opinionated and well-grounded. For the scanner, **`flutter_zxing` is the only viable choice**: it is the sole maintained Flutter scanner that is F-Droid-clean (native ZXing-C++ via FFI, zero Google ML Kit / Play Services). Every popular alternative (`mobile_scanner`, `ai_barcode_scanner`, `google_mlkit_barcode_scanning`) pulls proprietary ML Kit and would break Chrono's F-Droid distribution — a hard, non-negotiable constraint. The feature itself plugs into Chrono's existing pluggable task framework (new `AlarmTaskType` enum value + schema entry + a `StatefulWidget` mirroring `MathTask`), so the ringing-screen orchestration needs **zero changes**. The reliability fixes need **no new dependencies** at all — they are code + manifest changes (unlock-guard the boot path, make storage loads non-fatal, atomic writes, fix `.floor()` on snooze, separate "a date" from "an instant," replace the uncancellable volume ramp with a cancellable timer).

The dominant risks are concentrated and addressable. First, a **one-way-door product decision** must be made before any scanner code: `flutter_zxing 2.1.0` keeps Chrono's current minSdk 21, but the 2.2.x line bumps minSdk to 23 (drops Android 5.0/5.1) and the latest 2.3.0 requires a Flutter upgrade Chrono can't take this milestone — so the version pin is gated on whether dropping Android 5.0/5.1 is acceptable. Second, **camera preview over a secure lock screen** is the single biggest technical unknown (OEM-dependent, under-documented, can return a black preview), so it must be de-risked with an early on-device spike rather than discovered late. Third, the **escape hatch is load-bearing and core, not polish** — it is simultaneously the ethics requirement, the lockout safety net, and the accessibility path, and it must also catch permission-denied and camera-failure so a scan alarm can never become un-dismissable. The build order is dictated by Chrono's own core value ("reliably ring and stop … before any new feature"): reliability first, then the scanner feature, with the lock-screen camera spike pulled forward as a standalone probe.

## Key Findings

### Recommended Stack

The stack additions are minimal and deliberate: exactly one new dependency for the feature, and zero for the reliability fixes. Everything else reuses what Chrono already ships. The decisive call — `flutter_zxing` over the popular ML-Kit-backed scanners — is forced by the F-Droid distribution constraint, not preference, and is corroborated independently in STACK.md, FEATURES.md, ARCHITECTURE.md, and PITFALLS.md. See `.planning/research/STACK.md` for the full source-verified version matrix.

**Core technologies:**
- **`flutter_zxing` (exact pin, NOT `^`)**: QR + 1D barcode scan-to-dismiss capture — only maintained Flutter scanner with no Google/ML Kit/Play Services dependency (F-Droid-clean), and it ships its own `ReaderWidget` camera view with built-in torch, scan-frame, and zoom (no separate `camera` plugin needed). Version is a product decision (see Gaps): **`2.1.0` keeps minSdk 21**; `2.2.1` works only if minSdk to 23 is accepted; `2.3.0` is incompatible with Chrono's Flutter 3.22.2.
- **`permission_handler ^11.3.1` (already a dependency)**: runtime CAMERA permission — `Permission.camera` maps to Android CAMERA; no new dep, no version change. Request at *setup*, never at fire time.
- **No new dependency for reliability**: the boot crash, snooze, date, and volume bugs are all code + manifest fixes. `get_storage` stays; the fix is to guard/defer CE-storage reads, not to swap the storage library.

**Critical version requirement:** Pin `flutter_zxing` *exactly* (e.g. `flutter_zxing: 2.1.0`), never with a caret — a `^` range could resolve `2.3.0`, which needs Dart >=3.11 / Flutter >=3.41 and would silently break the build on the next `flutter pub upgrade`. Also note the native build requires CMake/NDK (FFI to C++); budget a small spike to green the first build (Chrono's existing `--split-per-abi` contains the APK-size impact).

### Expected Features

The market (Alarmy, Sleep as Android, QRAlarm-FOSS) sets clear expectations: register a specific code, a live viewfinder that auto-opens at ring time, continuous re-scan, and the alarm keeps ringing until the *exact* registered code is matched. Chrono's locked decisions describe the *humane* version of this proven pattern — shipping the proven core while replacing Alarmy's punitive 100-tap escalating lockout and paywall with a genuinely non-predatory, default-on escape hatch. The #1 real-world failure mode is users getting stuck with a lost/unreadable/dark code, which directly validates the escape-hatch-by-default decision. See `.planning/research/FEATURES.md`.

**Must have (table stakes, all P1):**
- Register a specific target code at setup — the whole point; stored as a `Setting<T>` in the task's `SettingGroup` (serializes for free).
- Live camera scanner at ring time that auto-opens and continuously matches — the core interaction (lives in `alarm_notification_screen.dart`, main isolate).
- Match validation with three-state feedback (no code / wrong code / match) and alarm-keeps-ringing-until-match — the wake-up guarantee.
- Camera permission/hardware handling that falls through to the escape hatch on denial/failure — non-negotiable "never trap the user."
- Escape-hatch fallback (ON by default, single sane timeout/attempt trigger) — ethics requirement + #1 real-world pain.
- Torch toggle — built into `ReaderWidget`; prevents the dominant dark-room scan failure.
- Test scan in setup — prevents lockout panic; reuses `ReaderWidget` for near-zero marginal cost.

**Should have (competitive differentiators, P2):**
- Configurable escape-hatch threshold (expose timeout/attempt knobs) — power users tighten; humane default protects everyone.
- Registered-item label hint ("You registered: Toothpaste") — prefer a plain label over a stored thumbnail (privacy).
- Haptic + visual confirmation on match — reuses the existing `vibration` dependency.
- Match on normalized `rawValue` (and optionally `format`) — cheap robustness against value collisions.

**Defer (v2+):**
- Downloadable/printable default QR code (QRAlarm parity) — *offer*, never require.
- Extending the scan task to timers — explicitly out of scope this milestone.

**Anti-features to actively avoid:** hard lockout with no exit; punitive/escalating escape hatch (Alarmy's 100 taps); gating snooze behind the scan; cloud sync / accounts for the code; uploading camera frames; paywalling the task or hatch; any ML-Kit scanner; silent auto-dismiss on timeout (defeats the alarm). Most of these tie directly to Chrono's non-predatory + F-Droid + accessibility constraints.

### Architecture Approach

The feature is additive and isolation-respecting: ScanTask is a `StatefulWidget` taking `{onSolve, settings}`, mirroring the existing `MathTask`, registered via a new `scan` enum value + an `AlarmTaskSchema` map entry. Because tasks ride the alarm's inline JSON serialization, **no `json_serialize.dart` factory entry is needed** (a notable correction to an earlier assumption), and the ring-screen orchestration is untouched — calling `onSolve()` once advances/dismisses. The hard boundary is that the **camera lives only in the main isolate** (the ring/dismiss screen), never the firing isolate; the controller binds to the ScanTask `State` (not the ring screen, so other tasks don't hold the camera), with `dispose()` + a `WidgetsBindingObserver` for pause/resume. The reliability fixes decompose into independent, testable layers, with one shared **idempotent cancel-by-id-then-set reschedule primitive** used by both the boot path and the snooze path. See `.planning/research/ARCHITECTURE.md` for line-level evidence.

**Major components:**
1. **ScanTask widget (new)** — owns camera lifecycle, decode, normalized match, escape-hatch timer/counter, calls `onSolve()`; bound to its own `State`.
2. **Scan registration UI (new)** — a one-shot scanner in the task-config flow that writes the decoded (normalized) code into the task `SettingGroup`.
3. **Boot/storage hardening (handle_boot.dart, setting_group.dart, list_storage.dart)** — unlock-guard above `initializeIsolate()`, null-guard before `json.decode` with catch to defaults (not catch to undefined), atomic temp+rename writes.
4. **Snooze state machine (alarm.dart)** — fractional duration (drop `.floor()`), cancel pending snooze + deactivate one-shot on dismiss (#457), persist snooze count across the isolate boundary, enforce max-count.
5. **Date serialization (setting.dart DateTimeSetting, date_picker_bottom_sheet.dart)** — separate "a date" (local Y/M/D) from "an instant" (epoch); normalize at the picker boundary only.
6. **Rising-volume player (ringtone_player.dart)** — replace the 11 fire-and-forget `Future.delayed` ramp callbacks + static stop-flag with an instance-scoped cancellable `Timer`.

### Critical Pitfalls

From `.planning/research/PITFALLS.md` (13 pitfalls total; top ones below):

1. **Scanner pulls in Google ML Kit, breaking F-Droid** — use `flutter_zxing`; gate before any scanner code is written by running `cd android && ./gradlew app:dependencies | grep -Ei 'mlkit|play-services|gms'` and expecting **zero** matches. `mobile_scanner`'s "unbundled" mode does NOT fix this (it just moves the model to Play Services).
2. **Boot isolate touches credential-encrypted storage before first unlock** — `handleBoot()` reads `get_storage`/settings before unlock, throwing `IllegalStateException`, causing a boot crash + half-written state, then a next-launch splash hang (the #442 epic). Guard with `isUserUnlocked` / defer to `ACTION_USER_UNLOCKED`; make boot reschedule idempotent; time-box the splash.
3. **Silent catch-and-fallback masks corruption** — existing broad `catch (e)` blocks + GetStorage-vs-text-file dual-store drift turn a data problem into a mystery. Replace with typed, logged recovery; pick one canonical store with an explicit one-time migration; null-guard before every `json.decode`.
4. **Snooze: `.floor()` floors fractional snooze to 0, and one-shot alarms re-fire after snooze-then-dismiss** — use seconds/`Duration`, clamp `<=0`; branch dismiss on `OnceAlarmSchedule` to deactivate (never reschedule); persist `_snoozeCount` before the isolate boundary; enforce max-count.
5. **No escape hatch / camera over the lock screen** — the alarm becomes un-dismissable (worst outcome for an alarm app). Build the escape hatch **before/alongside** the scan-success path; it must trigger on attempt-count *and* elapsed time, default ON, and cover permission-denied + camera-failure. Camera-over-lockscreen can yield a black preview (OEM-dependent) — verify on a secure lock screen across multiple OEMs early.

Also notable: code matching must **normalize both sides identically** (trim/strip control chars/case) or the correct code is silently rejected on a trailing newline; camera must be released on every exit path (privacy dot); never log scan payloads.

## Implications for Roadmap

Based on combined research, the suggested phase structure follows Chrono's core value (reliability before feature) with the highest-unknown probe pulled forward. The reliability cluster has an internal dependency spine — storage hardening and the idempotent reschedule primitive underpin everything else.

### Phase 1: Storage Hardening (foundation)
**Rationale:** Every other change reads/writes storage; the corruption-to-hang chain lives in the load/save layer, so the boot fix is meaningless if a late load still corrupts. This builds the shared idempotent reschedule primitive that Phases 2 and 3 both depend on.
**Delivers:** Non-fatal load (null-guard before `json.decode`, catch to defaults, contained GetStorage fallback, wrapped `initializeIsolate()`); atomic temp+rename writes; an idempotent cancel-by-id-then-set reschedule primitive; time-boxed splash.
**Addresses:** Reliability epic (#442/#420/#448/#489/#498/#516/#514/#483/#289) load-side; the "next launch hangs on splash" half.
**Avoids:** Pitfall 3 (silent catch masks corruption); the load-path half of Pitfall 2.

### Phase 2: Boot / Direct-Boot Guard
**Rationale:** Highest-severity user-facing bug (boot black-screen). Depends on Phase 1's non-fatal load + idempotent reschedule.
**Delivers:** Unlock guard in `handleBoot()` (check `isUserUnlocked` / defer to `ACTION_USER_UNLOCKED`); narrowed Direct-Boot manifest surface; reschedule on `BOOT_COMPLETED` (post-unlock). Optional device-protected (DE) storage only if pre-unlock firing is required (flagged as a product decision, not assumed).
**Implements:** Boot/storage hardening component.
**Avoids:** Pitfall 2 (boot touches locked storage).

### Phase 3: Snooze State Machine
**Rationale:** CRITICAL cluster alongside boot; depends on Phase 1's idempotent reschedule primitive.
**Delivers:** Fractional snooze duration (drop `.floor()` at both sites); `handleDismiss()` cancels pending snooze + deactivates one-shot (#457); persist snooze count across isolate boundary; enforce max-count; "never re-fires" fix.
**Addresses:** Snooze cluster (#439/#495/#445/#457).
**Avoids:** Pitfall 4 (fractional floors to 0; one-shot re-fires).

### Phase 4: Date Serialization + Volume + FAB (HIGH-value bug batch)
**Rationale:** Largely independent of Phases 2-3; Date depends on Phase 1 (load must tolerate old epoch values during migration). Groups the HIGH-value fixes, including community PRs to merge.
**Delivers:** Local-date normalization at picker boundary + date-aware `DateTimeSetting` (#340/#455/#472); cancellable-Timer rising-volume ramp via reviewing/merging PR #467 (#407/#506); FAB overlap fix via PR #466 (#417).
**Avoids:** Pitfall 5 (date off-by-one) and Pitfall 6 (uncancellable volume ramp). **Note:** DST recurring-alarm recompute (#359) is explicitly OUT of scope.

### Phase 5: Lock-Screen Camera Spike (de-risking probe — can run early/in parallel)
**Rationale:** The single biggest unknown in the milestone. Whether a live camera preview works from the `flutter_show_when_locked` ring activity on a secure lock screen is OEM-dependent and under-documented; a black preview would invalidate or reshape the entire feature design and could force native work. Pull this forward as a standalone probe — it does not depend on the reliability work.
**Delivers:** On-device validation across several OEMs/Android versions; a go/no-go (or "requires unlock first") decision and any native plumbing needed.
**Avoids:** Pitfall 12 (camera over lock screen — black preview / permission dialog behind keyguard).

### Phase 6: Scanner Foundation (dependency gate)
**Rationale:** Per core value, the feature comes after reliability. The dependency choice and minSdk decision are a one-way door that must be settled first.
**Delivers:** minSdk product decision (21 vs 23), then `flutter_zxing` exact-version pin; green native (CMake/NDK) build; CAMERA manifest entry + `uses-feature required="false"`; verified zero `mlkit`/`gms`/`play-services` in the Gradle graph; F-Droid (`prod`) build compiles.
**Uses:** `flutter_zxing` (exact pin), existing `permission_handler`.
**Avoids:** Pitfall 1 (ML Kit breaks F-Droid) — verification is the phase exit criterion.

### Phase 7: Scan-to-Dismiss Task UI
**Rationale:** Builds on a green scanner foundation and a resolved lock-screen spike. Escape hatch is built first/alongside the scan-success path, not after.
**Delivers:** `scan` enum value + schema entry + `SettingGroup` fields (Registered Code, escape hatch); registration UI (one-shot scan, write normalized code); ScanTask widget (camera lifecycle, normalized match, three-state feedback, torch, escape hatch, `onSolve()`); test scan in setup; l10n strings.
**Addresses:** All P1 feature table stakes + torch + test scan.
**Implements:** ScanTask + registration components.
**Avoids:** Pitfalls 7-11, 13 (camera release, torch, escape hatch, ANR, whitespace match, wakelock cap).

### Phase Ordering Rationale
- **Reliability before feature** is mandated by PROJECT.md's core value; an unreliable alarm app fails its one job.
- **Phase 1 first** because the corruption chain is in the shared load/save layer and the idempotent reschedule primitive is the spine for Phases 2 and 3 — build once, depend twice.
- **Phase 5 (camera spike) pulled forward** as a parallelizable probe because it is the biggest unknown and a negative result reshapes the feature — discovering that late is the expensive failure.
- **Phase 6 before Phase 7** because the minSdk/version decision and the F-Droid dependency gate are one-way doors that everything downstream depends on.
- The escape hatch is treated as core within Phase 7 (built first), not deferred — it is the ethics, safety, and accessibility path simultaneously.

### Research Flags

Phases likely needing deeper research during planning (`/gsd-plan-phase --research-phase <N>`):
- **Phase 2 (Boot Guard):** Direct-Boot plumbing through `flutter_boot_receiver` — does it expose unlock state / `LOCKED_BOOT_COMPLETED`, or is a native `directBootAware` + `USER_UNLOCKED` receiver required? Note the commented `path:` fork override in `pubspec.yaml` suggests native edits may be needed. Also confirm which manifest `directBootAware` lines are Chrono-owned vs plugin-supplied before editing.
- **Phase 5 (Lock-Screen Camera Spike):** Inherently a research/spike phase — on-device behavior across OEMs is the unknown; no amount of doc-reading substitutes for hardware testing.
- **Phase 7 (Scan Task UI):** `flutter_zxing` `ReaderWidget` lifecycle/dispose semantics on the pinned (pre-2.3.0) line — 2.3.0 fixed camera-disposal issues you won't have, so verify defensive dispose/resume; confirm result-callback shape for normalized matching.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Storage Hardening):** Root causes confirmed at line level; the fixes (null-guard, atomic write, idempotent reschedule) are well-understood patterns.
- **Phase 3 (Snooze):** Bugs confirmed at line level (`.floor()` sites, dismiss-path gap); the state machine is small and specified.
- **Phase 4 (Date/Volume/FAB):** Mechanisms confirmed (epoch round-trip; `Future.delayed` + static flag); two community PRs (#467, #466) to review against the stated cancellation/correctness criteria.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Scanner choice, F-Droid verdict, and version/minSdk facts source-verified from pub.dev API + git tags (not training data); reliability root cause confirmed against Chrono's actual manifest. |
| Features | HIGH | Market behavior grounded in official Alarmy + Sleep as Android docs and the QRAlarm FOSS precedent; product decisions already locked. MEDIUM only on community pain points and exact lock-screen camera behavior. |
| Architecture | HIGH | Line-level evidence from source files read this session (task framework, isolate split, snooze, date, boot). MEDIUM/LOW only where dependent on external library/Android-API behavior (flagged [VERIFY]). |
| Pitfalls | HIGH | Four reliability clusters corroborated directly against `CONCERNS.md` + source; F-Droid/ML Kit finding verified against pub.dev. MEDIUM only for camera-over-lockscreen (device-dependent). |

**Overall confidence:** HIGH

### Gaps to Address

- **minSdk product decision (one-way door, blocks Phase 6):** `flutter_zxing 2.1.0` keeps minSdk 21; `2.2.1` forces minSdk 23 (drops Android 5.0/5.1). Must be decided *before* the scanner is pinned. Resolve as an explicit product call at the start of Phase 6. (Note: FEATURES.md/ARCHITECTURE.md reference `2.2.1` while the source-verified STACK.md recommends `2.1.0` to preserve minSdk 21 — STACK.md is authoritative; the discrepancy IS this open decision.)
- **Lock-screen camera behavior across OEMs (highest technical risk):** can a preview render from the keyguard-visible ring activity, or does it black-out? Resolve via the Phase 5 on-device spike before committing the Phase 7 design.
- **Direct-Boot manifest ownership + `flutter_boot_receiver` capabilities:** which `directBootAware`/`LOCKED_BOOT_COMPLETED` lines are Chrono-owned vs forked-plugin-supplied, and whether the plugin exposes unlock state or needs native edits. Trace during Phase 2 planning.
- **Pre-unlock firing in scope?** Product call: must alarms ring before first unlock after reboot? Yes means device-protected (DE) storage work (heavier); No means a pure code guard suffices. Decide at Phase 2; default assumption is "no" (defer-until-unlock).
- **Unread snooze/date files:** `once_alarm_schedule.dart` + `schedule_alarm.dart` (the "never re-fires" path) and `date_picker_bottom_sheet.dart:145` were not opened this session — confirm during Phase 3/4 planning.

## Sources

### Primary (HIGH confidence)
- pub.dev package API (`/api/packages/flutter_zxing`) + git tags `android/build.gradle` — per-version Dart/Flutter/minSdk constraints (2.1.0 = minSdk 21; 2.2.x = 23; 2.3.0 = Dart 3.11/Flutter 3.41).
- developer.android.com/privacy-and-security/direct-boot — CE vs DE storage, `directBootAware`, `LOCKED_BOOT_COMPLETED`, `isUserUnlocked`, `createDeviceProtectedStorageContext`.
- Chrono source (read line-level this session): `alarm_task.dart`, `alarm_task_schemas.dart`, `alarm_notification_screen.dart`, `math_task.dart`, `alarm.dart`, `handle_boot.dart`, `initialize_isolate.dart`, `setting_group.dart`, `list_storage.dart`, `ringtone_player.dart`, `setting.dart`, plus `AndroidManifest.xml`, `pubspec.yaml`, `android/app/build.gradle`.
- Chrono `.planning/codebase/{ARCHITECTURE,STACK,STRUCTURE,CONVENTIONS,INTEGRATIONS,TESTING,CONCERNS}.md` and `PROJECT.md`.
- Alarmy Help Center (QR/Barcode mission; Emergency Mode 100-tap escalation), Sleep as Android CAPTCHA docs, QRAlarm F-Droid listing + GitHub (`sweakpl/qralarm-android`).
- Android full-screen-intent limits (alarm-app exemption); pub.dev `permission_handler` (Permission.camera maps to CAMERA).

### Secondary (MEDIUM confidence)
- F-Droid Anti-Features (NonFreeDep) policy + threads on mobile_scanner / ML Kit exclusion.
- orhanobut/hawk #224, mobile_scanner #505 — real-world corroboration of CE-storage-before-unlock and camera-stays-alive-on-pop.
- Community pain reports (lost/unreadable code, "set a backup alarm"); Alarmy "recognition not working well" support article (code-match fragility).
- Accessibility references (AFB, BOIA) on QR camera-alignment barriers for blind/low-vision users.

### Tertiary (LOW confidence — validate on hardware)
- Flutter camera + `showWhenLocked` + CameraX background/locked-capture behavior — OEM-dependent, under-documented; the Phase 5 spike is the validation.

---
*Research completed: 2026-05-30*
*Ready for roadmap: yes*
