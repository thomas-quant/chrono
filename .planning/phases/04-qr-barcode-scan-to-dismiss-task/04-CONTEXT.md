# Phase 4: QR/Barcode Scan-to-Dismiss Task - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Ship a registered-code **scan-to-dismiss** alarm task: a new `AlarmTaskType` where, at ring
time, the alarm only dismisses when a **pre-registered** QR / 1D barcode is re-scanned — on an
**F-Droid-clean scanner** (`flutter_zxing`, exact-pinned 2.2.x, zero ML Kit/gms), with a
**default-on escape hatch** so the alarm can never become un-dismissable. The lock-screen camera
preview is **de-risked first** (a hardware spike) before the scan-task UI is committed.

**In scope (requirements):** BUILD-01, BUILD-02, SCAN-01..SCAN-12 (14 reqs). See
`.planning/REQUIREMENTS.md` for exact wording — that is the contract; decisions below only
clarify HOW.

**Not in scope (deferred / out):**
- Timers (scan task is alarms-only this milestone), gating snooze behind the scan task.
- Multiple registered codes per task, user-entered code **labels/names**, configurable
  fine-grained escape thresholds, downloadable default QR — all **v2** (SCAN-V2-01..04).
- ML-based camera missions (image/object recognition) — Alarmy uses ML Kit for those; our
  F-Droid constraint forbids it. ZXing barcode/QR only.
- Pre-first-unlock alarm firing (defer-until-unlock carried from Phase 1).

</domain>

<decisions>
## Implementation Decisions

### Escape hatch (SCAN-06/07) — the ethics-critical "never trap the user" guarantee
- **D-ESC-TRIGGER:** Plain-dismiss unlocks on **time OR failed-attempts, whichever comes first.**
  (Camera-permission-denied and camera-unavailable still auto-trigger it **instantly** per SCAN-07.)
- **D-ESC-DEFAULT:** Single sane default ≈ **120s elapsed** OR a debounced wrong-read count.
  *Claude's discretion on the exact attempt number + the wrong-read debounce* (the ZXing scanner
  emits many reads/sec, so "failed attempts" must be debounced — e.g. count distinct non-matching
  payloads, or rate-limit to ~1/sec — NOT raw decode callbacks). Pin a conservative count (~10).
- **D-ESC-EXPOSURE:** v1 exposes an **on/off toggle only** — the threshold numbers live behind it.
  Fine-grained time/attempt knobs are **v2** (SCAN-V2-02).
- **D-ESC-SCOPE:** When the escape hatch fires it **skips only the scan task** — any tasks stacked
  *after* it still run. This mirrors existing app behavior (other tasks have no escape). The
  "never un-dismissable" guarantee (SCAN-07) is therefore scoped to **the scan task / camera
  failure**, not to whatever else the user deliberately stacked. (User chose this over full-alarm
  dismiss.)
- **D-ESC-MODEL (values divergence from Alarmy):** Implement only the **non-predatory safety
  auto-dismiss** (≈ Alarmy's "turn off alarm if unresponsive for a certain time"). Do **NOT** build
  Alarmy's "Emergency Escape" friction path (typed guilt-pledge, escalating tap-count penalty,
  "harder mission next time") — that traps/guilts users and is forbidden by our accessibility/ethics
  constraint.

### Lock-screen camera de-risk (SCAN criterion #1) — the milestone's biggest unknown
- **D-LOCK-SPIKE-SCOPE:** The spike tests **only Chrono's existing `showWhenLocked`-activity path**
  (`flutter_show_when_locked`). A black/dead preview on a secure (PIN/pattern) keyguard ⇒ go
  straight to the unlock-then-scan fallback. (We did **not** adopt Alarmy's overlay approach for the
  spike — see Research Items / Deferred for that alternative.)
- **D-LOCK-NOGO-UX:** On no-go devices, show an **"unlock to scan"** prompt over the keyguard; the
  scanner opens once unlocked; the alarm **keeps ringing** until then. Escape hatch is always
  underneath.
- **D-LOCK-SHIP:** **Ship regardless** of spike outcome — the default-on escape hatch is the
  universal safety net, so no-go OEMs degrade gracefully rather than blocking the release.

### Code registration in alarm setup (SCAN-02/08/10)
- **D-REG-UI:** **Inline custom setting card** with a "Scan to register" button, inside the task's
  settings (alongside the escape-hatch toggle). Not a separate dedicated screen.
- **D-REG-DISPLAY:** **Status only** — "✓ Code registered". Do **not** display the raw decoded
  value (privacy; never log payloads). A user-facing label/name is **v2** (SCAN-V2-01).
- **D-REG-TEST:** **Registration *is* the test scan** — successfully scanning to register inherently
  proves it scans (satisfies SCAN-10). Offer an optional "scan again to re-test"; no separate
  mandatory step.
- **D-REG-REQUIRED:** A registered code is **required to save** the task (prevents shipping an alarm
  that can only ever be escape-hatched). Re-scanning **replaces** the stored code.
- **D-REG-CAMDENIED:** If camera permission is denied at setup → **deep-link to system app-settings**
  (permission nudge), then resume registration. (Permission is requested at **setup, never fire
  time** — SCAN-08.)

### Ring-time scanner (SCAN-03/05/09) — reuse the existing task/ring architecture
- **D-RING-LAYOUT:** The scan task is **just another task widget** rendered full-screen in the
  **dismiss step**, entered via the existing **swipe-to-dismiss** action (`SlideNotificationAction`
  → `_setNextWidget()` → `task.builder(onSolve)` in `alarm_notification_screen.dart`). No new ring
  orchestration. Camera preview fills the `_currentWidget` slot; volume auto-lowers to
  `volumeDuringTasks`. (This matches Alarmy too — its ring-time barcode mission is a *fragment* in
  the ring activity, not a separate screen.)
- **D-RING-SNOOZE:** Snooze stays the **existing pre-task ring action** (`SlideNotificationAction`'s
  `onSnooze`). It is reachable **without ever entering the scanner**, which satisfies SCAN-05
  ("gates full dismiss only; snooze remains a normal tap") cleanly. No snooze affordance inside the
  scanner (consistent with all existing tasks).
- **D-RING-WRONGSCAN:** A non-matching scan gives **brief visual + haptic "not the registered code"
  feedback** and **counts toward the failed-attempt escape threshold** (ties to D-ESC-TRIGGER).

### Storage & matching (SCAN-02/03)
- **D-STORE-FORMAT:** Persist the registered code as a **raw, normalized string** in the task's
  `SettingGroup` (a `StringSetting`, per the existing inline-alarm-JSON pattern — no
  `json_serialize.dart` factory entry needed). Chosen over a hash so a v2 label/display stays
  possible. (Alarmy also stores raw values.)
- **D-MATCH-NORMALIZE:** Normalize **both sides identically** at register and at compare —
  trim / strip control chars / case — so a trailing newline or case diff can't false-reject
  (SCAN-03). Normalize **before** storing, and compare normalized-to-normalized.

### Claude's Discretion
- **Barcode symbology set:** accept a **broad ZXing format set** (QR + common 1D: EAN-8/13,
  UPC-A/E, Code128, Code39, ITF, + QR/DataMatrix) mirroring Alarmy's broad "QR/Barcode". Confirm
  the exact `flutter_zxing` format-enable config during research; narrow only if spurious reads
  surface (SCAN-04).
- Exact escape attempt-count + wrong-read debounce mechanism (D-ESC-DEFAULT).
- Torch default state (off), rear camera default, scan-frame overlay styling (table-stakes).
- Whether to reuse `flutter_zxing`'s `ReaderWidget` directly vs a thin wrapper — planner's call.

### ⚠ DEVIATION FROM A LOCKED CONSTRAINT — clean-room override (record honestly)
- **D-CLEANROOM-OVERRIDE:** The user **explicitly overrode** the locked "clean-room only; no
  decompiled Alarmy code/assets" constraint (`CLAUDE.md`, `PROJECT.md` Key Decisions,
  `REQUIREMENTS.md` Out-of-Scope) **for this personal fork**, after being advised 3× of the
  clean-room/derivative-work and F-Droid-provenance implications. Alarmy 26.23.0 was decompiled via
  a **private, throwaway** GitHub Actions repo (`thomas-quant/alarmy-teardown`, private) — the
  public Chrono fork was kept clean (teardown lives in no committed Chrono file; the local `.xapk`
  is git-excluded via `.git/info/exclude`).
- **What actually informed decisions:** ONLY observable-behavior-equivalent artifacts — user-facing
  **strings.xml**, **AndroidManifest**, and **layout file names**. Alarmy's source is **R8-obfuscated**
  and was **not read or copied** (it's unreadable noise). The teardown produced (a) *validations* of
  decisions already made independently, and (b) **one** new gray area (lock-screen overlay-vs-
  `showWhenLocked`). No protected source expression (SSO) entered our design.
- **Downstream consequence (do not bury):** strictly speaking this is no longer a textbook
  clean-room provenance. In practice the contamination risk is low (resources/behavior, not source),
  but the **constraint docs and the F-Droid provenance story should be reconciled at the next
  `/gsd-transition`** — either re-affirm clean-room going forward (decisions here are independently
  defensible from public behavior) or formally amend the constraint. Flagged, not silently absorbed
  (mirrors how Phase 3's D-PR-METHOD deviation was handled).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone planning docs
- `.planning/PROJECT.md` — milestone scope, constraints, Key Decisions (scanner=flutter_zxing,
  minSdk 21→23, new AlarmTask type, escape-hatch-on, clean-room — note D-CLEANROOM-OVERRIDE deviates).
- `.planning/REQUIREMENTS.md` — BUILD-01/02, SCAN-01..12 exact wording (this phase's contract) +
  v2 list (SCAN-V2-01..04) for what is deliberately deferred.
- `.planning/ROADMAP.md` §"Phase 4" (goal, 5 success criteria — criterion #1 = lock-screen spike) +
  §"Research Flags → Phase 4" (lock-screen camera is a hardware spike; verify `ReaderWidget`
  lifecycle/dispose on the pinned pre-2.3.0 line; confirm result-callback shape for normalized match).

### Existing task framework (the key enabler — new task slots in with zero ring-orchestration change)
- `lib/alarm/types/alarm_task.dart` — `AlarmTaskType` enum (add `scan`/`qrBarcode`),
  `AlarmTaskSchema` (`getLocalizedName`, `settings` SettingGroup, `_builder(onSolve, settings)`),
  `AlarmTask` (`toJson`/`fromJson` ride inline alarm JSON).
- `lib/alarm/data/alarm_task_schemas.dart` — `alarmTaskSchemasMap`; register the new schema here
  (SettingGroup with the registered-code StringSetting + escape on/off + any difficulty knobs;
  builder returns the scan task widget).
- `lib/alarm/widgets/tasks/` — existing task widgets (math/retype/sequence/memory) = the pattern to
  mirror for the new `ScanTask` widget. The widget calls `onSolve()` to complete dismiss.
- `lib/alarm/screens/alarm_notification_screen.dart` — ring-screen state machine: `actionWidget`
  (swipe `SlideNotificationAction`, `onDismiss=_setNextWidget`, `onSnooze=_snoozeAlarm`) →
  `_setNextWidget()` iterates `alarm.tasks[i].builder(_setNextWidget)` full-screen → dismiss when
  index ≥ tasks.length. Lowers volume to `alarm.volume * volumeDuringTasks / 100` during tasks.
- `lib/alarm/data/alarm_settings_schema.dart` — `CustomizableListSetting<AlarmTask>` (task config
  UI) + "Dismiss Action Type"; where the inline registration card (D-REG-UI) integrates.

### Settings / serialization / l10n / permissions
- `.planning/codebase/CONVENTIONS.md` — naming, logging (`logger.t/i/e/f`), `toJson`/`fromJson`,
  file layout; `StringSetting` already exists (no new factory entry needed for the code value).
- `.planning/codebase/ARCHITECTURE.md` — SettingGroup JSON persistence, isolate boundaries
  (camera lifecycle MUST live in the main isolate / notification screen, never the firing isolate).
- `lib/l10n/app_en.arb` — English-baseline strings; all new user-facing copy goes here (SCAN-12),
  other locales via Weblate.
- `permission_handler ^11.3.1` (existing) — camera permission at setup; `app_settings ^5.1.1` for
  the deep-link-to-settings nudge (D-REG-CAMDENIED).
- `flutter_show_when_locked ^0.0.4` (existing) — the `showWhenLocked` path the lock-screen spike
  tests (D-LOCK-SPIKE-SCOPE).
- `android/app/src/main/AndroidManifest.xml` — add `CAMERA` + `uses-feature android.hardware.camera
  required="false"` (SCAN-08; Alarmy's manifest confirms this exact shape, incl. autofocus/flash/
  front all `required=false`).
- `android/app/build.gradle` — minSdk 21→23 bump (BUILD-01); `flutter_zxing` native build needs
  CMake/NDK.

### CI / testing (per CLAUDE.md Testing Policy — default CI-runnable tests to GitHub Actions)
- `.github/workflows/tests.yml` — `flutter test --coverage` (authoritative gate; unit + headless
  widget; no emulator). `.github/workflows/test-apk.yml` — `flutter analyze` + dev APK.
- `test/alarm/types/alarm_snooze_test.dart` — Phase-2 regression pattern to mirror; extract a pure
  seam (normalize/match function, escape-hatch controller with injectable clock/Timer) and unit-test
  it in CI. Real camera/just_audio/lock-screen = on-device only.

### Teardown reference (private, NOT in this repo)
- `thomas-quant/alarmy-teardown` (private GH repo) — Alarmy 26.23.0 teardown artifacts. Reference
  only; behavioral validations already folded into the decisions above. See D-CLEANROOM-OVERRIDE.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **AlarmTask framework** (`alarm_task.dart` + `alarm_task_schemas.dart` + `widgets/tasks/`) — the
  new scan task is a drop-in schema + widget; ring orchestration needs no change.
- **`SlideNotificationAction`** — the swipe-to-dismiss/snooze widget that gates entry to the task
  flow; snooze (`onSnooze`) lives here, pre-task (D-RING-SNOOZE).
- **`volumeDuringTasks`** — ring screen already lowers alarm volume during a task; the scanner
  inherits it (no new mute logic needed; contrast Alarmy's "mute during mission" cap — out of scope).
- **`StringSetting`** + SettingGroup JSON round-trip — holds the registered code (D-STORE-FORMAT).
- **`permission_handler`** (camera) + **`app_settings`** (deep-link to settings) — both already deps.
- **`flutter_show_when_locked`** — existing over-lock mechanism the spike validates for camera.
- **Phase-2 test seam pattern** (`withClock(Clock.fixed(...))`, assert on objects/flags, OS no-ops
  under `FLUTTER_TEST`) — template for unit-testing the normalize/match + escape-hatch controller.

### Established Patterns
- **Task widget → `onSolve()` → dismiss** — the scan widget calls `onSolve` on a verified match (or
  when the escape hatch fires, skipping just this task — D-ESC-SCOPE).
- **Tasks run sequentially when stacked** — confirmed in `_setNextWidget` index walk (and matches
  Alarmy "complete each mission one by one"); informs D-ESC-SCOPE.
- **Settings as string-keyed SettingGroup serialized to inline alarm JSON** — new task config
  follows this; no new persistence path.

### Integration Points
- **Setup:** `CustomizableListSetting<AlarmTask>` (alarm_settings_schema.dart) → new task's
  SettingGroup → inline registration card (D-REG-UI) opens the scanner to capture the code.
- **Ring:** `alarm_notification_screen.dart` `_setNextWidget()` → `ScanTask.builder(onSolve)`
  full-screen; snooze via the pre-task `SlideNotificationAction`.
- **Camera lifecycle:** main isolate / notification screen only; release on every exit path
  (success / escape / background) — SCAN-11 (no stuck privacy indicator).

</code_context>

<specifics>
## Specific Ideas

**From the Alarmy 26.23.0 teardown (behavioral; resources/manifest only — see D-CLEANROOM-OVERRIDE):**
- **Library validation:** Alarmy's QR/Barcode mission uses **`zxing-android-embedded`**
  (`com.journeyapps.barcodescanner` + `com.google.zxing.*`) — the **same ZXing family** as our
  `flutter_zxing`. Alarmy *also* bundles **ML Kit / `gms.vision.barcode`** (for its image-recognition
  "Household Item Hunt" mission) — which is exactly why Alarmy is **not** on F-Droid, and exactly
  what our zero-ML-Kit constraint forbids. Confirms both our library choice and our scope exclusion.
- **Manifest validation (SCAN-08 verbatim):** `CAMERA` + `uses-feature android.hardware.camera
  required="false"` (and autofocus/flash/front all `required=false`).
- **Architecture validation:** registration is in the alarm editor
  (`alarmeditor.mission.detail.barcode.QRBarcodeScannerActivity`); ring-time barcode mission is a
  **fragment in the ring activity** (`fragment_barcode_mission.xml`), not a separate screen — matches
  our D-RING-LAYOUT. Wrong/no code → "Cannot find the QR/barcode to proceed". Torch with graceful
  "Can't turn on the flash" no-flash handling (SCAN-09).
- **New gray area found → D-LOCK-SPIKE-SCOPE:** Alarmy uses **no manifest `showWhenLocked`**; it
  renders over-lock via a **Display-over-apps overlay (`SYSTEM_ALERT_WINDOW`) + `DISABLE_KEYGUARD` +
  runtime keyguard-dismiss**. Chrono uses the `showWhenLocked`-activity approach. For a *camera
  preview*, these can differ over a secure keyguard — recorded as the fallback mechanism if our path
  fails on device (we chose to spike our path only).
- **Escape divergence → D-ESC-MODEL:** Alarmy splits escape into a predatory "Emergency Escape"
  (guilt-pledge + escalating penalty) and a benign auto-dismiss. We implement **only** the benign
  safety auto-dismiss.
- **Scope contrast:** Alarmy stores **multiple named** codes; we ship a **single status-only** code
  (label + multi-code = v2). Store the code in a way that could later grow to a list/label.

</specifics>

<deferred>
## Deferred Ideas

- **v2 scan enhancements (already in REQUIREMENTS v2):** registered-item label/name shown at ring
  time (SCAN-V2-01), configurable escape thresholds as explicit knobs (SCAN-V2-02), downloadable/
  printable default QR (SCAN-V2-03), scan-to-dismiss for timers (SCAN-V2-04).
- **Multiple registered codes per task** (match any of a set) — Alarmy does this; v2.
- **Overlay (`SYSTEM_ALERT_WINDOW`) + keyguard-dismiss lock-screen approach** — Alarmy's mechanism;
  hold as the fallback to revisit only if the `showWhenLocked` camera spike comes back no-go and we
  want to recover those OEMs before accepting unlock-then-scan.
- **"Mute during mission" (capped)** — Alarmy feature; Chrono already auto-lowers via
  `volumeDuringTasks`; full user-mute-with-cap is out of scope.
- **Reconcile clean-room constraint docs** at next `/gsd-transition` (consequence of
  D-CLEANROOM-OVERRIDE) — re-affirm or formally amend in PROJECT.md/REQUIREMENTS.md/CLAUDE.md.

</deferred>

<research_items>
## Open Items for the Researcher

1. **Lock-screen camera spike (criterion #1, highest risk):** Does a live `flutter_zxing`
   `ReaderWidget` preview render + scan inside Chrono's existing `showWhenLocked` activity over a
   **secure (PIN/pattern) keyguard**, across ≥2 OEMs? Produce a documented go / no-go /
   "requires unlock first" decision BEFORE the scan-task UI is committed. (Alarmy's overlay approach
   is the recorded fallback — D-LOCK-SPIKE-SCOPE / Deferred.)
2. **`flutter_zxing` 2.2.x specifics on Flutter 3.22.2:** `ReaderWidget` lifecycle/dispose semantics
   (camera released on every exit path — SCAN-11); exact result-callback shape for the normalized
   match (D-MATCH-NORMALIZE); the format-enable config for the broad symbology set (D-STORE/symbology);
   native CMake/NDK build under the minSdk-23 bump; **verify zero `mlkit`/`gms`/`play-services` in
   `./gradlew app:dependencies`** (BUILD-02 exit criterion).
3. **Escape-hatch failed-attempt debounce:** confirm how `flutter_zxing` surfaces repeated decodes
   so "failed attempts" can be debounced sanely (distinct payloads vs rate-limit) — D-ESC-DEFAULT.
4. **Registration card seam:** confirm the cleanest way to host a custom "scan to register" action
   inside a `SettingGroup`/`CustomizableListSetting<AlarmTask>` card (D-REG-UI), and a CI-testable
   pure seam for normalize/match + the escape-hatch controller (injectable clock/Timer).

</research_items>

---

*Phase: 4-QR/Barcode Scan-to-Dismiss Task*
*Context gathered: 2026-06-05*
