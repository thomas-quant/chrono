# Phase 4: QR/Barcode Scan-to-Dismiss Task - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-05
**Phase:** 4-QR/Barcode Scan-to-Dismiss Task
**Areas discussed:** Escape hatch (default & v1 exposure), Lock-screen camera no-go fallback, Code-registration setup flow, Ring-time scanner layout, + a second round informed by an Alarmy teardown (lock-screen spike scope, code storage, stacked-task escape scope, camera-denied-at-setup)

---

## Escape hatch — trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Time-based | Plain-dismiss after fixed elapsed time; robust if camera never reads | |
| Time or attempts | Whichever first: elapsed time OR N non-matching scans | ✓ |
| Attempts-based | After N non-matching scans only | |

**User's choice:** Time or attempts (whichever first)
**Notes:** Camera-denied/unavailable already auto-triggers instantly (SCAN-07, locked).

## Escape hatch — default threshold

| Option | Description | Selected |
|--------|-------------|----------|
| ~30 seconds | Gentler/safer; easy to wait out | |
| ~60 seconds | Middle ground | |
| ~90–120 seconds | Stricter / more "forces you out of bed" | ✓ |

**User's choice:** ~90–120 seconds
**Notes:** Exact attempt-count + wrong-read debounce left to Claude's discretion (behind the toggle).

## Escape hatch — v1 exposure

| Option | Description | Selected |
|--------|-------------|----------|
| On/off only | Single sane default behind one toggle | ✓ |
| On/off + preset | Plus coarse Lenient/Normal/Strict | |
| On/off + value | Plus explicit seconds/attempts field | |

**User's choice:** On/off toggle only
**Notes:** Fine-grained knobs are v2 (SCAN-V2-02).

## Lock-screen camera no-go fallback — UX

| Option | Description | Selected |
|--------|-------------|----------|
| Unlock-then-scan | "Unlock to scan" prompt over keyguard; alarm keeps ringing | ✓ |
| Auto escape hatch | Treat as camera-unavailable; straight to escape countdown | |
| Detect at runtime | Best-effort detect; auto-switch that device | |

**User's choice:** Unlock-then-scan
**Notes:** Escape hatch always present underneath.

## Lock-screen — ship vs gate

| Option | Description | Selected |
|--------|-------------|----------|
| Ship anyway | Escape hatch guarantees dismissability; degrade gracefully | ✓ |
| Gate on spike | Broad no-go blocks the feature release | |

**User's choice:** Ship anyway

## Code-registration setup — UI

| Option | Description | Selected |
|--------|-------------|----------|
| Inline custom card | "Scan to register" button in the task's settings card | ✓ |
| Dedicated screen | Full registration screen pushed from the card | |

**User's choice:** Inline custom card

## Code-registration setup — show value

| Option | Description | Selected |
|--------|-------------|----------|
| Status only | "✓ Code registered"; don't show raw value | ✓ |
| Raw value | Show decoded value | |
| Truncated | Masked/truncated form | |

**User's choice:** Status only
**Notes:** On-screen display ≠ logging; label/name deferred to v2 (SCAN-V2-01).

## Code-registration setup — test scan

| Option | Description | Selected |
|--------|-------------|----------|
| Registration is the test | Scanning to register proves it scans; optional re-test | ✓ |
| Separate test button | Distinct "Test scan" after registering | |

**User's choice:** Registration is the test

## Code-registration setup — required to save

| Option | Description | Selected |
|--------|-------------|----------|
| Required to save | Can't save the task without a registered code; re-scan replaces | ✓ |
| Optional | Allow saving with no code; falls through to escape hatch | |

**User's choice:** Required to save

## Ring-time scanner — layout

| Option | Description | Selected |
|--------|-------------|----------|
| Immediate full-screen | Camera takes over the moment the alarm rings | |
| Open on demand | Ring screen + "Scan to dismiss" button opens scanner | |
| Embedded preview | Preview region within the ring screen | |

**User's choice:** Free-text — "like how the current UI is, where it's a swipe action to then enter the dismissal step. so swipe to dismiss as immediate full screen, and then the camera preview."
**Notes:** Confirmed against `alarm_notification_screen.dart`: swipe `SlideNotificationAction` → `_setNextWidget()` → full-screen task widget. Scan task is just another task widget in the dismiss step.

## Ring-time scanner — snooze coexistence

| Option | Description | Selected |
|--------|-------------|----------|
| Overlaid on scanner | Snooze button over/below the scanner | |
| On ring screen | Snooze on the ring screen; back out to reach it | ✓ |

**User's choice:** "refer to prev" → snooze stays the existing pre-task ring action (`onSnooze`); never inside the scanner. Satisfies SCAN-05.

## Ring-time scanner — wrong scan

| Option | Description | Selected |
|--------|-------------|----------|
| Feedback + counts | Visual + haptic; counts toward failed-attempt threshold | ✓ |
| Feedback, no count | Feedback but doesn't count | |
| Silent retry | No explicit feedback | |

**User's choice:** Feedback + counts

---

## Second round — informed by the Alarmy 26.23.0 teardown

> The user opted to decompile Alarmy (overriding the clean-room constraint for this personal fork —
> see CONTEXT.md D-CLEANROOM-OVERRIDE). Teardown ran in a private GH Actions repo
> (`thomas-quant/alarmy-teardown`); only resources/manifest (strings, layouts, AndroidManifest)
> informed decisions — R8-obfuscated source was not read/copied. It validated most decisions and
> surfaced one new gray area (lock-screen overlay vs showWhenLocked).

## Lock-screen spike scope

| Option | Description | Selected |
|--------|-------------|----------|
| Test both mechanisms | Chrono's showWhenLocked AND Alarmy-style overlay/keyguard-dismiss before no-go | |
| Current path only | Spike only Chrono's existing showWhenLocked path; black → unlock-then-scan | ✓ |

**User's choice:** Current path only
**Notes:** Overlay approach recorded as fallback (Deferred), not adopted.

## Registered-code storage

| Option | Description | Selected |
|--------|-------------|----------|
| Raw normalized string | Store decoded value normalized in alarm JSON (like Alarmy) | ✓ |
| Normalized hash | Store only a hash; raw never persists | |

**User's choice:** Raw normalized string
**Notes:** Keeps a v2 label/display open.

## Stacked-task escape scope

| Option | Description | Selected |
|--------|-------------|----------|
| Fully dismiss the alarm | Escape bypasses the whole alarm | |
| Skip only the scan task | Escape completes the scan task; remaining tasks still run | ✓ |

**User's choice:** Skip only the scan task
**Notes:** Matches existing app behavior; SCAN-07 guarantee scoped to the scan task / camera failure.

## Camera denied at setup

| Option | Description | Selected |
|--------|-------------|----------|
| Deep-link to settings | Prompt + button to open system settings, then resume | ✓ |
| Block until granted | Can't add the task until camera granted | |
| Allow + warn | Save without registering; warn it relies on escape hatch | |

**User's choice:** Deep-link to settings

---

## Claude's Discretion

- Exact escape attempt-count + wrong-read debounce mechanism (behind the on/off toggle).
- Barcode symbology set (broad ZXing set mirroring Alarmy; confirm `flutter_zxing` format config).
- Torch default (off), rear camera default, scan-frame overlay styling.
- `ReaderWidget` direct vs thin wrapper.

## Deferred Ideas

- v2 scan enhancements: label/name at ring time (SCAN-V2-01), configurable escape knobs
  (SCAN-V2-02), downloadable default QR (SCAN-V2-03), timers (SCAN-V2-04).
- Multiple registered codes per task (match-any-of-set).
- Overlay (`SYSTEM_ALERT_WINDOW`) + keyguard-dismiss lock-screen approach (fallback if spike no-go).
- "Mute during mission" (capped) — Chrono already auto-lowers via `volumeDuringTasks`.
- Reconcile the clean-room constraint docs at next `/gsd-transition` (D-CLEANROOM-OVERRIDE).
