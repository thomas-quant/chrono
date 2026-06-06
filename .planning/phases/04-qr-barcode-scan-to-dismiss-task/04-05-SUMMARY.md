---
phase: 04-qr-barcode-scan-to-dismiss-task
plan: 05
subsystem: scan-task-setup-registration
tags: [scan, qr, barcode, registration, camera-permission, save-gate, settings-card, privacy, a11y, l10n, ci]
requires:
  - "Plan 04-04: AlarmTaskType.scan + scan schema (hidden 'Registered Code' StringSetting isVisual:false + Escape Hatch) — the SettingGroup this plan mounts the card into"
  - "Plan 04-02 pure seam: normalizeCode (code_match.dart) — reused (NOT reimplemented) to normalize-before-store and to test save-gate emptiness identically to ring-time compare"
  - "Plan 04-01: flutter_zxing 2.2.1 ReaderWidget + CAMERA manifest — so the register screen compiles in CI and the runtime camera request is meaningful"
provides:
  - "Inline 'Scan to register' card (ScanRegisterCard) inside the scan task SettingGroup: requests camera at SETUP (SCAN-08), pushes the register scanner on grant, deep-links to settings on denial then resumes (D-REG-CAMDENIED), shows status only (D-REG-DISPLAY), renders scanCodeRequired inline while empty"
  - "Registration scanner screen (ScanRegisterScreen): ReaderWidget -> normalizeCode(code.text) -> store into StringSetting -> pop. Registration IS the test scan (SCAN-02/10/D-REG-TEST)"
  - "REAL save gate (D-REG-REQUIRED): CustomizableListItem.validate() default-no-op + AlarmTask.validate() override (scanCodeRequired when empty) + CustomizeScreen Save block with announced error — a code-less scan task cannot be saved (T-04-20)"
  - "print(setting.value) payload leak removed from dynamic_toggle_setting_card.dart (T-04-13)"
affects:
  - "Plan 04-06 (on-device checkpoint): verifies the REAL camera-permission grant/deny flow, real register scan, camera release, and the real Save block on device"
tech-stack:
  added: []
  patterns:
    - "Route B (D-STORE-FORMAT): a tiny non-persisted marker SettingItem (ScanRegisterSetting) dispatched in get_setting_widget.dart to a custom card over the sibling plain StringSetting — NO json_serialize.dart factory entry (the CustomSetting route A would have needed one)"
    - "Card mirrors setting_action_card.dart (CardContainer/InkWell/Row[title+status, chevron]) + custom_setting_card.dart await-push-then-setState refresh idiom"
    - "Camera permission requested at SETUP only via permissions.dart status/request idiom with Permission.camera; AppSettings.openAppSettings() deep-link precedent (general_settings_schema.dart)"
    - "Save-gate seam: default-no-op base method on CustomizableListItem + targeted override on AlarmTask + single enforcement point at the one CustomizeScreen Save button (threaded through CustomizeListItemScreen) — every other item unaffected"
key-files:
  created:
    - "lib/alarm/screens/scan_register_screen.dart"
    - "lib/alarm/widgets/scan_register_card.dart"
    - "lib/settings/types/scan_register_setting.dart"
  modified:
    - "lib/settings/widgets/dynamic_toggle_setting_card.dart"
    - "lib/alarm/data/alarm_task_schemas.dart"
    - "lib/settings/logic/get_setting_widget.dart"
    - "lib/common/types/list_item.dart"
    - "lib/alarm/types/alarm_task.dart"
    - "lib/common/widgets/customize_screen.dart"
    - "lib/common/widgets/list/customize_list_item_screen.dart"
decisions:
  - "Marker type = a NEW tiny ScanRegisterSetting class (not a reused SettingAction). Rationale: SettingAction dispatches to SettingActionCard (the wrong widget); a dedicated marker makes the get_setting_widget dispatch branch unambiguous. It carries no persisted value (valueToJson -> null), so route B is honored and no fromJsonFactories[...] entry was added (D-STORE-FORMAT literally satisfied — grep RegisteredCode json_serialize.dart = 0)."
  - "Save-gate seam = default-no-op CustomizableListItem.validate(BuildContext)->null + AlarmTask.validate() override returning scanCodeRequired only for type==scan with normalizeCode(Registered Code).isEmpty, enforced at the single CustomizeScreen Save TextButton.onPressed (blocks pop; shows colorScheme.error SnackBar + SemanticsService.announce). Threaded through CustomizeListItemScreen which defaults validate to item.validate(context). No call-site changes needed (themes/timers/alarms all hit the no-op default), so they behave exactly as before."
  - "Camera-denied resume = an AlertDialog with scanCameraPermissionPrompt + scanOpenSettings (-> AppSettings.openAppSettings()); on return it re-invokes _handleScanToRegister so the user is dropped straight back into the grant/scan flow (D-REG-CAMDENIED)."
  - "Status-only display via the normalizeCode guard: the single codeSetting.value read in the card is inside normalizeCode(...); the raw value is NEVER rendered as text or logged (D-REG-DISPLAY / T-04-14). Success status uses the primary accent; the required error uses colorScheme.error."
  - "Register screen reuses the SAME broad symbology bitmask as the ring widget (scan_task.dart) so a code that registers is also readable at ring time. A _registered guard prevents a double-store/double-pop if a second frame arrives."
metrics:
  duration: "~4 min"
  completed: "2026-06-06"
  tasks: 4
  files: 10
---

# Phase 04 Plan 05: Scan-Task Setup & Registration Summary

Built the setup half of the scan-to-dismiss task: an inline "Scan to register"
card inside the scan task's `SettingGroup`, a registration scanner screen that
normalizes-and-stores the decoded code, a REAL D-REG-REQUIRED save gate that
blocks saving a code-less scan task at the one Save button, status-only display
that never shows the raw value, and removal of the pre-existing
`print(setting.value)` payload leak — all by reusing Plan 04-04's schema and
Plan 04-02's `normalizeCode` seam, with zero new factory entries (route B,
D-STORE-FORMAT).

## What Was Built

| Task | Requirement(s) | Deliverable | Commit |
|------|----------------|-------------|--------|
| 1 | SCAN-02, SCAN-10, T-04-13 | `ScanRegisterScreen` (`ReaderWidget` -> `normalizeCode(code.text)` -> `setValue` -> pop; registration is the test scan) + removed `print(widget.setting.value)` leak | `3779f6f` |
| 2 | SCAN-08, D-REG-CAMDENIED, D-REG-DISPLAY, D-REG-REQUIRED (UI half) | `ScanRegisterCard` (setup camera-permission gate, push-on-grant, settings deep-link-on-deny + resume, status-only, inline `scanCodeRequired`, Semantics) | `2beca1f` |
| 3 | SCAN-02 (mounting) | `ScanRegisterSetting` marker + dispatch branch in `get_setting_widget.dart` returning `ScanRegisterCard` over the sibling `getSetting("Registered Code")` (route B) | `a3d5909` |
| 4 | D-REG-REQUIRED (real gate), T-04-20 | `CustomizableListItem.validate()` default-no-op + `AlarmTask.validate()` override + `CustomizeScreen` Save block (announced) threaded via `CustomizeListItemScreen` | `969fb1f` |

## Why These Choices

- **Route B over route A (D-STORE-FORMAT, the planner's call):** the raw value
  stays in the existing plain `Registered Code` `StringSetting` (`isVisual:false`
  so it auto-renders no card); a tiny non-persisted `ScanRegisterSetting` marker
  dispatches to the custom card. The `CustomSetting` route (A) would have required
  a `fromJsonFactories[RegisteredCode]` entry — exactly what D-STORE-FORMAT avoids.
  `grep RegisteredCode lib/common/utils/json_serialize.dart` = 0.
- **A dedicated marker class, not a reused `SettingAction`:** `SettingAction`
  dispatches to `SettingActionCard` (the wrong widget). A dedicated
  `ScanRegisterSetting` (carries no persisted value, `valueToJson -> null`) keeps
  the new `get_setting_widget.dart` branch unambiguous and tiny.
- **The save gate is a REAL block, not copy (D-REG-REQUIRED / T-04-20):** it is
  enforced at the single confirm control — `CustomizeScreen`'s Save `TextButton`.
  `widget.validate?.call(_item)` runs BEFORE `onSave`/`pop`; a non-null result
  early-returns (no pop), shows a `colorScheme.error` `SnackBar`, AND calls
  `SemanticsService.announce(...)` so it is never a silent dead button (UI-SPEC
  Surface 5). The predicate (`AlarmTask.validate()`) references the registered-code
  emptiness via the same `normalizeCode` seam used at store + at ring-time compare,
  so the card status, the gate, and the matcher can never disagree.
- **Targeted, zero-blast-radius seam:** the base `CustomizableListItem.validate()`
  is a default no-op (`=> null`), and `CustomizeListItemScreen` defaults its
  validate to `item.validate(context)`. Themes, timers, and non-scan alarm tasks
  all hit the no-op and behave exactly as before — no call-site changes were
  needed at the four `CustomizeListItemScreen` use sites.
- **Camera at setup only (SCAN-08):** the only `Permission.camera` request lives in
  `ScanRegisterCard._handleScanToRegister` (setup). There is no fire-time request
  (Plan 04-04's ring widget mounts `ReaderWidget` but requests no permission).
- **Privacy (D-REG-DISPLAY / T-04-14):** the card's lone `codeSetting.value` read is
  inside `normalizeCode(...)`; the raw value is never rendered as text or logged.
  The register screen normalizes-and-stores without logging the payload.

## Marker Type Chosen

A **new tiny `ScanRegisterSetting`** class (`lib/settings/types/scan_register_setting.dart`),
not a reused `SettingAction` — see the decision above.

## Deviations from Plan

None — plan executed exactly as written. No Rules 1-4 deviations were triggered.

Two within-latitude implementation choices (not deviations):
1. The plan offered "reuse `SettingAction` OR a new tiny marker class" — the new
   marker class was chosen (recorded above) because `SettingAction` dispatches to
   the wrong card.
2. The plan suggested the announced error could be a `SnackBar` + `SemanticsService.announce`
   "or an equivalent announced inline error" — the `SnackBar` + `announce` pair was
   used (the inline `scanCodeRequired` on the card, built in Task 2, is the
   always-visible companion explanation).

## D-REG-REQUIRED Save-Gate Verification (source-asserted)

The gate is a real block, verified by reading the control flow (behavioral
on-device confirm folds into Plan 06):
- `AlarmTask.validate()` returns `scanCodeRequired` **only** when
  `type == AlarmTaskType.scan` **and** `normalizeCode(getSetting("Registered Code").value).isEmpty`;
  returns `null` otherwise (every other type/item savable).
- `CustomizeScreen` Save `onPressed`: `final error = widget.validate?.call(_item);`
  `if (error != null) { ...show + announce...; return; }` — the `Navigator.pop`
  is now reachable ONLY when `error == null`. The onPressed no longer pops
  unconditionally (`grep 'if (error != null)'` = 1).
- Cancel is untouched (still pops freely); an already-saved task is unaffected
  (the gate runs only on this Save press); registering a code makes
  `normalizeCode(...)` non-empty, so the next Save passes.

## Owed CI / Human Gates (NOT run locally — Flutter/Dart toolchain absent)

Per CLAUDE.md / STATE.md, Flutter/Dart is absent here. Everything below was
authored and statically verified (grep/read), NOT executed; NO push/dispatch was
performed.

- **`flutter gen-l10n` is OWED:** the new code references existing-in-ARB getters
  (`scanRegisteredCodeTitle`, `scanCodeRegistered`, `scanNoCodeRegistered`,
  `scanRegisterButton`, `scanRescanButton`, `scanCameraPermissionPrompt`,
  `scanOpenSettings`, `scanCodeRequired`). All eight keys already exist in
  `lib/l10n/app_en.arb` (Plan 04-04 owns the ARB; this plan did NOT touch it), but
  the generated `AppLocalizations` getters do not exist on disk until codegen runs
  in CI/build. The new files will not compile locally without it — CI is the
  authoritative compile gate.
- **`flutter analyze` / full compile** is OWED via CI — also depends on the
  `flutter_zxing` package (not resolved locally) and the gen-l10n getters above.
- **No new unit/widget test was authored by this plan** (it is UI/permission/
  navigation wiring; the testable logic — `normalizeCode` and the empty-stored
  floor — is already CI-covered by Plan 04-02's `code_match_test.dart`, which this
  plan reuses). The save-gate predicate and the card are exercised on-device in
  Plan 06.
- **On-device (Plan 06 checkpoint):** the REAL camera-permission grant/deny flow
  (and the deep-link-to-settings resume), a real register scan storing a code,
  camera release after pop, and the real Save block on a code-less scan task.
  These are the device-only gates this plan deliberately defers.

## Threat Mitigations Applied (from the plan's threat register)

- **T-04-13 (print payload leak):** removed `print(widget.setting.value)` from
  `dynamic_toggle_setting_card.dart` (no replacement; the value is potentially
  sensitive). The toggle/onChanged logic is unchanged.
- **T-04-14 (card/screen rendering raw value):** status-only display; the raw
  decoded value is never rendered or logged anywhere in the card or screen.
- **T-04-15 (camera left active):** `ScanRegisterScreen` pops on decode -> the
  `ReaderWidget` leaves the tree -> the `CameraController` is released. Behavioral
  confirm owed on-device (Plan 06).
- **T-04-16 (permission timing):** `Permission.camera` requested at setup only;
  no fire-time request exists.
- **T-04-20 (shipping a code-less scan task):** the D-REG-REQUIRED Save gate blocks
  it; the block is announced (`scanCodeRequired`), never a silent dead button, and
  never traps an already-saved task.

No new security surface was introduced outside the plan's threat model. No
`## Threat Flags` needed.

## Self-Check: PASSED

All three created files exist on disk; the four task commit hashes
(`3779f6f`, `2beca1f`, `a3d5909`, `969fb1f`) exist in git history (verified below).
