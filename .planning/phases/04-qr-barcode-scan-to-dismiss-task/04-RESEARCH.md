# Phase 4: QR/Barcode Scan-to-Dismiss Task - Research

**Researched:** 2026-06-05
**Domain:** Flutter Android — native barcode scanning (ZXing FFI), camera-over-lock-screen, alarm-task framework extension, F-Droid FOSS provenance
**Confidence:** HIGH on everything resolvable from docs/source/codebase; the lock-screen camera behavior remains a genuine ON-DEVICE unknown by nature (it is a hardware spike — see Item 1).

## Summary

The phase is well-bounded by CONTEXT.md's locked decisions; this research fills the four deferred technical gaps. Three of the four are now **decision-complete from authoritative sources**: (2) the exact `flutter_zxing` pin is **`2.2.1`** (the only 2.2.x line that is both F-Droid-clean and compatible with Flutter 3.22.2 — `2.3.0` requires Flutter ≥3.41 and is correctly excluded; the plugin's own `android/build.gradle` hard-codes `minSdkVersion 23`, which is the real driver of BUILD-01); (3) the escape-hatch debounce is **already solved for free** by `ReaderWidget`'s `scanDelay` (default 1000ms rate-limit) plus the split `onScan`/`onScanFailure` callbacks; (4) the registration card and ring widget both slot cleanly into existing seams (`CustomSetting`-style card rendered by `getSettingWidgets` over the task's `SettingGroup`; a `ScanTask` widget mirroring the math/retype task widgets; the ring orchestration in `alarm_notification_screen.dart` needs **zero** change, confirmed by reading `_setNextWidget()`).

The remaining true unknown is (1) the **lock-screen camera spike**. Chrono renders the ring screen over a secure keyguard via a **runtime native call** — `FlutterShowWhenLocked().show()` (`alarm_notifications.dart:182`) — **NOT** a manifest `android:showWhenLocked` attribute (the manifest has none). Whether a live CameraX/Camera2 preview composites and decodes inside that window over a *secure* keyguard cannot be answered by doc-reading; it must be tested on ≥2 OEMs. The plan must sequence this spike FIRST, as a discrete go/no-go gate, before the scan-task UI is committed — the default-on escape hatch is the universal safety net that lets the feature ship regardless of outcome (D-LOCK-SHIP).

**Primary recommendation:** Pin `flutter_zxing: 2.2.1` (exact), bump `minSdkVersion 23`, add `CAMERA` + `uses-feature camera required="false"` to the manifest. Build the feature as: a `scan` `AlarmTaskType` + schema (`StringSetting` registered code + `SwitchSetting` escape-hatch toggle) + a `ScanTask` ring widget + an inline registration card in the task's `SettingGroup`. Extract two pure CI-testable seams — a `normalizeCode()`/`codesMatch()` function and an `EscapeHatchController` (injectable `Clock`/`Timer`) — and unit-test them headlessly, mirroring the Phase-2 `alarm_snooze_test.dart` pattern. Run the lock-screen spike as the first plan, in isolation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Escape hatch (SCAN-06/07):**
- **D-ESC-TRIGGER:** Plain-dismiss unlocks on **time OR failed-attempts, whichever comes first.** Camera-permission-denied and camera-unavailable auto-trigger it **instantly** (SCAN-07).
- **D-ESC-DEFAULT:** Single sane default ≈ **120s elapsed** OR a debounced wrong-read count (~10). *Claude's discretion on exact attempt number + wrong-read debounce mechanism* — ZXing emits many reads/sec, so failed attempts MUST be debounced (count distinct non-matching payloads, or rate-limit ~1/sec), NOT raw decode callbacks.
- **D-ESC-EXPOSURE:** v1 exposes an **on/off toggle only**; threshold numbers live behind it. Fine-grained knobs = v2 (SCAN-V2-02).
- **D-ESC-SCOPE:** When the escape hatch fires it **skips only the scan task** — tasks stacked after it still run. "Never un-dismissable" (SCAN-07) is scoped to the scan task / camera failure, not the whole alarm.
- **D-ESC-MODEL:** Implement ONLY the non-predatory safety auto-dismiss. Do **NOT** build Alarmy's "Emergency Escape" friction path (guilt-pledge, escalating penalty). Forbidden by accessibility/ethics constraint.

**Lock-screen camera de-risk (criterion #1):**
- **D-LOCK-SPIKE-SCOPE:** Spike tests **only** Chrono's existing `showWhenLocked`-activity path (`flutter_show_when_locked`). Black/dead preview on secure keyguard ⇒ go straight to unlock-then-scan fallback. (Did NOT adopt Alarmy's overlay approach for the spike.)
- **D-LOCK-NOGO-UX:** On no-go devices, show an "unlock to scan" prompt over the keyguard; scanner opens once unlocked; alarm keeps ringing until then. Escape hatch always underneath.
- **D-LOCK-SHIP:** **Ship regardless** of spike outcome — the default-on escape hatch is the universal safety net.

**Code registration (SCAN-02/08/10):**
- **D-REG-UI:** **Inline custom setting card** with a "Scan to register" button inside the task's settings. Not a separate dedicated screen.
- **D-REG-DISPLAY:** **Status only** — "✓ Code registered". Do NOT display the raw decoded value (privacy; never log payloads). Label/name = v2.
- **D-REG-TEST:** Registration **is** the test scan (satisfies SCAN-10). Offer optional "scan again to re-test"; no separate mandatory step.
- **D-REG-REQUIRED:** A registered code is **required to save** the task. Re-scanning **replaces** the stored code.
- **D-REG-CAMDENIED:** Camera denied at setup → **deep-link to system app-settings**, then resume registration. Permission requested at **setup, never fire time** (SCAN-08).

**Ring-time scanner (SCAN-03/05/09):**
- **D-RING-LAYOUT:** Scan task is **just another task widget** rendered full-screen in the dismiss step, entered via existing swipe-to-dismiss (`SlideNotificationAction` → `_setNextWidget()` → `task.builder(onSolve)`). No new ring orchestration. Volume auto-lowers to `volumeDuringTasks`.
- **D-RING-SNOOZE:** Snooze stays the **existing pre-task ring action** (`SlideNotificationAction.onSnooze`), reachable without entering the scanner (satisfies SCAN-05). No snooze affordance inside the scanner.
- **D-RING-WRONGSCAN:** Non-matching scan → brief visual + haptic "not the registered code" feedback + counts toward the failed-attempt escape threshold.

**Storage & matching (SCAN-02/03):**
- **D-STORE-FORMAT:** Persist the registered code as a **raw, normalized string** in the task's `SettingGroup` (a `StringSetting`; no `json_serialize.dart` factory entry needed). Chosen over a hash so a v2 label/display stays possible.
- **D-MATCH-NORMALIZE:** Normalize **both sides identically** at register and compare — trim / strip control chars / case. Normalize **before** storing; compare normalized-to-normalized.

### Claude's Discretion
- **Barcode symbology set:** broad ZXing format set (QR + EAN-8/13, UPC-A/E, Code128, Code39, ITF, + QR/DataMatrix). Confirm exact `flutter_zxing` format-enable config (resolved below); narrow only if spurious reads surface (SCAN-04).
- Exact escape attempt-count + wrong-read debounce mechanism (D-ESC-DEFAULT) — recommended below.
- Torch default (off), rear camera default, scan-frame overlay styling.
- Reuse `ReaderWidget` directly vs a thin wrapper — planner's call (recommendation below).

### ⚠ DEVIATION — clean-room override (D-CLEANROOM-OVERRIDE)
The user explicitly overrode the locked "clean-room only" constraint **for this personal fork**, after being advised 3×. Alarmy 26.23.0 was decompiled in a private throwaway repo; only observable-behavior artifacts (strings.xml, manifest, layout names) informed decisions; R8-obfuscated source was not read/copied. **Downstream consequence:** reconcile the clean-room/F-Droid-provenance docs at the next `/gsd-transition` (re-affirm or formally amend). Flagged, not silently absorbed.

### Deferred Ideas (OUT OF SCOPE)
- v2 scan enhancements: registered-item label at ring time (SCAN-V2-01), configurable escape thresholds as knobs (SCAN-V2-02), downloadable/printable default QR (SCAN-V2-03), scan-to-dismiss for timers (SCAN-V2-04).
- Multiple registered codes per task (match any of a set).
- Overlay (`SYSTEM_ALERT_WINDOW`) + keyguard-dismiss lock-screen approach — held as the **fallback** to revisit only if the `showWhenLocked` spike is no-go and we want to recover those OEMs before accepting unlock-then-scan.
- "Mute during mission" (capped) — Chrono already auto-lowers via `volumeDuringTasks`.
- Reconcile clean-room constraint docs at next `/gsd-transition`.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BUILD-01 | minSdk 21 → 23 | `flutter_zxing 2.2.1` `android/build.gradle` hard-codes `minSdkVersion 23` [VERIFIED: github.com/khoren93/flutter_zxing/blob/main/android/build.gradle]. Edit `android/app/build.gradle:56` `minSdkVersion 21` → `23`. CI build gate. |
| BUILD-02 | `flutter_zxing` exact-pinned 2.2.x, zero mlkit/gms/play-services | Pin `2.2.1` (Item 2). Plugin build references **zero** gms/mlkit; transitive `camera` resolves to AndroidX Camera2/CameraX (no Play Services). Verify via `./gradlew :app:dependencies` in CI (command below). |
| SCAN-01 | Add "Scan code to dismiss" task alongside math/retype/sequence/memory | New `AlarmTaskType.scan` + schema entry in `alarmTaskSchemasMap` (Item 4). Drop-in; ring orchestration unchanged. |
| SCAN-02 | Register a QR/1D barcode at setup; store in task settings | Inline registration card opens `ReaderWidget`; `code.text` normalized → `StringSetting`. `Code.text` field confirmed (Item 2). |
| SCAN-03 | Ring-time match dismisses; normalize both sides | `onScan: (Code c) => codesMatch(normalize(c.text), storedNormalized)` → `onSolve()`. Pure `normalizeCode`/`codesMatch` seam (Item 4 / Validation). |
| SCAN-04 | Accept QR + common 1D barcodes | `codeFormat: int` bitmask; default `Format.any`. Recommended explicit set below (Item 2). |
| SCAN-05 | Gates full dismiss only; snooze stays a normal tap | D-RING-SNOOZE: snooze lives on the pre-task `SlideNotificationAction`, never inside the scanner. Confirmed by `_setNextWidget()` read. |
| SCAN-06 | Escape hatch ON by default, threshold (attempts and/or time), user can tighten/disable | `EscapeHatchController` seam + `SwitchSetting("Escape Hatch", default true)`. v1 = on/off toggle only (D-ESC-EXPOSURE). |
| SCAN-07 | Escape also on cam-denied + cam-unavailable; screen-reader reachable | `onControllerCreated(controller, exception)` surfaces init failure → fire escape instantly. Wrap escape button in `Semantics`. (Item 2/3.) |
| SCAN-08 | Permission at setup (never fire time); CAMERA + uses-feature required="false" | `permission_handler` `Permission.camera` at registration (mirror `lib/system/logic/permissions.dart`). Manifest additions below. |
| SCAN-09 | Torch toggle in scanner | `ReaderWidget(showFlashlight: true)` built in; graceful no-flash handling. Default off (D discretion). |
| SCAN-10 | Test scan at setup | D-REG-TEST: registration **is** the test scan; optional re-scan. Reuse the `TryAlarmTaskScreen` precedent. |
| SCAN-11 | Camera released on every exit path | `ReaderWidget.dispose()` disposes `CameraController`; pause/inactive/hidden stops stream. Verify dispose on success/escape/background (Item 2, Pitfall 1). |
| SCAN-12 | New strings localized (English baseline) | Add keys to `lib/l10n/app_en.arb` (`"key":"value"` + `"@key":{}` pattern). `flutter gen-l10n` is a CI/human gate. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Live camera preview + decode (register + ring) | Main isolate / notification screen UI | — | Camera lifecycle MUST be main-isolate; firing isolate has no FlutterEngine/UI. Confirmed by ARCHITECTURE.md + `alarm_notification_screen.dart` running in main isolate. |
| Code normalization + match | Pure Dart logic (domain) | — | Dependency-free; CI-testable; no camera/UI. The `normalizeCode`/`codesMatch` seam. |
| Escape-hatch threshold timing | Pure Dart controller (domain) | UI (wires callback) | Injectable `Clock`/`Timer`; CI-testable. Mirrors Phase-3 `VolumeRampController`. |
| Registered-code persistence | Settings layer (`SettingGroup` JSON) | — | `StringSetting` rides inline alarm JSON; no new persistence path. |
| Camera permission request | System layer (`permission_handler`) | UI | Requested at setup (D-REG-CAMDENIED / SCAN-08). |
| Over-lock window | Native (`flutter_show_when_locked` runtime call) | — | `FlutterShowWhenLocked().show()` already invoked in `alarm_notifications.dart:182`; the scan preview inherits whatever this window allows. **This is the spike's subject.** |
| Ring orchestration / task sequencing | Existing ring state machine | — | `_setNextWidget()` unchanged; new task auto-picked-up. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_zxing` | **2.2.1** (exact, not caret) | Native ZXing barcode/QR scanner via Dart FFI; provides `ReaderWidget` (camera + torch + overlay + decode) | The only F-Droid-clean Flutter scanner (pure ZXing C++ via FFI, zero ML Kit/Play Services). 147 likes, 160/160 pub points, ~49K downloads/30d, real repo `khoren93/flutter_zxing` [VERIFIED: pub.dev API]. |

**Why 2.2.1 exactly (not `^2.2.0`, not 2.3.0):** [VERIFIED: pub.dev API `/api/packages/flutter_zxing`]
- `2.2.1` (published 2025-08-10) declares `flutter: >=3.3.0, sdk: >=3.3.3 <4.0.0` — **compatible** with Chrono's Flutter 3.22.2 / Dart 3.4.
- `2.3.0` (published 2026-04-20) declares `flutter: >=3.41.0, sdk: >=3.11.0` — **incompatible** with Flutter 3.22.2. A caret `^2.2.0` would let pub upgrade into `2.3.0` and break the build. **Pin exactly `2.2.1`.**
- `2.2.0` and `2.2.1` were both published 2025-08-10; `2.2.1` is the patch and the correct pin.

### Supporting (all already in pubspec — no new deps beyond flutter_zxing)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `permission_handler` | ^11.3.1 (existing) | `Permission.camera` request at setup | SCAN-08. Mirror `lib/system/logic/permissions.dart`. |
| `app_settings` | ^5.1.1 (existing) | Deep-link to system app-settings when camera denied | D-REG-CAMDENIED. Pattern: `AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization)` at `general_settings_schema.dart:344`. |
| `vibration` | ^1.7.6 (existing) | Haptic "not the registered code" feedback | D-RING-WRONGSCAN. |
| `flutter_show_when_locked` | ^0.0.4 (existing) | Over-lock window (already used by the ring screen) | The spike's subject — no new call needed; `.show()` already at `alarm_notifications.dart:182`. |
| `clock` | ^1.1.1 (existing) | Mockable clock for the escape-hatch controller test seam | Mirrors `alarm_snooze_test.dart` `withClock(Clock.fixed(...))`. |

### Transitive dependencies of flutter_zxing 2.2.1 [VERIFIED: pub.dev API]
`camera: >=0.10.5 <0.12.0`, `ffi: ^2.0.0`, `image: ^4.1.0`, `image_picker: ^1.0.0`. All FOSS. The FOSS-cleanliness risk is **`camera`** (see Package Legitimacy Audit + Pitfall 3): on Flutter 3.22.2 pub's solver will resolve `camera` to a version whose Android impl is `camera_android` (Camera2) or a 3.22-compatible `camera_android_camerax` — both AndroidX, **no ML Kit / Play Services**. `image_picker`'s Android impl is also AndroidX-clean. **Must be confirmed in the lockfile + Gradle graph in CI** (BUILD-02 gate).

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `flutter_zxing 2.2.1` | `mobile_scanner` | Faster/smoother, but uses Google ML Kit → **breaks F-Droid** (the whole reason for this stack). Forbidden by BUILD-02. |
| `flutter_zxing 2.2.1` | `flutter_zxing 2.1.0` (keeps minSdk 21) | Avoids the minSdk bump, but the F-Droid-clean line forces minSdk 23 anyway; the team already committed to BUILD-01. 2.2.1 is the current clean line. |
| Pin `^2.2.0` | exact `2.2.1` | Caret would upgrade into the Flutter-3.41-only 2.3.0 and break the build. **Do not use a caret** (BUILD-02 verbatim: "exact-pinned … not a caret"). |

**Installation (pubspec.yaml dependencies block):**
```yaml
flutter_zxing: 2.2.1   # exact pin — NOT ^2.2.0 (2.3.0 needs Flutter >=3.41)
```
*No `flutter pub get` can run locally (toolchain absent). The lockfile is generated/verified in CI.*

**Version verification (already done this session):**
```
pub.dev API /api/packages/flutter_zxing → 2.2.1 env: flutter>=3.3.0, sdk>=3.3.3 <4.0.0 (published 2025-08-10)
```

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `flutter_zxing` | **pub.dev** | published 2.2.1 on 2025-08-10 (1.x line years old) | ~49K/30d | github.com/khoren93/flutter_zxing | **N/A (false positive)** | **Approved** |
| `camera` (transitive) | pub.dev | mature (Flutter-team-adjacent) | very high | flutter/packages | not run (transitive) | Approved — AndroidX, no ML Kit |
| `image_picker` (transitive) | pub.dev | mature | very high | flutter/packages | not run (transitive) | Approved |
| `ffi`, `image` (transitive) | pub.dev | mature | very high | dart-lang / brendan-duncan | not run (transitive) | Approved |

**slopcheck note (important):** `slopcheck install flutter_zxing` returned `[SLOP] Package 'flutter_zxing' does not exist on pypi`. This is a **false positive from an ecosystem mismatch** — slopcheck only checks **PyPI**, and `flutter_zxing` is a **pub.dev (Dart/Flutter)** package, which slopcheck has no registry for. The authoritative verification for pub packages is the **pub.dev API**, which confirms `flutter_zxing` is a real, mature package (full 1.x→2.3.0 version history, 49K downloads/30d, 160/160 pub points, real GitHub source). slopcheck is the wrong tool for this ecosystem and its verdict here must be disregarded. **Disposition: Approved via pub.dev API**, not flagged.

**Packages removed due to slopcheck [SLOP] verdict:** none (the lone [SLOP] is a documented ecosystem-mismatch false positive).
**Packages flagged as suspicious [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram

```
SETUP (alarm editor — main isolate, device unlocked)
  CustomizableListSetting<AlarmTask> "Tasks"  (alarm_settings_schema.dart:297)
        │ user adds AlarmTask(scan)
        ▼
  CustomizeListItemScreen renders task.settings.settingItems
        via getSettingWidgets()   (customize_list_item_screen.dart:53)
        │
        ├─► [Registration card]  ── tap "Scan to register" ──►
        │       Permission.camera (permission_handler)
        │           ├─ denied → AppSettings.openAppSettings() → resume
        │           └─ granted → push ScanRegisterScreen
        │                           ReaderWidget(onScan) → code.text
        │                           normalizeCode(text) ──► StringSetting "Registered Code"
        │                           status display "✓ Code registered"
        │
        └─► [Escape Hatch toggle]  SwitchSetting (default ON)

RING (alarm fires — firing isolate plays audio; UI on MAIN isolate over keyguard)
  AndroidAlarmManager → alarm_isolate → full-screen notification
        │ FlutterShowWhenLocked().show()   (alarm_notifications.dart:182)  ◄── SPIKE SUBJECT
        ▼
  AlarmNotificationScreen (main isolate)
        actionWidget = SlideNotificationAction
            ├─ swipe SNOOZE → onSnooze (pre-task, no scanner)   ◄── SCAN-05
            └─ swipe DISMISS → _setNextWidget()
                    │ volume → alarm.volume * volumeDuringTasks/100
                    ▼
              alarm.tasks[i].builder(_setNextWidget)   (unchanged orchestration)
                    │  for type==scan → ScanTask widget
                    ▼
              ScanTask  (main isolate)
                ReaderWidget(onScan / onScanFailure)
                  ├─ onScan + codesMatch(normalize(text), stored) → onSolve() → next task / dismiss
                  ├─ onScanFailure / non-match → haptic+visual + EscapeHatchController.recordFailedAttempt()
                  ├─ onControllerCreated(_, exception!=null) → EscapeHatchController.fireNow()  ◄── SCAN-07
                  └─ EscapeHatchController fires (≥120s OR ≥N attempts) → show "Dismiss" (Semantics) → onSolve()
                dispose(): ReaderWidget disposes CameraController on every exit  ◄── SCAN-11
```

### Recommended Project Structure (new files; mirror existing layout)
```
lib/alarm/widgets/tasks/scan_task.dart            # ring-time ScanTask widget (mirrors math_task.dart)
lib/alarm/screens/scan_register_screen.dart       # setup registration scanner screen (mirrors try_alarm_task_screen.dart)
lib/alarm/widgets/scan_register_card.dart         # inline "Scan to register" card (mirrors setting_action_card.dart)
lib/alarm/logic/code_match.dart                   # PURE: normalizeCode() + codesMatch()  ← CI-tested seam
lib/alarm/logic/escape_hatch_controller.dart      # PURE: injectable Clock/Timer + callbacks ← CI-tested seam
# edits:
lib/alarm/types/alarm_task.dart                   # add AlarmTaskType.scan
lib/alarm/data/alarm_task_schemas.dart            # register the scan schema
lib/l10n/app_en.arb                               # new strings (SCAN-12)
android/app/build.gradle                          # minSdkVersion 21 → 23 (BUILD-01)
android/app/src/main/AndroidManifest.xml          # CAMERA + uses-feature (SCAN-08)
pubspec.yaml                                       # flutter_zxing: 2.2.1
test/alarm/logic/code_match_test.dart             # PURE seam test
test/alarm/logic/escape_hatch_controller_test.dart# PURE seam test
```

### Pattern 1: New AlarmTask type (drop-in — zero ring-orchestration change)
**What:** Add an enum value, a schema entry whose builder returns the ring widget, done. `_setNextWidget()` iterates `alarm.tasks[i].builder(_setNextWidget)` and dismisses when index ≥ length — it is type-agnostic.
**When to use:** SCAN-01. Confirmed by reading `alarm_task.dart` + `alarm_notification_screen.dart:41-63`.
**Example (schema registration, mirrors the math entry):**
```dart
// Source: lib/alarm/data/alarm_task_schemas.dart (existing pattern, lines 11-47)
AlarmTaskType.scan: AlarmTaskSchema(
  (context) => AppLocalizations.of(context)!.scanTask,
  SettingGroup("Scan Settings",
      (context) => AppLocalizations.of(context)!.scanTask, [
    StringSetting("Registered Code",
        (context) => AppLocalizations.of(context)!.scanRegisteredCode, "",
        isVisual: false),                 // hidden raw value (D-REG-DISPLAY: status only)
    SwitchSetting("Escape Hatch",
        (context) => AppLocalizations.of(context)!.scanEscapeHatch, true), // ON by default (D-ESC)
    // NOTE: the inline "Scan to register" affordance is added as a custom card
    // — see Pattern 2 (it is NOT a plain StringSetting card).
  ]),
  (onSolve, settings) => ScanTask(onSolve: onSolve, settings: settings),
),
```

### Pattern 2: Inline registration card inside the task SettingGroup (D-REG-UI)
**What:** The task's settings page is rendered by `getSettingWidgets(item.settings.settingItems, ...)` in `customize_list_item_screen.dart:53`. Each `SettingItem` is dispatched to a card by `get_setting_widget.dart` (`if (item is X) return XCard(...)`). To host a custom "Scan to register" button + status, the cleanest options:
- **(Recommended) A `CustomSetting<RegisteredCode>`** whose `screenBuilder` returns `ScanRegisterScreen` and whose `valueDisplayBuilder` shows "✓ Code registered" / "Not registered". `CustomSettingCard` already renders a tappable chevron card that pushes `getScreenBuilder(context)` (`custom_setting_card.dart:25-31`). This requires a `fromJsonFactories[RegisteredCode]` entry (`CustomSetting.loadValueFromJson` at `setting.dart:281`) — **the one place a `json_serialize.dart` factory entry IS needed** if you go the `CustomSetting` route. CONTEXT D-STORE-FORMAT says "no factory entry needed" — that holds only if you store via a plain `StringSetting` and add the scan button as a separate card.
- **(Alternative, matches D-STORE-FORMAT literally) A new `ScanRegisterSettingCard`** registered in `get_setting_widget.dart` against a marker setting type, storing into the `StringSetting "Registered Code"`. This keeps the raw value in a plain `StringSetting` (no factory entry) and adds a button card alongside it. Mirror `setting_action_card.dart` (an `InkWell` whose `onTap` runs an action — `setting_action_card.dart:31`).

**Planner's call.** Both are valid; the second honors D-STORE-FORMAT's "no factory entry" exactly. Either way the scan flow is: permission → `ReaderWidget` screen → `normalizeCode(code.text)` → store → pop with status.
**Example (reuse the test-scan-screen precedent):**
```dart
// Source: lib/alarm/screens/try_alarm_task_screen.dart (existing — a Scaffold that
// renders a task widget and pops on solve). ScanRegisterScreen mirrors this:
//   Scaffold(appBar: AppTopBar(), body: ReaderWidget(onScan: (code) { store(code.text); Navigator.pop(); }))
```

### Pattern 3: ReaderWidget result handling (normalized match + failure split)
**What:** `ReaderWidget` fires **`onScan: Function(Code)?`** on a *valid* decode and **`onScanFailure: Function(Code)?`** on a failed/invalid decode. `scanDelay` (default `Duration(milliseconds: 1000)`) rate-limits callbacks. The `Code` result exposes `.text` (String?), `.isValid` (bool), `.format` (int), `.isInverted` (bool).
**Example:**
```dart
// Source: github.com/khoren93/flutter_zxing/blob/main/lib/src/ui/reader_widget.dart
ReaderWidget(
  codeFormat: scanFormats,                 // int bitmask — see Item 2 symbology set
  showFlashlight: true,                    // SCAN-09 torch toggle (built in)
  showToggleCamera: false,                 // single rear camera (D discretion)
  showGallery: false,                      // ring-time: live camera only
  scanDelay: const Duration(milliseconds: 1000),       // built-in debounce
  scanDelaySuccess: const Duration(milliseconds: 1000),
  onControllerCreated: (controller, exception) {
    if (exception != null) escapeHatch.fireNow();      // SCAN-07 camera-unavailable
  },
  onScan: (Code code) async {
    if (codesMatch(normalizeCode(code.text), storedNormalized)) {
      onSolve();                                        // dismiss this task
    } else {
      vibrate(); showWrongCodeFeedback();
      escapeHatch.recordFailedAttempt();               // D-RING-WRONGSCAN
    }
  },
  onScanFailure: (Code code) { /* optional: usually ignore — no-decode frames */ },
)
```

### Anti-Patterns to Avoid
- **Putting camera lifecycle in the firing isolate:** The firing isolate (`alarm_isolate.dart`) has no FlutterEngine/UI — `ReaderWidget` cannot run there. Camera MUST be in the main-isolate `AlarmNotificationScreen` task widget. (ARCHITECTURE.md constraint.)
- **Counting raw decode callbacks as "failed attempts":** ZXing emits many reads/sec; raw counting trips the escape hatch in milliseconds. Debounce via `scanDelay` (≥1/sec) AND/OR only count *distinct non-matching payloads* (D-ESC-DEFAULT).
- **Logging the decoded payload:** D-REG-DISPLAY / privacy — never `logger.*(code.text)`. (Also remove the pre-existing `print(setting.value)` leak at `dynamic_toggle_setting_card.dart:39` if you touch settings-card code — STATE.md todo.)
- **Using a caret `^2.2.0`:** would upgrade into Flutter-3.41-only 2.3.0. Exact pin only.
- **Not disposing the camera on background:** stuck privacy indicator (SCAN-11). Rely on `ReaderWidget.dispose()` and verify the widget is actually removed from the tree on every exit path (success, escape, app background).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Barcode/QR decode | A custom decoder | `flutter_zxing` `ReaderWidget` | Native ZXing C++; handles 18 symbologies, rotation, inversion, crop. |
| Camera preview + lifecycle | Raw `camera` plugin wiring | `ReaderWidget` (wraps `camera`) | Already handles init, AppLifecycle pause/resume, dispose, torch, overlay. |
| Scan-rate debounce | A manual throttle timer | `ReaderWidget.scanDelay` (default 1000ms) | Built-in; the exact mechanism that makes "failed attempts" countable (Item 3). |
| Over-lock window | New manifest flags / native activity | `FlutterShowWhenLocked().show()` (already wired at `alarm_notifications.dart:182`) | The ring screen already opens it; the scan preview inherits it. |
| Camera permission UX | Custom permission dialog | `permission_handler` + `app_settings` deep-link | Both already deps; mirror `permissions.dart` + `general_settings_schema.dart:344`. |
| Settings persistence | New storage path | `StringSetting` in the task `SettingGroup` | Rides inline alarm JSON; no new persistence (D-STORE-FORMAT). |

**Key insight:** Almost the entire feature is *assembly of existing seams*. The only genuinely new code is two tiny pure functions/controllers (normalize/match, escape-hatch timing) and three thin widgets (ring task, register screen, register card). The risk is concentrated in ONE place doc-reading can't cover: the camera-over-secure-keyguard spike.

## Common Pitfalls

### Pitfall 1: Camera not released → stuck privacy indicator (SCAN-11)
**What goes wrong:** Green camera dot / privacy indicator stays on after dismiss/escape/background.
**Why it happens:** `ReaderWidget` only fully disposes the `CameraController` in `dispose()`; on pause/inactive/hidden it merely **stops the stream** (controller not disposed). If the widget isn't actually removed from the tree on an exit path, the controller lingers.
**How to avoid:** Ensure every exit path (match→`onSolve`, escape-fire→`onSolve`, app→background) removes `ScanTask` from the tree so Flutter calls `dispose()`. On `AppLifecycleState.paused`, the stream stops (good) but verify on-device the indicator clears. Add a defensive explicit controller stop on escape-fire if you keep a controller reference via `onControllerCreated`.
**Warning signs:** Privacy dot persists after the alarm screen closes; second alarm's scanner fails to acquire the camera ("camera in use").

### Pitfall 2: Escape hatch trips instantly (Item 3)
**What goes wrong:** "Plain dismiss" appears within a second of the scanner opening.
**Why it happens:** Counting every `onScan`/decode frame as an attempt (many/sec).
**How to avoid:** Debounce — `scanDelay: 1000ms` caps callback rate; in `EscapeHatchController` only count a failed attempt on a *non-matching valid decode* (not no-decode frames, not the matching one), optionally de-duplicating identical consecutive payloads. Default ~10 attempts OR ~120s elapsed (D-ESC-DEFAULT).
**Warning signs:** Escape button shows almost immediately; attempt counter races up while pointing at a wrong code.

### Pitfall 3: `camera`/`image_picker` transitive deps pull a non-FOSS artifact (BUILD-02)
**What goes wrong:** The F-Droid `prod` build fails the zero-ML-Kit gate because a transitive dep injects `play-services`/`mlkit`.
**Why it happens:** `flutter_zxing` depends on `camera: >=0.10.5 <0.12.0`; the resolved version's Android impl + any other plugin could (in theory) pull Play Services. On Flutter 3.22.2, `camera` resolves to a 3.22-compatible line whose Android impl is `camera_android` (Camera2) or a compatible `camera_android_camerax` — both AndroidX, **no ML Kit** (verified: `camera_android` deps = `flutter_plugin_android_lifecycle`, `stream_transform`, `camera_platform_interface` only).
**How to avoid:** After `flutter pub get` in CI, run the BUILD-02 gate (below) and inspect `pubspec.lock` for the resolved `camera`/`camera_android*` versions. This is a **CI gate**, not a local check (toolchain absent).
**Warning signs:** `./gradlew :app:dependencies` output contains `com.google.android.gms`, `play-services`, or `mlkit`.

### Pitfall 4: NDK / CMake version mismatch on the native build (BUILD-01/02)
**What goes wrong:** Gradle native build fails or warns on NDK version.
**Why it happens:** `flutter_zxing 2.2.1`'s `android/build.gradle` declares `ndkVersion "27.0.12077973"` and an `externalNativeBuild` CMake (`../src/CMakeLists.txt`); the consuming app uses `ndkVersion flutter.ndkVersion` (`android/app/build.gradle:38`). Mismatched NDK across modules triggers Gradle's "module X requests NDK 27, app uses Y" error in newer AGP.
**How to avoid:** Let Flutter manage the NDK; if Gradle complains, set the app's `ndkVersion` to the highest requested (27.0.12077973) in `android/app/build.gradle`. CMake comes from the Android SDK; the F-Droid/CI builder must have NDK + CMake available (CI `test-apk.yml` / a build job).
**Warning signs:** "NDK version X did not match" or "CMake not found" in the Gradle log. **Flag:** this only surfaces in a real native build — neither `flutter analyze` nor headless `flutter test` exercises it. The dev APK build (`test-apk.yml`) is the earliest gate that compiles native code.

### Pitfall 5: `onScan` silently never fires on some OEMs
**What goes wrong:** Camera preview shows but codes never decode (reported on Xiaomi Poco M3, flutter_zxing issue #114).
**Why it happens:** Device-specific camera stream/format quirks in the underlying `camera` plugin.
**How to avoid:** Fold a "does it actually decode?" check into the lock-screen spike's OEM matrix (it's the same camera path). The escape hatch is the safety net if a specific OEM can't decode at all.
**Warning signs:** Preview renders, no `onScan` ever called even on a known-good QR.

## Runtime State Inventory

> This is a **greenfield feature add**, not a rename/refactor/migration. No existing stored string is being renamed. The only new persisted state is the registered-code `StringSetting`, written fresh.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — new `StringSetting "Registered Code"` is written fresh into the task `SettingGroup` (inline alarm JSON). Existing alarms without a scan task are unaffected. | none |
| Live service config | None — no external service stores any phase-4 string. | none |
| OS-registered state | New `CAMERA` permission + `uses-feature` in the manifest (additive). No task-scheduler/launchd-style registration involved. | manifest edit only |
| Secrets/env vars | None. | none |
| Build artifacts | minSdk bump (21→23) + new native ZXing `.so` libs from `flutter_zxing` CMake build. A clean CI build regenerates these; no stale artifact migration. The `alarmSchemaVersion` (currently 5, `alarm_settings_schema.dart:31`) does **not** need bumping for an additive task type (tasks load via `fromJson` and default-construct unknown types). | clean CI build |

**Nothing found in the rename/migration categories** — verified by: this phase adds a new task type and new settings keys; it renames nothing and migrates no existing records.

## Code Examples

### Pure normalize + match seam (CI-testable; SCAN-03 / D-MATCH-NORMALIZE)
```dart
// lib/alarm/logic/code_match.dart  — dependency-free, no camera/UI.
// Normalize BOTH sides identically (trim / strip control chars / case-fold)
// so a trailing newline or case diff can never false-reject.
String normalizeCode(String? raw) {
  if (raw == null) return '';
  // Strip ASCII control chars (incl. trailing \n, \r, \t, \0), trim, lower-case.
  final stripped = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  return stripped.trim().toLowerCase();
}

bool codesMatch(String scannedNormalized, String storedNormalized) {
  if (storedNormalized.isEmpty) return false;   // never match an unregistered task
  return scannedNormalized == storedNormalized;
}
```
*Decision needed (Open Question O1): is case-folding desired? Barcodes are usually case-insensitive ASCII; QR payloads can be case-significant URLs. Recommendation: case-fold for v1 (matches Alarmy's lenient behavior; reduces false rejects), flag to user at discuss-phase. The normalize step is applied at BOTH register and compare, so it is internally consistent either way.*

### Pure escape-hatch controller seam (CI-testable; SCAN-06/07 / D-ESC)
```dart
// lib/alarm/logic/escape_hatch_controller.dart — injectable Clock + Timer,
// mirrors Phase-3 VolumeRampController (single owned Timer + callback).
class EscapeHatchController {
  EscapeHatchController({
    required this.onEscapeAvailable,     // callback → UI shows "Dismiss"
    this.maxFailedAttempts = 10,         // D-ESC-DEFAULT (conservative)
    this.elapsedThreshold = const Duration(seconds: 120),
    this.enabled = true,                 // SwitchSetting "Escape Hatch"
  });
  final VoidCallback onEscapeAvailable;
  final int maxFailedAttempts;
  final Duration elapsedThreshold;
  final bool enabled;

  int _attempts = 0;
  Timer? _timer;
  bool _fired = false;

  void start() {                          // call when scanner opens
    if (!enabled) return;
    _timer = Timer(elapsedThreshold, _fire);   // time branch (D-ESC-TRIGGER)
  }
  void recordFailedAttempt() {            // call ONLY on a non-matching valid decode
    if (!enabled) return;
    _attempts++;
    if (_attempts >= maxFailedAttempts) _fire();   // attempts branch
  }
  void fireNow() => _fire();              // camera-denied / camera-unavailable (SCAN-07)
  void _fire() {
    if (_fired) return;
    _fired = true;
    onEscapeAvailable();
  }
  void dispose() => _timer?.cancel();
}
```
*Tested under `fake_async` / `withClock(Clock.fixed(...))` exactly like `volume_ramp_controller_test.dart` and `alarm_snooze_test.dart` — no camera, no real time.*

### Symbology set (SCAN-04 / D discretion)
```dart
// Broad set per CONTEXT (QR + common 1D + DataMatrix). Format is a bitmask.
// Source: github.com/khoren93/flutter_zxing format.dart (bit-shift constants).
final int scanFormats = Format.qrCode | Format.dataMatrix |
    Format.ean8 | Format.ean13 | Format.upca | Format.upce |
    Format.code128 | Format.code39 | Format.itf;
// Simpler alternative if spurious reads are NOT a concern: codeFormat: Format.any (default).
// Narrow to Format.qrCode-only if 1D false-reads surface in testing (SCAN-04 escape clause).
```

### Manifest additions (SCAN-08)
```xml
<!-- android/app/src/main/AndroidManifest.xml — add alongside existing uses-permission -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
<uses-feature android:name="android.hardware.camera.flash" android:required="false" />
<!-- required="false" so the Play listing isn't camera-gated (Alarmy's manifest uses this exact shape). -->
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ML Kit scanners (`mobile_scanner`) for QR | Native ZXing FFI (`flutter_zxing`) for FOSS apps | ongoing | The ONLY path that keeps F-Droid distribution; ML Kit is a proprietary blob. |
| `flutter_zxing 2.1.0` (minSdk 21) | `flutter_zxing 2.2.1` (minSdk 23) | 2025-08 | The clean line moved to minSdk 23 → forces BUILD-01. |
| `camera_android` (Camera2) | `camera_android_camerax` (CameraX) on newer `camera` | 2024-25 (camera 0.11) | On Flutter 3.22.2 the solver stays on a 3.22-compatible line; either Android impl is FOSS-clean. Confirm in lockfile. |

**Deprecated/outdated:**
- `flutter_zxing 2.3.0`: requires Flutter ≥3.41 — **unusable** on Chrono's 3.22.2 until a Flutter upgrade. Do not pin to it or to a caret that reaches it.

## Validation Architecture

> `workflow.nyquist_validation` not set to false in config → section included. All commands below are **CI (GitHub Actions) or on-device gates** — the dev machine has no Flutter/Dart/Android SDK.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (SDK built-in) + `clock` (`withClock`) + `fake_async` (transitive, already used) |
| Config file | none beyond `pubspec.yaml`; tests in `test/` mirror `lib/` |
| Quick run command | `flutter test test/alarm/logic/` — **CI gate (`tests.yml`)**, not local |
| Full suite command | `flutter test --coverage` — **CI gate (`tests.yml`)** |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command (CI) | File Exists? |
|--------|----------|-----------|------------------------|-------------|
| SCAN-03 | trailing-newline / case / control-char does NOT false-reject; wrong code does not match; empty stored never matches | unit (pure) | `flutter test test/alarm/logic/code_match_test.dart` | ❌ Wave 0 |
| SCAN-06 | escape fires at ≥120s (time branch) and at ≥N attempts (attempt branch); disabled toggle never fires | unit (pure, `fake_async`/`withClock`) | `flutter test test/alarm/logic/escape_hatch_controller_test.dart` | ❌ Wave 0 |
| SCAN-07 | `fireNow()` (cam-denied/unavailable) fires immediately and only once | unit (pure) | same file as SCAN-06 | ❌ Wave 0 |
| SCAN-01 | `AlarmTask(scan)` round-trips through `toJson`/`fromJson`; schema present in map | unit | `flutter test test/alarm/types/` (extend) | ❌ Wave 0 |
| SCAN-09 / SCAN-11 | torch toggle, camera dispose, over-lock preview | **on-device only** | manual — no CI substitute (real camera/keyguard) | n/a |
| BUILD-01/02 | minSdk 23; zero ML Kit in Gradle graph; native build compiles | **CI build gate** | see commands below | n/a |

### Sampling Rate
- **Per task commit:** `flutter test test/alarm/logic/` (the two pure seams — sub-second, CI).
- **Per wave merge:** `flutter test --coverage` (full suite, CI `tests.yml`).
- **Phase gate:** full suite green in CI + the dev-APK native build green (`test-apk.yml`) + the on-device spike + on-device SCAN-09/11 checks signed off.

### BUILD-02 zero-ML-Kit gate (CI command, NOT local)
```bash
# Run in GitHub Actions after `flutter pub get`, in the android/ dir:
cd android && ./gradlew :app:dependencies --configuration prodReleaseRuntimeClasspath \
  | grep -Ei 'mlkit|play-services|gms' && echo "FAIL: non-FOSS dep present" || echo "PASS: zero ML Kit"
# Expect: PASS (no matches). Targets the prod (F-Droid) flavor's release classpath.
```
*This requires the Android SDK + a network fetch — route it to GitHub Actions (extend `test-apk.yml` or a new job). It cannot run on the dev machine.*

### Wave 0 Gaps
- [ ] `test/alarm/logic/code_match_test.dart` — covers SCAN-03 (normalize/match edge cases).
- [ ] `test/alarm/logic/escape_hatch_controller_test.dart` — covers SCAN-06/07 (time + attempt + cam-fail branches; disabled).
- [ ] `lib/alarm/logic/code_match.dart` + `lib/alarm/logic/escape_hatch_controller.dart` — the seams under test must exist first.
- [ ] (Optional) extend `test/alarm/types/` for `AlarmTask(scan)` JSON round-trip.
- [ ] **Infra flag:** no emulator / `integration_test` job exists. A live-camera-over-keyguard test is NOT automatable in CI without a camera-equipped device farm — adding `reactivecircus/android-emulator-runner` would still not give a *secure keyguard + real camera*. **Recommendation: do NOT add an emulator job for this; keep SCAN-09/11 + the spike as documented on-device gates.** Flag explicitly to the user.

## Security Domain

> `security_enforcement` not explicitly false → included. This feature adds a camera capability and stores a user-provided code.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | The scan is an alarm-dismiss gate, not an auth boundary. |
| V3 Session Management | no | — |
| V4 Access Control | partial | The escape hatch is a deliberate, mandatory bypass (anti-trap). Not a security control — an accessibility/safety one. |
| V5 Input Validation | yes | Decoded `code.text` is treated as an opaque string — normalized, compared, never `eval`'d, never used to build a query/path/intent. No injection surface. |
| V6 Cryptography | no | Raw string stored (D-STORE-FORMAT, chosen over hash deliberately for v2 label support). Not a secret — it's a physical code the user can re-scan. No crypto needed. |
| V7 Error/Logging | yes | **Never log the decoded payload** (privacy). Remove the existing `print(setting.value)` at `dynamic_toggle_setting_card.dart:39` if touched. |
| V8 Data Protection | yes | Registered code persists in app-private storage (existing JSON path). Privacy indicator must clear on camera release (SCAN-11). |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Camera left active after exit (privacy leak) | Information Disclosure | `ReaderWidget.dispose()` on every exit path (SCAN-11; Pitfall 1). |
| Decoded payload written to logs | Information Disclosure | No `logger`/`print` of `code.text`; status-only display. |
| Un-dismissable alarm (user trapped) | Denial of Service (against the user) | Default-ON escape hatch + instant fire on cam-denied/unavailable (SCAN-07). The ethics-critical control. |
| Malicious QR payload | Tampering/Injection | Payload is compared as an opaque string only; never executed/parsed into an action. |
| Non-FOSS blob via transitive dep | (supply-chain) | BUILD-02 Gradle-graph gate in CI; exact pin. |

## Environment Availability

| Dependency | Required By | Available (dev machine) | Version | Fallback |
|------------|------------|------------|---------|----------|
| Flutter/Dart SDK | all build/test | ✗ | — | CI (`tests.yml`, `test-apk.yml`) is the authoritative gate |
| Android SDK + NDK 27 + CMake | native ZXing build (BUILD-01/02) | ✗ | — | GitHub Actions build job (`test-apk.yml` builds the dev APK; extend for the prod-flavor dep gate) |
| `flutter_zxing 2.2.1` | scanner | n/a (pub) — verified via pub.dev API | 2.2.1 | none — it's the only FOSS-clean option |
| ≥2 physical Android devices w/ secure keyguard + camera, different OEMs | lock-screen spike (criterion #1) | ✗ (user-provided) | — | **No fallback — the spike is inherently on-device.** Unlock-then-scan is the product fallback if the spike is no-go, but the *spike itself* needs real devices. |

**Missing dependencies with no fallback:**
- The ≥2-OEM physical device spike (criterion #1) — cannot be simulated; it is the one true on-device unknown.

**Missing dependencies with fallback:**
- Flutter/Android toolchain → CI (all builds/tests/dep-audits route to GitHub Actions).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | On Flutter 3.22.2 the solver resolves `camera` to a FOSS-clean Android impl (no ML Kit/Play Services) | Standard Stack / Pitfall 3 | If a transitive dep DID pull Play Services, BUILD-02 fails. **Mitigated:** the CI Gradle-graph gate catches it deterministically before merge. The risk is low (`camera`/`image_picker` Android impls are AndroidX), but it is `[ASSUMED]` until the CI gate runs. |
| A2 | `flutter_zxing 2.2.1` native build (NDK 27 + CMake) compiles cleanly under Chrono's Gradle 7.6.4 / AGP toolchain after the minSdk bump | Pitfall 4 / Standard Stack | Native build could fail on NDK/AGP/CMake mismatch. **Mitigated:** the dev-APK CI build is the first real compile gate; fixable by aligning `ndkVersion`. `[ASSUMED]` until a native build runs in CI. |
| A3 | Case-folding in `normalizeCode` is the desired default (vs case-sensitive) | Code Examples / O1 | Could false-*accept* two codes differing only by case (rare for physical codes). Low risk; confirm at discuss-phase. |
| A4 | `ReaderWidget.dispose()` reliably clears the OS privacy indicator on every OEM | Pitfall 1 / SCAN-11 | Some OEM could lag the indicator. On-device check (SCAN-11) confirms; defensive explicit controller-stop on escape recommended. |
| A5 | The `showWhenLocked` over-lock window permits a live camera preview over a SECURE keyguard | Item 1 / spike | **This is THE unknown.** If false on an OEM → unlock-then-scan fallback (D-LOCK-NOGO-UX). Resolved only by the spike. |

## Open Questions

1. **Case-sensitivity of code matching (O1).**
   - What we know: Physical 1D/QR codes are usually case-insensitive ASCII; the normalize step is applied identically at register and compare, so it's internally consistent.
   - What's unclear: Whether any target user registers a case-significant payload (e.g. a URL QR).
   - Recommendation: Case-fold for v1 (fewer false rejects, matches Alarmy). Surface at discuss-phase; trivially reversible (one line in `normalizeCode`).

2. **Registration card route: `CustomSetting` vs new card type (O2).**
   - What we know: Both work; `CustomSetting` reuses `CustomSettingCard` but needs a `fromJsonFactories` entry (contradicting D-STORE-FORMAT's "no factory entry"); a new `ScanRegisterSettingCard` + plain `StringSetting` honors D-STORE-FORMAT exactly.
   - What's unclear: Team preference for one more factory entry vs one more card type in the `get_setting_widget` dispatch.
   - Recommendation: Planner's call (CONTEXT explicitly leaves wrapper-vs-direct to the planner). The `StringSetting` + custom button-card route is marginally cleaner re: D-STORE-FORMAT.

3. **Does `_setNextWidget`'s `volumeDuringTasks` lowering interfere with hearing wrong-scan haptic feedback? (O3)**
   - What we know: Volume auto-lowers to `volumeDuringTasks` during any task; haptics are independent of audio volume.
   - What's unclear: Nothing blocking — noted for completeness.
   - Recommendation: No action; haptic (`vibration`) is the primary wrong-scan signal, independent of volume.

## The Lock-Screen Camera Spike (Item 1 — first plan, discrete go/no-go)

> This is the milestone's biggest unknown and **must be the FIRST plan**, executed and decided BEFORE the scan-task UI is committed (ROADMAP criterion #1, D-LOCK-SPIKE-SCOPE).

**Why no doc can answer it:** Chrono opens the over-lock window with a **runtime native call** `FlutterShowWhenLocked().show()` (`alarm_notifications.dart:182`), not a manifest `android:showWhenLocked` attribute (the manifest has none — verified). Whether a CameraX/Camera2 preview surface composites and *decodes* inside that window over a **secure (PIN/pattern)** keyguard is OEM/Android-version dependent and observable only on real hardware. (Some OEMs blank camera surfaces over a secure keyguard for privacy.)

**Minimal spike scaffold (throwaway — do NOT build the full task UI yet):**
1. Add `flutter_zxing: 2.2.1` + bump `minSdkVersion 23` + add `CAMERA` manifest perms (these are needed regardless; BUILD-01/02/SCAN-08).
2. Add a temporary debug entry that, on a *fired alarm* (real over-lock path via the existing notification → `AlarmNotificationScreen`), renders a bare `ReaderWidget(onScan: (c) => debugPrint('DECODED'))` in place of the action widget — i.e. exercise the SAME `FlutterShowWhenLocked().show()` window the real feature will use. (Reusing the real ring path is essential — a normal in-app screen does NOT reproduce the keyguard condition.)
3. Lock the device with a **secure** PIN/pattern. Fire the alarm. Observe.

**Decision matrix (document per device):**
| Observation over SECURE keyguard | Verdict |
|----------------------------------|---------|
| Live preview renders AND `onScan` decodes a test code | **GO** — build full scan UI on the `showWhenLocked` path. |
| Black/blank/frozen preview (no frames) | **NO-GO** → unlock-then-scan fallback (D-LOCK-NOGO-UX): show "unlock to scan" prompt over keyguard, open scanner after unlock, alarm keeps ringing, escape hatch underneath. |
| Preview renders but `onScan` never fires (cf. issue #114) | **REQUIRES-INVESTIGATION** — device-specific decode failure; escape hatch covers it; treat as no-go for that OEM. |

**OEM matrix (≥2 required, more is better):** pick 2+ distinct vendors (e.g. Pixel/AOSP + Samsung OneUI + Xiaomi/MIUI if available — MIUI is the most aggressive over-lock restrictor and surfaced #114). Record Android version + OEM skin per row.

**Ship gate:** Per D-LOCK-SHIP, the feature ships regardless of outcome — go-devices use direct over-lock scan; no-go devices degrade to unlock-then-scan. The escape hatch guarantees no alarm is ever un-dismissable on any device. The spike's job is to decide which *primary* path each device class gets, not whether to ship.

**Deferred fallback (NOT in this phase):** Alarmy's `SYSTEM_ALERT_WINDOW` overlay + `DISABLE_KEYGUARD` + runtime keyguard-dismiss. Hold as the secondary recovery path only if the `showWhenLocked` spike is broadly no-go and recovering those OEMs is judged worth it later.

## Project Constraints (from CLAUDE.md)

- **No state-management library** — `setState` + `SettingGroup` + `ListenerManager` only. The escape-hatch controller is a plain Dart object wired via callbacks, not a Provider/Bloc.
- **Camera lifecycle in the main isolate / notification screen, NEVER the firing isolate.** (ARCHITECTURE.md + CLAUDE.md.)
- **F-Droid FOSS-clean** — zero `mlkit`/`gms`/`play-services` in the prod Gradle graph (BUILD-02). Verified via CI Gradle-graph gate.
- **Testing Policy:** maximize CI-runnable tests; extract pure seams (normalize/match, escape-hatch controller) and unit-test them headlessly. Camera/lock-screen/torch are the only legitimate on-device-only gates. **No emulator/integration_test job exists — adding one is a separate deferrable decision; this phase recommends NOT adding it** (a secure-keyguard + real-camera condition isn't reproducible in an emulator job anyway).
- **Local toolchain absent** — never report `flutter test`/`analyze`/`gen-l10n`/`./gradlew` as locally passing. CI is the authoritative gate.
- **No `Co-Authored-By: Claude` trailer**; commit as the global git author (user's global CLAUDE.md).
- **minSdk 23, compileSdk 34, Kotlin 1.8, Java 17, Dart 3.4+/Flutter 3.22.x** — new dep (`flutter_zxing 2.2.1`) is compatible (verified).
- **Snake_case Dart filenames; UpperCamelCase classes; `toJson`/`fromJson`; `logger.t/i/e/f`** — new files follow CONVENTIONS.md.

## Sources

### Primary (HIGH confidence)
- **pub.dev API** `https://pub.dev/api/packages/flutter_zxing` (+ `/score`) — version list with SDK constraints & publish dates, dependency tree, popularity. Authoritative for the 2.2.1 pin and FOSS deps. [VERIFIED]
- **github.com/khoren93/flutter_zxing** `android/build.gradle` — `minSdkVersion 23`, NDK 27.0.12077973, CMake `../src/CMakeLists.txt`, zero gms/mlkit. [VERIFIED]
- **github.com/khoren93/flutter_zxing** `lib/src/ui/reader_widget.dart`, `lib/src/models/code.dart`, `lib/src/models/format.dart` — `ReaderWidget` constructor params/defaults, `onScan`/`onScanFailure`/`onControllerCreated` signatures, dispose lifecycle, `Code` fields, `Format` bitmask constants. [VERIFIED]
- **Chrono codebase** (read this session): `alarm_task.dart`, `alarm_task_schemas.dart`, `alarm_notification_screen.dart` (`_setNextWidget`), `alarm_settings_schema.dart` (`CustomizableListSetting<AlarmTask>`), `setting.dart` (`StringSetting`/`CustomSetting`/`Setting` base), `custom_setting_card.dart`, `setting_action_card.dart`, `get_setting_widget.dart`, `customize_list_item_screen.dart`, `try_alarm_task_screen.dart`, `permissions.dart`, `general_settings_schema.dart` (app_settings), `alarm_notifications.dart` (`FlutterShowWhenLocked().show()`), `AndroidManifest.xml`, `android/app/build.gradle`, `test/alarm/types/alarm_snooze_test.dart`. [VERIFIED]

### Secondary (MEDIUM confidence)
- pub.dev `camera_android` / `camera_android_camerax` dependency listings (transitive FOSS check) [VERIFIED via API].
- flutter_zxing GitHub issue #114 (onScan not firing on Xiaomi Poco M3) — device-specific decode-failure precedent [CITED].

### Tertiary (LOW confidence)
- General Flutter camera-permission articles (WebSearch) — not load-bearing; manifest shape confirmed from the project + flutter_zxing example instead.

## Metadata

**Confidence breakdown:**
- Standard stack / exact pin (2.2.1): **HIGH** — pub.dev API authoritative; SDK-constraint incompatibility of 2.3.0 is decisive.
- ReaderWidget API / Code / Format: **HIGH** — read from plugin source.
- Codebase seams (task framework, registration card, ring orchestration): **HIGH** — line-level confirmed in source.
- Escape-hatch debounce mechanism: **HIGH** — `scanDelay` default 1000ms + `onScan`/`onScanFailure` split confirmed in source.
- BUILD-02 transitive cleanliness: **MEDIUM** — plugin build is provably clean; the `camera` transitive resolution is FOSS by inspection but must be confirmed by the CI Gradle gate on the actual lockfile (A1).
- Native build (NDK/CMake) success: **MEDIUM** — declared config is standard but only a real CI native build proves it compiles (A2).
- Lock-screen camera over secure keyguard: **LOW (by nature)** — genuine on-device unknown; the spike resolves it (A5).

**Research date:** 2026-06-05
**Valid until:** ~2026-09-05 (90 days) — `flutter_zxing` 2.x line is stable; the pin is frozen against a known-incompatible 2.3.0, so this won't drift unless Chrono upgrades Flutter past 3.41 (then revisit the pin).

## RESEARCH COMPLETE

**Phase:** 4 - QR/Barcode Scan-to-Dismiss Task
**Confidence:** HIGH (with one inherent on-device unknown: the lock-screen camera spike)

### Key Findings
- **Exact pin resolved: `flutter_zxing: 2.2.1`** (not a caret). 2.3.0 needs Flutter ≥3.41 (incompatible); the plugin's own `android/build.gradle` forces `minSdkVersion 23` — that, not a product preference, is the real driver of BUILD-01.
- **Escape-hatch debounce is free:** `ReaderWidget.scanDelay` (default 1000ms) rate-limits callbacks, and `onScan`/`onScanFailure`/`onControllerCreated` cleanly separate match / non-match / camera-failure. Recommended default: ≥120s OR ≥10 *distinct non-matching* attempts; cam-denied/unavailable fires instantly.
- **Feature is mostly assembly of existing seams:** new `AlarmTaskType.scan` + schema + a `ScanTask` ring widget (mirrors `math_task.dart`) + an inline registration card (mirrors `setting_action_card.dart`/`CustomSettingCard`) — `_setNextWidget()` ring orchestration needs **zero** change (line-confirmed). Two pure CI-testable seams: `normalizeCode`/`codesMatch` and `EscapeHatchController` (injectable `Clock`/`Timer`, mirrors Phase-3 `VolumeRampController`).
- **Over-lock is a runtime call, not a manifest flag:** `FlutterShowWhenLocked().show()` already runs for every ring (`alarm_notifications.dart:182`) — the spike must reuse the REAL ring path on a SECURE keyguard across ≥2 OEMs; an in-app screen won't reproduce it. Ship-regardless: the default-ON escape hatch is the universal safety net.
- **BUILD-02 cleanliness:** the plugin build has zero gms/mlkit; the only transitive risk is `camera`/`image_picker`, which resolve to AndroidX (Camera2/CameraX) on Flutter 3.22.2 — confirm with the CI `./gradlew :app:dependencies` gate on the prod flavor.

### File Created
`.planning/phases/04-qr-barcode-scan-to-dismiss-task/04-RESEARCH.md`

### Confidence Assessment
| Area | Level | Reason |
|------|-------|--------|
| Standard Stack (2.2.1 pin) | HIGH | pub.dev API authoritative; 2.3.0 SDK-incompat decisive |
| Architecture / seams | HIGH | Line-level confirmed in Chrono source |
| Pitfalls / escape debounce | HIGH | ReaderWidget API read from source |
| BUILD-02 transitive cleanliness | MEDIUM | Provable at plugin level; CI Gradle gate must confirm the lockfile (A1) |
| Native NDK/CMake build | MEDIUM | Standard config; only a real CI build proves it (A2) |
| Lock-screen camera over secure keyguard | LOW (inherent) | On-device unknown — the spike resolves it (A5) |

### Open Questions
1. Case-sensitivity of matching (recommend case-fold for v1) — discuss-phase.
2. Registration card: `CustomSetting` vs new card type — planner's call (CONTEXT defers it).
3. Whether to add an emulator/integration_test CI job — recommend NO (can't reproduce secure-keyguard+camera; keep on-device gates).

### Ready for Planning
Research complete. The planner can sequence: **Plan 1 = lock-screen spike (first, discrete go/no-go)** → Plan 2 = build gate (pin + minSdk + manifest + zero-ML-Kit CI verify) → Plan 3 = pure seams + tests → Plan 4 = registration card + ScanTask ring widget + l10n. All requirement IDs (BUILD-01/02, SCAN-01..12) are mapped to concrete, decision-complete support above.
