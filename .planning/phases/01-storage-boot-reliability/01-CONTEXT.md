# Phase 1: Storage & Boot Reliability - Context

**Gathered:** 2026-05-30
**Status:** Ready for planning

<domain>
## Phase Boundary

After any reboot, killed write, or partial/corrupted state, Chrono always launches to its
normal UI and re-arms alarms **exactly once** — the boot black-screen / splash-hang epic is
gone. This phase also builds the **shared idempotent reschedule primitive** that Phases 2 and
4 reuse.

**In scope (requirements):** BOOT-01, BOOT-02, BOOT-03, BOOT-04, STOR-01, STOR-02.

**Not in scope (clarified during discussion):**
- Storage re-architecture (per-file-per-alarm, SQLite) — explicitly considered and rejected; see D-04.
- Removing the dual-store (GetStorage) fallback or migrating off it — keep + guard only; see D-05.
- Pre-first-unlock alarm *firing* (device-protected/DE storage work) — defer-until-unlock only; see D-07.
- Snooze, date, volume, FAB fixes — Phases 2 and 3.

</domain>

<decisions>
## Implementation Decisions

### Corrupt-data recovery & storage hardening (Tier 1 — harden the existing text path)
- **D-01:** Keep the current plain-text-JSON storage model. Do **not** rewrite the storage
  layer this phase. Reliability-before-feature: a storage rewrite mid-reliability-milestone is
  the most likely way to *introduce* new boot/storage bugs. (User: "haven't had an alarm
  corrupt on me yet… harden the text path.")
- **D-02:** **Atomic writes** for list/settings files — temp-write + rename (`saveTextFile` /
  `saveList`), so a process killed mid-save can never leave a half-written file; the previous
  good file survives until the new one is fully written. (STOR-01)
- **D-03:** **Guarded JSON decode** everywhere — no unguarded `json.decode`. A null / empty /
  invalid-JSON value recovers to a safe default and is logged, never throws. (STOR-02, BOOT-04)
- **D-04:** **Per-entry salvage on list load** — parse alarm entries individually: load every
  valid alarm, skip + log only the corrupt one(s). Only when the *top-level* list structure is
  unparseable do we fall back to a whole-list safe default (logged). The app never crashes or
  hangs on bad data. (BOOT-04)

### Hardening reach — GetStorage dual-store fallback
- **D-05:** **Keep** the legacy GetStorage→text-file fallback in `SettingGroup.load()` but make
  it **null-safe** (guard the `json.decode(null)` crash vector at `setting_group.dart:257-268`).
  Do **not** remove the dual store and do **not** add a one-time GetStorage→file migration this
  phase — that's a bigger change against the Tier 1 minimal-change principle. The known
  dual-store *drift* stays a documented (now non-fatal) wart.

### Boot-failure UX
- **D-06:** **Time-box the splash / boot init** so a recoverable error can never become a
  permanent hang — the app always reaches the normal UI. Recovery is **silent + logged** for
  routine cases (settings defaulted, slow init, salvaged non-alarm data). Show a **one-time,
  dismissible, localized notice only when alarms were actually lost** — i.e. one or more alarm
  entries were dropped during per-entry salvage, or the whole alarm list was reset. This is the
  case that can cause a missed wake-up, so the user needs to know to re-create the alarm.
  Requires: (a) a new localized string (English baseline; others via Weblate), and (b) logic to
  detect "≥1 alarm was lost" and surface it once on next normal launch.

### Boot path & reschedule (from phase goal + carried decisions)
- **D-07:** **Pre-unlock alarm firing = defer-until-unlock** (Claude's call — user did not select
  this gray area). Pure code guard: boot-time code must not touch credential-encrypted storage
  before the device is unlocked (fixes the `LOCKED_BOOT_COMPLETED` crash, BOOT-02). A post-reboot
  alarm re-arms/rings once the device is unlocked; we do **not** add device-protected (DE)
  storage to fire while still locked. Aligns with PROJECT.md "pre-first-unlock firing out unless
  validated." **Revisit during planning** if the on-device boot behavior proves this insufficient.
- **D-08:** Build **one shared idempotent reschedule primitive** (the phase's stated spine) used
  by both the boot path and normal app launch, so that after reboot+unlock every alarm/timer is
  rescheduled **exactly once** — no duplicates, no misses — even when the boot receiver and app
  launch both run. Phases 2 and 4 reuse it. (BOOT-03)

### Claude's Discretion
- Splash/init timeout duration and the exact mechanism (timer vs. guarded future) — planner/executor's call.
- The precise temp-file naming / fsync strategy for the atomic write — implementation detail.
- Where the "alarms were lost" flag is stored and how the one-time notice is rendered
  (snackbar vs. banner) — implementation detail, but it MUST be screen-reader reachable and
  use a localized string.
- Whether the same atomic-write/guarded-decode hardening is applied to `timers.txt` and other
  list files for consistency (low cost, same code path) — apply unless a reason not to surfaces.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone planning docs
- `.planning/PROJECT.md` — milestone scope, constraints, key decisions (incl. minSdk/scanner — not this phase).
- `.planning/REQUIREMENTS.md` — BOOT-01..04, STOR-01, STOR-02 exact wording (this phase's contract).
- `.planning/ROADMAP.md` §"Phase 1" + §"Research Flags" — goal, success criteria, and the Direct-Boot research flag.

### Reliability root causes (line-level — primary source for what to fix)
- `.planning/codebase/CONCERNS.md` — tech debt, fragile areas, the dual-store + `json.decode(null)` + non-atomic-write writeups.
- `.planning/research/PITFALLS.md` — reliability pitfalls research.
- `.planning/research/SUMMARY.md` — research synthesis.
- `.planning/codebase/ARCHITECTURE.md` §"Data Flow → App Boot" + §"Architectural Constraints" — boot sequence, isolate/`IsolateNameServer` ports, concurrent-write `Queue`.

### Source files to change (root causes confirmed)
- `lib/system/logic/handle_boot.dart` (~:20) — `initializeIsolate()` awaited outside try/catch; reads CE storage pre-unlock (BOOT-01, BOOT-02).
- `lib/system/logic/initialize_isolate.dart` — isolate init path shared by boot + alarm firing.
- `lib/settings/types/setting_group.dart` (:257-268, :265) — unguarded `json.decode`; silent GetStorage fallback (STOR-02, BOOT-04, D-05).
- `lib/common/utils/list_storage.dart` (:82-90) — non-atomic `saveTextFile` (`FileMode.writeOnly`); `loadList`/`saveList`; concurrent-write `Queue` (STOR-01, D-02, D-04).
- `lib/settings/logic/initialize_settings.dart` (:55-60) — `initializeStorage()` / first-run seeding (and the `clearSettingsOnDebug` default — watch item).
- `lib/main.dart` (~:24, :46) — app-launch reschedule path (`updateAlarms`/`updateTimers`); pairs with `handle_boot.dart` for the idempotent reschedule primitive (BOOT-03, D-08).

### Conventions
- `.planning/codebase/CONVENTIONS.md` — naming, logging levels (`logger.t/i/e/f`), serialization (`toJson`/`fromJson`), file layout to match when adding code.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`list_storage.dart` `Queue`** — file I/O already serializes concurrent writes through a single
  `Queue`; the atomic-write change (D-02) layers onto this rather than replacing it.
- **`logger` singleton** (`lib/developer/logic/logger.dart`) — use `logger.e()` for recovered
  errors, `logger.i()` for lifecycle, `logger.f()` for isolate-fatal; recovery logging (D-03/D-04)
  uses the existing pattern, no new logging infra.
- **`ListenerManager` + `IsolateNameServer` ports** (`stopAlarmPort`, `updatePort`) — the
  existing cross-isolate signalling the reschedule primitive (D-08) coordinates over.
- **`flutter_boot_receiver`** — already wired for `BOOT_COMPLETED`; the boot guard (D-07) builds
  on it. (Whether it exposes unlock state / needs native `LOCKED_BOOT_COMPLETED` edits is the
  ROADMAP research flag — researcher to confirm; note the commented `path:` fork override in `pubspec.yaml`.)

### Established Patterns
- **Plain-text-JSON document storage** — `Alarm` embeds a nested `SettingGroup` tree serialized
  via `toJson()`/`fromJson()` to one `.txt` file per list ("alarms", "timers"). Tier 1 (D-01)
  keeps this; per-entry salvage (D-04) must parse the JSON *array* element-by-element.
- **Log-and-continue error handling** — storage/settings errors are logged and recovered, not
  thrown (except settings-tree lookup). D-03/D-04 extend this consistently.
- **Isolate data access via disk re-read** — `appSettings` and alarm state are shared across the
  main and alarm isolates by re-loading from disk. This is *why* SQLite was rejected (D-04
  rationale): `sqflite` in a background isolate is finicky (per-isolate `databaseFactory`,
  multi-isolate DB access) — `dart:io` file reads have no such ceremony.

### Integration Points
- **Boot:** `handleBoot()` (`handle_boot.dart`) and `main()` (`main.dart`) both reschedule —
  the idempotent primitive (D-08) sits between them.
- **Storage:** `SettingGroup.load()/save()` and `loadList`/`saveList` are the choke points for
  D-02/D-03/D-04/D-05.
- **UI notice:** the "alarms were lost" one-time notice (D-06) surfaces on next normal launch —
  likely near `App` / `NavScaffold` startup; must be screen-reader reachable + localized.

</code_context>

<specifics>
## Specific Ideas

- User floated **per-file-per-alarm** (`Clock/alarms/alarm-{id}.txt`) and **SQLite** as storage
  alternatives. After weighing the tradeoffs (structural corruption isolation / transactional
  durability vs. migration risk, the sqflite-background-isolate gotcha, and a storage rewrite
  mid-reliability-milestone) the user chose **Tier 1 — harden the text path**. Rationale: "I
  haven't had an alarm corrupt on me yet so we're fine." These alternatives are recorded as
  considered-and-rejected (D-01/D-04) so they are **not relitigated** in planning.
- If per-file storage were ever revisited (future milestone), the user wanted **alarms only**
  (does not use timers) — see Deferred Ideas.

</specifics>

<deferred>
## Deferred Ideas

- **Per-file-per-alarm storage** (`Clock/alarms/alarm-{id}.txt` + an order index), alarms-only —
  structural corruption isolation. Rejected for this milestone (Tier 1 chosen). Candidate for a
  future storage-reliability/refactor milestone if real-world corruption ever shows up.
- **SQLite (blob-per-row) persistence** for alarms — engine-level atomicity/durability. Rejected:
  full storage rewrite + requires validating `sqflite` behavior in the alarm background isolate.
  Future milestone only.
- **Remove the GetStorage dual store + explicit one-time migration** — kept-and-guarded only this
  phase (D-05); the clean single-store migration is a future-milestone refactor.

</deferred>

---

*Phase: 1-Storage & Boot Reliability*
*Context gathered: 2026-05-30*
