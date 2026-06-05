---
phase: 03-date-volume-fab-high-value-fixes
plan: 03
subsystem: ui
tags: [flutter, layout, fab, list-view, theme-extension, widget-test]

# Dependency graph
requires:
  - phase: 03-date-volume-fab-high-value-fixes (plans 01-02)
    provides: "Date-only serialization (03-01) and the cancellable volume ramp (03-02); this plan closes the third Phase-3 defect (FAB overlap) at the shared list layer"
provides:
  - "A single computed bottom inset on CustomListView's scrollable that reserves FAB clearance for every list screen (~13 FAB screens) in one edit"
  - "A narrow headless widget test asserting the list reserves bottom clearance >= the FAB extent (incl. Material +20)"
affects: [phase-04-qr-scan-task (any new list/FAB screens inherit the clearance), gsd-transition (PR-02 / ROADMAP criterion #4 reword owed)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Central layout fix at the shared list/FAB composition layer (D-FAB-SCOPE) — one EdgeInsets edit covers all screens rather than per-screen padding"
    - "Derived (not guessed) layout constants, with each term's source line cited in a code comment (Pitfall 4 avoidance)"
    - "Narrow headless widget test on a layout seam: pump the component under a Theme carrying ThemeSettingExtension, assert the resolved SliverPadding inset"

key-files:
  created:
    - test/common/widgets/list/fab_clearance_test.dart
  modified:
    - lib/common/widgets/list/custom_list_view.dart

key-decisions:
  - "Bottom inset = 8 (original) + 56 (FAB tap target 16+24+16) + 16 (gap) + (useMaterialStyle ? 20 : 0), each term derived from fab.dart/snackbar.dart and cited inline"
  - "Single central edit in CustomListView; PersistentListView (pass-through wrapper) left untouched"
  - "No nav-bar height added to the inset — SafeArea already wraps the body and landscape has no bottom nav bar"
  - "Headless FAB widget test kept in CI (not degraded) — appSettings is a statically-constructed in-memory schema, so the seam pumps without storage/audio singletons"
  - "Reimplemented #466 independently, sole credit, no contributor attribution (D-PR-METHOD)"

patterns-established:
  - "Pattern 1: Central FAB bottom clearance — one bottom inset in CustomListView.build reserves room for the custom Positioned FAB overlay across all list screens"
  - "Pattern 2: Cite-the-derivation — layout magic numbers carry an inline comment naming the fab.dart/snackbar.dart line each term came from"

requirements-completed: [FAB-01, PR-02]

# Metrics
duration: 2min
completed: 2026-06-05
---

# Phase 3 Plan 3: Central FAB Bottom Clearance Summary

**One computed bottom inset on `CustomListView`'s shared scrollable reserves FAB clearance for all ~13 list screens, derived from `fab.dart`/`snackbar.dart` geometry, with a narrow headless widget test asserting the inset clears the FAB extent (incl. Material +20).**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-06-05T00:57:29Z
- **Completed:** 2026-06-05T00:59:xxZ
- **Tasks:** 2
- **Files modified:** 2 (1 modified, 1 created)

## Accomplishments
- Fixed FAB-01 at the single shared list/FAB layer (D-FAB-SCOPE): the custom `Positioned` FAB overlay no longer occludes the last list item / bottom alarm's menu button, on every screen that renders its list through `CustomListView` (directly or via the `PersistentListView` wrapper).
- Replaced the hardcoded `padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)` on `AnimatedReorderableListView` with `EdgeInsets.only(left: 16, right: 16, top: 8, bottom: <computed>)`, reading `theme.extension<ThemeSettingExtension>()!.useMaterialStyle` (mirroring `fab.dart:58-59`).
- Authored a narrow headless widget test that pumps `CustomListView` under a `ThemeData` carrying a `ThemeSettingExtension` and asserts the resolved `SliverPadding` bottom inset clears the FAB extent in both Material and non-Material styles.

## The exact derived bottom-inset constant

```dart
final double fabBottomClearance =
    8 + 56 + 16 + (themeSettings.useMaterialStyle ? 20 : 0);
```

Each term is derived (not picked), and cited in an inline comment in `custom_list_view.dart`:

| Term | Value | Source |
|------|-------|--------|
| original list inset | `8` | the previous `EdgeInsets.symmetric(vertical: 8)` baseline (kept) |
| FAB tap-target extent | `56` | `16 + 24 + 16` — `fab.dart:84` (`EdgeInsets.all(16.0)`) around the `24`px icon at `fab.dart:88` (`size: 24 * widget.size`, `size: 1`) |
| gap to the FAB | `16` | matches `fab.dart:74` right offset (`16 + ...`) and the `64 + 16` FAB gap in `snackbar.dart:57,59` (`getSnackbar`) |
| Material `+20` | `(useMaterialStyle ? 20 : 0)` | matches the FAB's own `widget.bottomPadding + 20` at `fab.dart:67-69` (and the `bottom += 20` Material rule in `snackbar.dart:67-69`) so the inset clears the FAB's raised bottom in Material style |

Horizontal `16` and top `8` are preserved exactly — only the bottom inset changed. No nav-bar height is added: `SafeArea` already wraps the body (`nav_scaffold.dart:252`) and landscape has no bottom nav bar (`nav_scaffold.dart:230`).

## Task Commits

Each task was committed atomically:

1. **Task 1: Inject one computed bottom inset into CustomListView's list padding** - `78e1b2e` (fix)
2. **Task 2: Narrow headless widget test — list reserves bottom clearance >= FAB extent** - `43d2c35` (test)

**Plan metadata:** committed separately (docs: complete plan).

## Files Created/Modified
- `lib/common/widgets/list/custom_list_view.dart` - Added `theme_extension.dart` import; read `ThemeSettingExtension` in `build`; replaced the hardcoded symmetric padding with `EdgeInsets.only(...)` carrying the derived `fabBottomClearance` bottom inset (with the term-by-term derivation comment).
- `test/common/widgets/list/fab_clearance_test.dart` - **(new)** Narrow headless widget test: pumps `CustomListView` (empty item list) under a `MaterialApp` whose `ThemeData` carries a `ThemeSettingExtension`, finds the forwarded `SliverPadding`, and asserts `padding.bottom >= 56` (non-material), `>= 56 + 20` (material), and that `left/right == 16`, `top == 8`.

## Headless FAB test: stayed in CI (not degraded)

The narrow headless test was attempted first (per the plan) and **kept in CI** — it did not need to degrade to on-device-only. Rationale: `CustomListView.initState` only reads a *statically-constructed* in-memory setting reference (`appSettings.getGroup("General").getGroup("Interactions").getSetting("Long Press Action")`); `appSettings` is a module-level `SettingGroup` literal (`settings_schema.dart:21`) reachable under `TestWidgetsFlutterBinding.ensureInitialized()` without any storage/audio/l10n I/O. The test pumps an **empty** item list, so the per-item builder (the only path that reads the setting's *value* for `LongPressAction`) never runs, and the `SliverPadding` is still built. The test does not boot `App()`/`NavScaffold`, touches no `just_audio`/storage, and adds no pub dependency.

**Residual CI risk (owed gate, below):** if the static `appSettings` schema construction transitively reaches storage on first access in the CI environment, the pump could throw — in which case the plan permits degrading this single test to on-device-only (D-TEST-COVERAGE). That is a CI-confirmable outcome, not a local one; flagged for the verifier.

## Decisions Made
- **Single central edit, wrapper untouched** — the fix lives in `CustomListView` (the one point all lists render through); `persistent_list_view.dart` is a pass-through and was deliberately NOT modified.
- **Derive, don't guess** — every term in the bottom inset cites its `fab.dart`/`snackbar.dart` source line in an inline comment, so the constant is auditable (Pitfall 4).
- **No nav-bar height** — `SafeArea` already handles system insets and landscape has no bottom nav bar, so the inset only needs to clear the FAB itself.
- **Sole credit / clean-room** — reimplemented the #466 FAB fix independently; no contributor attribution, no co-author trailer, no reference to PR #466 anywhere in code, comments, or commits (D-PR-METHOD).

## Deviations from Plan

None - plan executed exactly as written. No checkpoints, no auth gates, no auto-fixes (Rules 1-4 not triggered). Only the two intended files changed.

## Issues Encountered
None.

## Known Stubs
None — the bottom inset is a live computed value wired to `useMaterialStyle`; no placeholder/empty data introduced.

## Owed CI / human gates (toolchain absent locally)

The Flutter/Dart toolchain is absent in this environment, so the following were authored in-repo and are **owed via CI** — never run or reported as locally passing:

- **`flutter test` (authoritative gate, `tests.yml` on push):** the new `test/common/widgets/list/fab_clearance_test.dart` runs here. This is where the clearance contract is actually verified. If it proves flaky/unworkable headlessly in CI (see "Residual CI risk" above), degrade it to on-device-only and document — but the narrow headless test was the correct first attempt.
- **`flutter analyze` (informational, `test-apk.yml` dispatch):** confirm no NEW issues on `lib/common/widgets/list/custom_list_view.dart` and `test/common/widgets/list/fab_clearance_test.dart`. Note: `test-apk.yml`'s scoped analyze gate currently points at the Phase-2 files (per 02-02) — it does not yet cover these Phase-3 paths; a future repoint or a full-tree analyze run is the real coverage.
- **On-device cross-OEM layout (human gate, CI cannot run):** verify the last list item and the bottommost alarm's menu button are fully visible above the FAB in **portrait and landscape**, in **Material and non-Material** styles, across OEMs. This is the only check CI genuinely cannot perform.

## Deferred (not done here)

- **PR-02 and ROADMAP Phase-3 success-criterion #4 still literally say "crediting the contributor."** Per the plan and D-PR-METHOD this milestone reimplements #466 with sole credit, so those artifacts need rewording — **deferred to the next `/gsd-transition`**, intentionally NOT reworded in this plan. Flagged, not silently absorbed.

## Next Phase Readiness
- FAB-01 closed at the shared layer; any new list/FAB screen added in Phase 4 (QR scan task) inherits the clearance automatically with no per-screen work.
- Phase 3's three high-value defects (date 03-01, volume 03-02, FAB 03-03) are now all source-complete; the phase's remaining gates are the owed CI runs and the end-of-phase on-device checks.

## Self-Check: PASSED

- FOUND: `lib/common/widgets/list/custom_list_view.dart`
- FOUND: `test/common/widgets/list/fab_clearance_test.dart`
- FOUND: `.planning/phases/03-date-volume-fab-high-value-fixes/03-03-SUMMARY.md`
- FOUND: commit `78e1b2e` (Task 1)
- FOUND: commit `43d2c35` (Task 2)

---
*Phase: 03-date-volume-fab-high-value-fixes*
*Completed: 2026-06-05*
