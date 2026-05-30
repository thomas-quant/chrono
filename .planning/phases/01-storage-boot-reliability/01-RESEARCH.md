# Phase 1: Storage & Boot Reliability - Research

**Researched:** 2026-05-30
**Domain:** Android Direct Boot / File-Based Encryption (FBE) boot path, atomic file persistence, idempotent alarm reschedule — Flutter 3.22.2 / Dart 3.4, minSdk 21 (→ 23 in Phase 4), Android-only
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Keep the current plain-text-JSON storage model. Do **not** rewrite the storage layer this phase. (Reliability-before-feature; a storage rewrite mid-reliability-milestone is the most likely way to *introduce* new boot/storage bugs.)
- **D-02:** **Atomic writes** for list/settings files — temp-write + rename (`saveTextFile` / `saveList`), so a process killed mid-save can never leave a half-written file; the previous good file survives until the new one is fully written. (STOR-01)
- **D-03:** **Guarded JSON decode** everywhere — no unguarded `json.decode`. A null / empty / invalid-JSON value recovers to a safe default and is logged, never throws. (STOR-02, BOOT-04)
- **D-04:** **Per-entry salvage on list load** — parse alarm entries individually: load every valid alarm, skip + log only the corrupt one(s). Only when the *top-level* list structure is unparseable do we fall back to a whole-list safe default (logged). The app never crashes or hangs on bad data. (BOOT-04)
- **D-05:** **Keep** the legacy GetStorage→text-file fallback in `SettingGroup.load()` but make it **null-safe** (guard the `json.decode(null)` crash vector at `setting_group.dart:257-268`). Do **not** remove the dual store and do **not** add a one-time GetStorage→file migration this phase.
- **D-06:** **Time-box the splash / boot init** so a recoverable error can never become a permanent hang. Recovery is **silent + logged** for routine cases. Show a **one-time, dismissible, localized notice only when alarms were actually lost** (≥1 alarm entry dropped during per-entry salvage, or the whole alarm list was reset). Requires (a) a new localized string (English baseline; others via Weblate), and (b) logic to detect "≥1 alarm was lost" and surface it once on next normal launch.
- **D-07:** **Pre-unlock alarm firing = defer-until-unlock** (Claude's call). Pure code guard: boot-time code must not touch credential-encrypted storage before the device is unlocked (fixes the `LOCKED_BOOT_COMPLETED` crash, BOOT-02). A post-reboot alarm re-arms/rings once the device is unlocked; do **not** add device-protected (DE) storage to fire while still locked. **Revisit during planning** if the on-device boot behavior proves this insufficient.
- **D-08:** Build **one shared idempotent reschedule primitive** used by both the boot path and normal app launch, so that after reboot+unlock every alarm/timer is rescheduled **exactly once** — no duplicates, no misses — even when the boot receiver and app launch both run. Phases 2 and 4 reuse it. (BOOT-03)

### Claude's Discretion
- Splash/init timeout duration and the exact mechanism (timer vs. guarded future) — planner/executor's call.
- The precise temp-file naming / fsync strategy for the atomic write — implementation detail.
- Where the "alarms were lost" flag is stored and how the one-time notice is rendered (snackbar vs. banner) — implementation detail, but it MUST be screen-reader reachable and use a localized string.
- Whether the same atomic-write/guarded-decode hardening is applied to `timers.txt` and other list files for consistency (low cost, same code path) — apply unless a reason not to surfaces.

### Deferred Ideas (OUT OF SCOPE)
- **Per-file-per-alarm storage** (`Clock/alarms/alarm-{id}.txt` + an order index), alarms-only — rejected for this milestone (Tier 1 chosen). Future milestone candidate.
- **SQLite (blob-per-row) persistence** for alarms — rejected (full storage rewrite + `sqflite` background-isolate validation). Future milestone only.
- **Remove the GetStorage dual store + explicit one-time migration** — kept-and-guarded only this phase (D-05); the clean single-store migration is a future-milestone refactor.
- Snooze, date, volume, FAB fixes — Phases 2 and 3.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BOOT-01 | App launches to normal UI (never a permanent black/splash hang) after reboot, killed boot write, or partial/corrupted state | Time-boxed init (D-06) + non-fatal load (D-03/D-04). Root: `main.dart:43-50` awaits a chain of init futures with no timeout; any hang in `updateAlarms`/`load` = permanent splash. See *Architecture Patterns → Pattern 3*. |
| BOOT-02 | Boot-time code does not access credential-encrypted storage before unlock (no `IllegalStateException` on `LOCKED_BOOT_COMPLETED`) | **Primary target resolved below.** Chrono's manifest fires `flutter_boot_receiver` on `LOCKED_BOOT_COMPLETED` with `directBootAware="true"`; the plugin does NO unlock check and reads default (CE) SharedPreferences. Fix = unlock guard in `handleBoot()` + (optionally) narrow the manifest. See *Architecture Patterns → Pattern 1*. |
| BOOT-03 | Alarms/timers rescheduled after reboot once, idempotently (no duplicates, no missed reschedules) | Idempotent reschedule primitive (D-08). **Three** independent reschedule paths exist on reboot (see *Don't Hand-Roll* + *Pitfall 4*); the primitive must be safe to run N times. `updateAlarms()` is already cancel-all-then-reschedule-all — the work is making it the single funnel and making boot defer to unlock. |
| BOOT-04 | A corrupted/unreadable settings/list file recovers to a safe default and is logged, instead of crashing/hanging | Guarded decode (D-03) + per-entry salvage (D-04). Roots: `setting_group.dart:265` unguarded `json.decode(value)`; `json_serialize.dart:50-57` `listFromString` rethrows; `loadList` (async) never wraps `listFromString`. See *Code Examples*. |
| STOR-01 | List/settings writes are atomic (temp-write + rename) | `saveTextFile` at `list_storage.dart:82-91` uses `FileMode.writeOnly` (truncate-in-place) = non-atomic. Fix = write to `$key.txt.tmp` then `File.rename()`. See *Code Examples*. |
| STOR-02 | Storage reads guard against null/invalid JSON before decoding (no unguarded `json.decode`) | Same as BOOT-04 decode sites. `SettingGroup.load()` passes a possibly-null `GetStorage().read(id)` straight into `json.decode`. |
</phase_requirements>

## Summary

This phase is a **brownfield reliability hardening** of an existing, mature storage + boot path — not a greenfield build. There are **no new dependencies**: every fix is a code change (and one optional manifest change) against files whose root causes are confirmed at the line level. The dominant unknown — the Direct-Boot / unlock plumbing — is now **fully resolved from authoritative source** (the `flutter_boot_receiver` 1.1.0 Java source and changelog, plus Chrono's own `AndroidManifest.xml`).

The headline finding: **Chrono's boot crash is self-inflicted by its own manifest, not a plugin limitation.** The `flutter_boot_receiver` 1.1.0 changelog entry is literally *"Added direct boot support"*, and its `BootBroadcastReceiver.onReceive` matches `LOCKED_BOOT_COMPLETED`/`QUICKBOOT_POWERON` — but it performs **no `UserManager.isUserUnlocked()` check** and its `FlutterBackgroundExecutor` reads its callback handle from **default (credential-encrypted) SharedPreferences**. The plugin's *stock* README manifest registers only `BOOT_COMPLETED` with **no** `directBootAware`. Chrono's manifest deliberately *added* `LOCKED_BOOT_COMPLETED` + `directBootAware="true"` to the receiver, the `BootHandlerService`, the `android_alarm_manager_plus` components, **and** the `MainActivity`. So on an FBE device, after reboot-before-unlock, the receiver fires in Direct Boot mode, the Dart `handleBoot()` runs, and `initializeStorage()` → `getApplicationDocumentsDirectory()` (CE storage) → `IllegalStateException`. The current `handleBoot()` (`handle_boot.dart:20`) awaits `initializeIsolate()` *outside* the try/catch, so that throw is unhandled and the boot isolate crashes, leaving partial reschedule state that the next foreground launch then hangs on.

**Primary recommendation:** Implement a **defer-until-unlock guard** at the top of `handleBoot()` using `UserManager.isUserUnlocked()` (exposed via a tiny native MethodChannel on `MainActivity`, or a thin platform check), returning early without touching CE storage when locked — the OS already redelivers `BOOT_COMPLETED` (and Chrono's plugins re-fire) after unlock. Pair this with: (1) atomic temp+rename writes in `saveTextFile`/`saveRingtone`; (2) guarded `json.decode` + per-entry salvage in `listFromString`/`loadList` and a null-guard in `SettingGroup.load()`; (3) one shared idempotent reschedule funnel (`updateAlarms`/`updateTimers` are already cancel-then-schedule — the work is ensuring exactly one path runs and it tolerates being run twice); and (4) a time-boxed `main()` init so a slow/failed recovery degrades to the normal UI instead of an infinite splash, with a one-time localized "alarms were reset" notice only when salvage actually dropped an alarm.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Detect device unlock state at boot | Native Android (Kotlin/Java) | Dart guard in `handleBoot()` | `UserManager.isUserUnlocked()` is an Android API; Dart has no direct access. A MethodChannel on `MainActivity` or a thin platform call surfaces it. Decision is *made* in Dart (defer vs proceed). |
| Boot reschedule trigger | Native (`BootBroadcastReceiver` + OS redelivery) | Dart (`handleBoot` → `updateAlarms`) | The OS/plugin decides *when* the receiver fires; Dart decides *what* to do and whether to defer. |
| Atomic file write | Dart (`dart:io` `File.rename`) | — | `rename()` within the same filesystem is the POSIX-atomic primitive; no native code needed. App-private dir is a single filesystem. |
| Guarded decode / per-entry salvage | Dart (`json_serialize.dart`, `setting_group.dart`) | — | Pure Dart parsing logic. |
| Idempotent reschedule | Dart (`update_alarms.dart` / `update_timers.dart`) | Native (`AndroidAlarmManager.cancel/oneShotAt` by stable id) | Dedup keyed on `scheduleId` (stable, persisted in `alarm_schedule_ids`); cancel-before-schedule is the dedup mechanism. |
| Time-boxed splash | Dart (`main.dart`) | Flutter framework | Init orchestration is in `main()`; the timeout wraps Dart futures. |
| One-time "alarms lost" notice | Dart UI (`App`/`NavScaffold`) + l10n (`app_en.arb`) | — | Flutter widget + ARB string; must be screen-reader reachable. |

## Standard Stack

**No new packages.** Every requirement is satisfied with the existing toolchain and `dart:io`/`dart:convert`. The relevant already-present dependencies:

### Core
| Library | Version (resolved) | Purpose | Why Standard |
|---------|--------------------|---------|--------------|
| `dart:io` (SDK) | Dart 3.4 | `File.rename()` for atomic writes; `File.writeAsString` to a temp path | POSIX `rename(2)` is atomic on a single filesystem; the canonical crash-safe write pattern. `[CITED: api.dart.dev/dart-io/File/rename.html]` |
| `dart:convert` (SDK) | Dart 3.4 | `json.decode` / `json.encode` with try/catch guards | Already the serialization primitive throughout Chrono. |
| `flutter_boot_receiver` | **1.1.0** (pub.dev, sha `0860fa1b…`) | `BOOT_COMPLETED`/`LOCKED_BOOT_COMPLETED` → Dart `handleBoot()` callback | Already wired (`main.dart:38`). 1.1.0 *is* the "direct boot support" release. `[VERIFIED: github.com/AhsanSarwar45/flutter_boot_receiver CHANGELOG.md]` |
| `android_alarm_manager_plus` | **4.0.1** (fork `AhsanSarwar45/plus_plugins@alarm_show_intent`, ref `ae6c11c3`) | Exact alarm scheduling via `oneShotAt`; `rescheduleOnReboot:true` re-arms via its own `RebootBroadcastReceiver` | Already the scheduling backend; the fork adds the `alarm_show_intent` behavior. |
| `get_storage` | 2.1.1 | Legacy dual-store fallback (`first_launch`, `init_$key` flags, `SettingGroup` fallback read) | Kept + guarded (D-05), not removed. Backed by SharedPreferences (CE storage). |
| `device_info_plus` | 10.1.0 | `androidInfo.version.sdkInt` for API-level gating of the Direct Boot guard | Already initialized (`initializeAndroidInfo()`); Direct Boot only exists API 24+, so the guard can short-circuit on API < 24. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `queue` | 3.1.0+2 | Serializes all file I/O through one `Queue` (`list_storage.dart:14`) | The atomic-write change layers *inside* the existing queued closure — no new concurrency primitive needed. |
| `logger` | 2.4.0 | `logger.e/i/f` recovery logging | Recovery paths (D-03/D-04) reuse the existing `logger` singleton; no new logging infra. `[VERIFIED: lib/developer/logic/logger.dart]` |
| `flutter_localizations` + `intl` + ARB | 0.19.0 | The one new "alarms were reset" string | Add a key to `lib/l10n/app_en.arb` (flat `key` + `@key` metadata, 773 lines today); regenerate via `flutter gen-l10n`. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `File.rename` temp+swap | `File.writeAsString(...flush:true)` only | `flush:true` fsyncs but still truncates-in-place — a kill mid-write still corrupts. Rename is the only crash-atomic option. Use both: write temp with flush, then rename. |
| Dart `UserManager.isUserUnlocked` via MethodChannel | Native `directBootAware` DE-storage rewrite | DE storage = pre-unlock *firing* (D-07 deferred this). The MethodChannel guard is the minimal Tier-1 fix. |
| Manifest narrowing (drop `LOCKED_BOOT_COMPLETED`) | Keep manifest, guard in Dart only | See *Open Questions Q1* — both are viable; recommend the Dart guard as primary (robust even if `BOOT_COMPLETED` itself is delivered pre-unlock on some OEMs) and treat manifest narrowing as a secondary belt-and-suspenders. |

**Installation:** None — no `pubspec.yaml` changes. (If the planner adds a native unlock-state MethodChannel, that is Kotlin in `MainActivity.kt`, no Gradle dep.)

## Package Legitimacy Audit

> No external packages are installed in this phase. All dependencies above are pre-existing and already resolved in `pubspec.lock`. slopcheck/registry verification is **not applicable** — this is a code-and-manifest hardening phase with zero new installs.

**Packages removed due to slopcheck [SLOP] verdict:** none (no installs)
**Packages flagged as suspicious [SUS]:** none (no installs)

## Architecture Patterns

### System Architecture Diagram

```text
                          DEVICE REBOOT (FBE device, before unlock)
                                       │
                ┌──────────────────────┼───────────────────────────┐
                ▼                      ▼                            ▼
   ACTION_LOCKED_BOOT_COMPLETED   (later) ACTION_USER_UNLOCKED   ACTION_BOOT_COMPLETED
   (DE storage only)              (foreground)                  (background, post-unlock)
                │                                                    │
   ┌────────────┴────────────┐                          ┌───────────┴───────────┐
   ▼                         ▼                          ▼                       ▼
flutter_boot_receiver   android_alarm_manager_plus  flutter_boot_receiver   aamp Reboot-
BootBroadcastReceiver   RebootBroadcastReceiver     (fires AGAIN post-       BroadcastReceiver
(directBootAware,       (dynamically enabled by     unlock)                  (re-arms each
 NO unlock check)        rescheduleOnReboot:true)         │                   alarm itself)
   │                         │                            │                       │
   ▼                         ▼                            ▼                       ▼
BootHandlerService      [re-arms alarms from its     handleBoot()           [re-arms again]
(JobIntentService)       own persisted store —         │                          │
   │                     bypasses Dart entirely]       │                          │
   ▼                                                    ▼                          │
handleBoot() [Dart background isolate]  ◄───────── GUARD HERE: ───────────────────┘
   │                                    isUserUnlocked()? NO → log + return early
   │                                                       YES ↓
   ▼                                    ┌──────────────────────────────────────┐
initializeIsolate()                     │  IDEMPOTENT RESCHEDULE PRIMITIVE      │
   │  (CE storage touch — CRASH         │  updateAlarms(): cancelAllAlarms()    │
   │   if reached pre-unlock)           │    then for each alarm: cancel(id)    │
   ▼                                    │    + oneShotAt(id) — safe to run N×   │
updateAlarms() / updateTimers() ───────►│  keyed on stable scheduleId          │
                                        └──────────────────────────────────────┘
                                                       ▲
   APP COLD LAUNCH (main.dart)                         │
        │                                              │
   WidgetsFlutterBinding → Future.wait([init…])        │
        │  (TIME-BOX this with .timeout())             │
   initializeStorage() → initializeSettings()          │
        │  (guarded decode + per-entry salvage)        │
   updateAlarms()/updateTimers() ──────────────────────┘ (same funnel)
        │
   runApp(App) ──► App/NavScaffold: if alarmsWereLost → one-time localized notice
```

Data flow to trace for the primary use case (reboot → reliable UI + exactly-once reschedule):
1. Reboot delivers `LOCKED_BOOT_COMPLETED` → `handleBoot()` runs pre-unlock → **guard returns early** (no CE touch, no crash).
2. User unlocks → `BOOT_COMPLETED`/`USER_UNLOCKED` redelivered → `handleBoot()` runs again, guard passes → idempotent reschedule.
3. User opens app → `main()` runs the *same* reschedule funnel; cancel-then-schedule by stable id means the boot-path arming is replaced, not duplicated.

### Recommended Project Structure
No new directories. Touch points (all existing files):
```
lib/
├── system/logic/
│   ├── handle_boot.dart          # add unlock guard + wrap initializeIsolate in try/catch
│   └── initialize_isolate.dart   # (no structural change; called only after guard passes)
├── common/utils/
│   ├── list_storage.dart         # atomic saveTextFile/saveRingtone; loadList wraps salvage
│   └── json_serialize.dart       # listFromString → per-entry salvage + guarded decode
├── settings/types/
│   └── setting_group.dart        # load(): null-guard before json.decode (:257-268)
├── alarm/logic/update_alarms.dart  # the idempotent reschedule funnel (BOOT-03)
├── timer/logic/update_timers.dart  # same funnel for timers
├── main.dart                       # time-box init; surface "alarms lost" flag
├── app.dart / navigation/screens/nav_scaffold.dart  # one-time localized notice
└── l10n/app_en.arb                 # new "alarms were reset" string
android/app/src/main/
├── AndroidManifest.xml            # (optional) narrow boot receiver actions
└── kotlin/com/vicolo/chrono/MainActivity.kt  # (optional) isUserUnlocked MethodChannel
```

### Pattern 1: Defer-until-unlock boot guard (BOOT-02, D-07)
**What:** At the very top of `handleBoot()`, before any storage touch, check whether the user has unlocked the device. If not, log and return — do nothing. The OS redelivers `BOOT_COMPLETED` after unlock, and Chrono's `rescheduleOnReboot:true` alarms are independently re-armed by `android_alarm_manager_plus`, so deferring loses nothing.
**When to use:** Always, at the head of the boot isolate entry point. (Also safe to add to `initializeIsolate()` callers that run pre-unlock, but `handleBoot()` is the only Chrono-owned boot path.)
**Mechanism options (Claude's discretion, planner picks one):**
- **(A) Native MethodChannel (recommended):** add a `UserManager.isUserUnlocked()` call exposed over a MethodChannel on `MainActivity`/the plugin registrant. Most reliable; works regardless of which broadcast fired.
- **(B) Probe-and-catch:** attempt a cheap CE-storage read inside try/catch; treat `IllegalStateException` (or any throw) as "locked, defer." Simpler, no Kotlin, but conflates "locked" with "corrupt."
- **API gating:** Direct Boot only exists on **API 24+**. On `androidInfo.version.sdkInt < 24` (Chrono's minSdk is 21 this phase), the guard can no-op (storage always available). `[CITED: developer.android.com/privacy-and-security/direct-boot]`
**Example (sketch — guard at head of `handleBoot`):**
```dart
// lib/system/logic/handle_boot.dart  (Source: pattern derived from current handle_boot.dart + Android Direct Boot docs)
@pragma('vm:entry-point')
void handleBoot() async {
  FlutterError.onError = (d) => logger.f("Error in handleBoot isolate: ${d.exception}");
  try {
    if (await isDeviceLocked()) {           // (A) MethodChannel or (B) probe-and-catch
      logger.i("handleBoot: device locked (pre-unlock) — deferring reschedule until unlock");
      return;                               // OS redelivers BOOT_COMPLETED after unlock
    }
    await initializeIsolate();              // now INSIDE try/catch (was outside at :20)
    await updateAlarms("handleBoot(): boot reschedule");
    await updateTimers("handleBoot(): boot reschedule");
  } catch (e, st) {
    logger.f("Error in handleBoot isolate: $e\n$st");
  }
}
```

### Pattern 2: Atomic temp-write + rename (STOR-01, D-02)
**What:** Write the full content to a sibling temp file, flush, then `rename()` over the target. `rename` is atomic within one filesystem (the app-private dir is a single FS), so a reader either sees the old complete file or the new complete file — never a truncated one.
**When to use:** Every `saveTextFile` write (and `saveRingtone`); applies transitively to `saveList` and `SettingGroup.save()` which call it.
**Example:**
```dart
// lib/common/utils/list_storage.dart  (Source: dart:io File.rename + standard atomic-write idiom)
Future<void> saveTextFile(String key, String content) async {
  await queue.add(() async {
    final dir = getAppDataDirectoryPathSync();
    final target = File(path.join(dir, '$key.txt'));
    final tmp = File(path.join(dir, '$key.txt.tmp'));   // same dir = same filesystem
    await tmp.writeAsString(content, flush: true);       // flush before swap
    await tmp.rename(target.path);                        // atomic replace
  });
}
```
**Caveat (verified against current code):** the write stays *inside* the existing `queue.add(...)` closure (`list_storage.dart:83`) so it remains serialized with all other writes — no new race. Do not `rename` outside the queued closure. `flutter_foreground_task`'s isolate also writes through this same `queue` instance only when running in the *same* isolate; cross-isolate writes are already coordinated by re-reading from disk (the architecture's documented pattern), so rename introduces no new cross-isolate caveat beyond what exists today.

### Pattern 3: Time-boxed init / non-fatal splash (BOOT-01, D-06)
**What:** Wrap the `main()` init chain (or its slowest awaited segment) in `.timeout(Duration(seconds: N))` (or run it as a guarded future) so a hang or slow recovery degrades to `runApp(App())` with defaults rather than awaiting forever. Today `main.dart:43-50` does `await Future.wait([...])` then `await initializeStorage()` then `await updateAlarms(...)` with **no timeout** — any hang there is a permanent splash.
**When to use:** Around the storage/settings/reschedule init in `main()`. Reschedule failures must not block first paint.
**Example (sketch):**
```dart
// lib/main.dart  (Source: pattern derived from current main.dart init chain)
try {
  await _initStorageAndReschedule().timeout(const Duration(seconds: 8));
} on TimeoutException catch (e) {
  logger.f("main() init timed out — proceeding to UI with current state: $e");
} catch (e) {
  logger.f("main() init failed — proceeding to UI: $e");
}
runApp(const App());   // ALWAYS reached
```

### Pattern 4: Per-entry salvage on list load (BOOT-04, D-04)
**What:** When decoding the alarms list, parse the top-level JSON array first; if *that* fails, return `[]` (whole-list safe default, logged, and set the "alarms lost" flag). If it parses, map each element through `fromJson` inside its own try/catch — keep the good ones, skip+log the bad ones, set the flag if ≥1 was skipped.
**When to use:** `listFromString` / `loadList` for alarms (apply to timers too per D-06 discretion).
**Anti-pattern it replaces:** current `listFromString` (`json_serialize.dart:50-57`) decodes the whole array and maps with no per-element guard, then `rethrow`s — one bad alarm loses the entire list, and `loadList` (`list_storage.dart:58-60`) doesn't even wrap it, so the throw propagates.

### Pattern 5: Single idempotent reschedule funnel (BOOT-03, D-08)
**What:** `updateAlarms()`/`updateTimers()` are *already* idempotent by construction: `updateAlarms()` calls `cancelAllAlarms()` (cancels every id in `alarm_schedule_ids`) and then reschedules each enabled alarm; `scheduleAlarm()` removes the prior `scheduleId` and calls `AndroidAlarmManager.cancel(scheduleId)` before `oneShotAt(scheduleId, …)` — so re-running replaces, not duplicates. The phase work is: (1) make this the *one* funnel both `handleBoot()` and `main()` call (already true); (2) ensure the boot path defers when locked (Pattern 1) so it can't run on partial/locked state; (3) make it tolerant of being run twice in quick succession (boot-then-launch) — which it already is, via stable ids. Verify the `scheduleId` is stable across reload (it is derived from persisted `ScheduleId`/alarm runner ids, not regenerated).
**When to use:** This is the "spine" Phases 2 and 4 reuse — keep its signature stable and document it.

### Anti-Patterns to Avoid
- **Silent catch-to-default that conflates "locked" with "corrupt":** the current `setting_group.dart` outer catch (`:246-249`) and `handle_boot.dart` broad catch swallow both. Distinguish: locked → defer+retry (don't reset data); corrupt → recover to defaults + log + flag. (Pitfall 1.)
- **`json.decode(GetStorage().read(id))` with no null guard** (`setting_group.dart:263-265`): `read` returns `null` when the key is absent → `json.decode(null)` throws. Guard it (D-05).
- **Truncate-in-place writes** (`FileMode.writeOnly`): non-atomic; a kill mid-write corrupts. (STOR-01.)
- **Awaiting reschedule before first paint with no timeout:** turns a slow/failed reschedule into a permanent splash hang. (BOOT-01.)
- **Marking `MainActivity` `directBootAware="true"` without DE-storage handling** (current manifest `:38`): the activity claims to run in Direct Boot but its Flutter engine reads CE storage. Pre-unlock *firing* is out of scope (D-07); consider whether the activity needs `directBootAware` at all (see Q1).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic file replace | A custom "write .new, copy bytes, delete old" dance | `dart:io` `File.rename()` (temp in same dir) | `rename(2)` is the OS-atomic primitive; byte-copy reintroduces a torn-write window. |
| Reschedule-after-reboot | A new boot-reschedule routine | The existing `updateAlarms`/`updateTimers` funnel (already cancel-then-schedule by stable id) | Re-arms idempotently; a parallel routine creates a *fourth* reschedule path and duplicates. |
| Knowing the device is unlocked | A timestamp/heuristic ("has main() ever run?") | Android `UserManager.isUserUnlocked()` (or probe-and-catch the CE read) | The OS owns unlock state; heuristics drift and misfire across OEMs. |
| Surviving reboot at all | Persisting + re-arming alarms from your own table | `android_alarm_manager_plus` `rescheduleOnReboot:true` (already set) | The plugin already re-arms via its `RebootBroadcastReceiver`; the Dart boot path is a *belt-and-suspenders* re-check, not the primary mechanism. (This is *why* dedup matters — see Pitfall 4.) |
| JSON guard | A regex/length pre-check before decode | try/catch around `json.decode` + typed recovery | Only a real parse attempt tells you it's valid; pre-checks pass malformed-but-plausible input. |

**Key insight:** The reboot reschedule problem is **already over-solved** — there are three independent re-arm paths (aamp's `RebootBroadcastReceiver`, Chrono's `flutter_boot_receiver` → `handleBoot`, and the next `main()`). The bug is not "alarms don't re-arm"; it is "they re-arm too eagerly, on locked/partial state, via paths that can collide." The fix is *fewer/guarded* paths feeding *one* idempotent funnel, not more code.

## Runtime State Inventory

> Rename/refactor-relevant categories. This phase changes the **write format/path** (atomic temp file) and the **boot guard**, so runtime-state effects are limited — but two real items exist.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | App-private JSON files in `{getApplicationDocumentsDirectory()}/Clock/*.txt` (`alarms.txt`, `timers.txt`, `alarm_schedule_ids.txt`, `timer_schedule_ids.txt`, `alarm_events.txt`, settings group files keyed by group `id`). All **credential-encrypted** (path_provider docs dir). Atomic-write change must write the `.tmp` sibling into this **same** dir (same FS) or `rename` is non-atomic. | Code edit only — no data migration; format unchanged, only the write *procedure* changes. |
| Live service config | `android_alarm_manager_plus` persists scheduled alarms in its **own** SharedPreferences (`rescheduleOnReboot` store), independent of Chrono's JSON. `flutter_boot_receiver` persists its callback handle in `getSharedPreferences("com.flux.flutter_boot_receiver")` (default = CE). Both are written by `BootReceiver.initialize` / `oneShotAt` at runtime, not in git. | None to migrate. **Relevant to BOOT-02:** the boot-receiver's handle read is itself a CE-storage touch that can throw pre-unlock — the guard must short-circuit *before* the plugin's executor needs it, which it does (guard returns from `handleBoot` after the executor already resolved the handle; if the executor's own handle read throws pre-unlock that is the plugin's concern — see Q1/Pitfall 1). |
| OS-registered state | Manifest-declared boot receivers (`BootBroadcastReceiver`, aamp `RebootBroadcastReceiver`) and their `directBootAware`/`LOCKED_BOOT_COMPLETED` filters are **set at install time from `AndroidManifest.xml`**. Narrowing them (Q1) takes effect on next install/update, not on existing installs until reinstall — but manifest changes always ship with the APK, so no separate re-registration step. | If manifest is narrowed: rebuild + ship; no runtime re-registration needed. |
| Secrets/env vars | None touched. (Signing keys in `key.properties`/`.jks` are unaffected.) | None — verified: this phase touches no secrets. |
| Build artifacts | None. No package rename, no `egg-info`/binary artifacts. l10n regeneration (`flutter gen-l10n`) produces `gen_l10n` output from the new ARB key — a normal build step, not a stale artifact. | Run `flutter gen-l10n` (or rely on `flutter:generate: true` at build) after adding the ARB key. |

**The canonical question — after every file is updated, what runtime systems still have old state?** Existing `alarms.txt` written by the *old* non-atomic path are still valid JSON in the new format (format unchanged) — the new atomic writer reads/writes them transparently. The only "old state" is the aamp + boot-receiver SharedPreferences, which are runtime-managed and re-established on next schedule/boot. **No data migration is required.**

## Common Pitfalls

### Pitfall 1: Boot isolate touches credential-encrypted storage before unlock (BOOT-02 root)
**What goes wrong:** On API 24+ FBE devices, after reboot-before-unlock the device exposes only device-encrypted storage. Chrono's manifest fires `flutter_boot_receiver` on `LOCKED_BOOT_COMPLETED` (`directBootAware="true"`), the plugin runs `handleBoot()` with **no unlock check**, and `initializeIsolate()` → `initializeStorage()` → `getApplicationDocumentsDirectory()` (CE) → `IllegalStateException: ... not available until after user is unlocked`. `handle_boot.dart:20` awaits `initializeIsolate()` *outside* the try/catch, so the throw crashes the isolate with partial reschedule state, and the next foreground launch hangs on that partial state.
**Why it happens:** Chrono *opted into* Direct Boot in its own manifest (the plugin's stock README registers only `BOOT_COMPLETED`, no `directBootAware`) but never added a Dart-side unlock guard. `[VERIFIED: github.com/AhsanSarwar45/flutter_boot_receiver README.md + CHANGELOG.md "1.1.0 Added direct boot support"; android/app/src/main/AndroidManifest.xml:96-142]`
**How to avoid:** Pattern 1 — guard `handleBoot()` on `isUserUnlocked()` and return early when locked; move `initializeIsolate()` inside the try/catch. Optionally narrow the manifest (Q1).
**Warning signs:** Crash reports clustered immediately after reboot; "black screen after restart"; `IllegalStateException` mentioning credential-encrypted storage in logs.

### Pitfall 2: `json.decode(null)` / unguarded decode crashes the load path (BOOT-04/STOR-02 root)
**What goes wrong:** `SettingGroup.load()` (`setting_group.dart:257-265`) does `value = GetStorage().read(id)` in the catch fallback; `read` returns `null` for an absent key; `json.decode(null)` then throws inside `load()`. Separately, `listFromString` (`json_serialize.dart:50-57`) decodes and maps the whole array, `rethrow`ing on any failure, and `loadList` (`list_storage.dart:58-60`) doesn't wrap it — so one corrupt alarm throws out the whole list and can crash the caller.
**Why it happens:** The fallback was written assuming the text file is the only failure mode; the null path and the per-element path were never guarded.
**How to avoid:** Null-guard before `json.decode` in `load()` (recover to defaults if null/empty/invalid); per-entry salvage in `listFromString` (Pattern 4); wrap `loadList`'s decode.
**Warning signs:** "settings reset themselves" / "my alarms disappeared" with no crash *or* a crash on launch after an interrupted write.

### Pitfall 3: Non-atomic `FileMode.writeOnly` leaves a half-written file (STOR-01 root)
**What goes wrong:** `saveTextFile` (`list_storage.dart:82-91`) opens the target with `FileMode.writeOnly` (truncate-in-place) and streams the new content; a process kill between truncate and full write leaves a truncated/empty/partial file — which then fails to decode on next load (feeding Pitfall 2).
**Why it happens:** Truncate-in-place is the default mental model for "save a file"; the crash-window is invisible until a kill lands inside it.
**How to avoid:** Pattern 2 — temp write + `rename`.
**Warning signs:** Empty or truncated `alarms.txt`/settings files after a force-stop or low-memory kill; decode errors referencing a specific list file.

### Pitfall 4: Triple reschedule on reboot → duplicate or racing alarms (BOOT-03 root)
**What goes wrong:** On reboot there are **three** independent re-arm triggers: (1) `android_alarm_manager_plus`'s `RebootBroadcastReceiver` (dynamically enabled because every `oneShotAt` passes `rescheduleOnReboot:true`) re-arms each alarm from the plugin's own store; (2) Chrono's `flutter_boot_receiver` → `handleBoot()` → `updateAlarms()`; (3) the next `main()` → `updateAlarms()`. If any of these run on partial/locked state or interleave, you can get duplicate fires or a missed reschedule.
**Why it happens:** The reboot-survival problem is over-solved by independent mechanisms that don't know about each other.
**How to avoid:** Funnel (2) and (3) through the single idempotent `updateAlarms`/`updateTimers` (Pattern 5) — cancel-by-stable-id then schedule, safe to run N times. Guard (2) to defer when locked (Pattern 1) so it never runs on locked/partial state. (1) is the plugin's own path and is idempotent at the AlarmManager level (same request id replaces). Confirm `scheduleId` stability across reload.
**Warning signs:** An alarm fires twice; a snooze schedule and a fresh schedule both pending for one alarm; QA: reboot with an alarm armed, then open the app — count pending alarms.

### Pitfall 5: The "alarms were lost" notice fires for routine recovery (D-06 scope creep)
**What goes wrong:** Surfacing the notice on *any* recovery (settings defaulted, slow init) trains users to ignore it; the one case that matters (a dropped alarm = possible missed wake-up) gets lost in noise.
**Why it happens:** It's easier to set one "something recovered" flag than to distinguish alarm-loss from routine recovery.
**How to avoid:** Set the user-facing flag **only** when per-entry salvage skipped ≥1 alarm entry or the whole alarm list was reset to `[]`. Everything else is silent + logged (D-06). The notice must be screen-reader reachable and use a localized ARB string.
**Warning signs:** The notice appearing on a clean first launch or after a benign settings default.

## Code Examples

> Sketches derived from current Chrono source + cited primitives. The planner/executor adapts to exact signatures; these show the *shape* of each fix.

### Guarded `SettingGroup.load()` (STOR-02 / D-05)
```dart
// lib/settings/types/setting_group.dart  (replaces :257-268)
Future<void> load() async {
  String? value;
  try {
    value = loadTextFileSync(id);
  } catch (e) {
    logger.e("Error loading $id from file, trying GetStorage fallback: $e");
    value = GetStorage().read(id);          // may be null — DO NOT decode unguarded
  }
  if (value == null || value.isEmpty) {
    logger.e("No stored value for setting group '$id' — using defaults");
    return;                                  // keep schema defaults (D-05: keep fallback, null-safe)
  }
  try {
    loadValueFromJson(json.decode(value));
  } catch (e) {
    logger.e("Invalid JSON for setting group '$id' — using defaults: $e");
    // defaults already in place; no throw
  }
}
```

### Per-entry salvage `listFromString` (BOOT-04 / D-04)
```dart
// lib/common/utils/json_serialize.dart  (replaces :44-58)
List<T> listFromString<T extends JsonSerializable>(String encodedItems) {
  if (!fromJsonFactories.containsKey(T)) {
    throw Exception("No fromJson factory for type '$T'.");   // dev error — keep loud
  }
  final fromJson = fromJsonFactories[T]!;
  late final List<dynamic> rawList;
  try {
    rawList = json.decode(encodedItems) as List<dynamic>;     // top-level structure
  } catch (e) {
    logger.e("Top-level list JSON unparseable for '$T' — recovering to empty: $e");
    SalvageReport.markListReset<T>();                         // sets "alarms lost" flag if T == Alarm
    return [];
  }
  final out = <T>[];
  for (final raw in rawList) {
    try {
      out.add(fromJson(raw) as T);
    } catch (e) {
      logger.e("Skipping corrupt $T entry during salvage: $e");
      SalvageReport.markEntryDropped<T>();                    // sets "alarms lost" flag if T == Alarm
    }
  }
  return out;
}
```
*(Note: `loadList` at `list_storage.dart:58-60` must call this without re-throwing; `loadListSync` at `:49-56` already catches — align both.)*

### Atomic write — see Pattern 2 above.
### Defer-until-unlock guard — see Pattern 1 above.

### One-time localized notice plumbing (D-06)
```dart
// app_en.arb — add (flat key + @metadata, matching the 773-line file's style)
"alarmsResetNotice": "Some alarms could not be restored and were reset. Please check your alarms.",
"@alarmsResetNotice": { "description": "Shown once after boot recovery when ≥1 alarm was dropped/reset" }
// Surface in App/NavScaffold via AppLocalizations.of(context).alarmsResetNotice,
// rendered as a dismissible SnackBar/Banner (Semantics-wrapped, screen-reader reachable),
// gated on the SalvageReport flag, cleared after showing once.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `BOOT_COMPLETED`-only boot receiver | Direct-Boot-aware receivers (`LOCKED_BOOT_COMPLETED` + `directBootAware`) for early-boot apps | Android 7.0 / API 24 (2016) | Alarm apps *can* run pre-unlock, but must NOT touch CE storage there. Chrono opted in but didn't add the guard. `[CITED: developer.android.com/privacy-and-security/direct-boot]` |
| `flutter_boot_receiver` 1.0.0 (BOOT_COMPLETED only) | 1.1.0 "Added direct boot support" (matches `LOCKED_BOOT_COMPLETED`/`QUICKBOOT_POWERON`) | flutter_boot_receiver 1.1.0 | The pinned version is *why* `handleBoot` can fire pre-unlock. No unlock check is provided — the app must guard. `[VERIFIED: github.com/AhsanSarwar45/flutter_boot_receiver CHANGELOG.md]` |
| Truncate-in-place file save | Temp-write + atomic `rename` | Long-standing POSIX best practice | Crash-safe persistence; the previous good file survives a mid-write kill. |

**Deprecated/outdated:**
- The pub.dev *rendered* docs for `flutter_boot_receiver` describe only `BOOT_COMPLETED` and no `directBootAware` — **stale relative to the shipped 1.1.0 source**, which matches `LOCKED_BOOT_COMPLETED`. Trust the source + changelog (verified), not the rendered docs. (Recorded as A2.)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `getApplicationDocumentsDirectory()` on Android returns **credential-encrypted** app storage (so it throws pre-unlock). | Pitfall 1, Runtime State | LOW — Android FBE docs + multiple library reports (hawk #224, Instabug) confirm SharedPreferences/app-files are CE by default; DE requires `createDeviceProtectedStorageContext()`. `[CITED: developer.android.com/privacy-and-security/direct-boot]` If wrong, the guard is harmless (no-op) but BOOT-02 wouldn't reproduce. |
| A2 | `flutter_boot_receiver` 1.1.0 (resolved) matches the master source read here (receiver matches `LOCKED_BOOT_COMPLETED`, no unlock check). | Summary, Pattern 1 | LOW — changelog confirms direct-boot support landed in 1.1.0 (current resolved version); master only adds 1.2.0 license + 1.3.0 namespace, no behavioral boot change. Verify the exact 1.1.0 receiver source if the planner narrows the manifest. |
| A3 | On reboot, `android_alarm_manager_plus` (`rescheduleOnReboot:true`) independently re-arms alarms via its dynamically-enabled `RebootBroadcastReceiver`, creating a *third* reschedule path. | Pitfall 4, Don't Hand-Roll | MEDIUM — documented plugin behavior (`rescheduleOnReboot` + receiver `enabled="false"` flipped on at schedule time); the *fork* (`alarm_show_intent`) was not source-verified this session. Confirm the fork didn't alter reboot behavior during planning. |
| A4 | `scheduleId` is stable across reload (so cancel-then-schedule dedups correctly). | Pattern 5 | MEDIUM — ids are persisted in `alarm_schedule_ids`/`ScheduleId` and not regenerated on load, but the alarm-runner id derivation was not exhaustively traced. Verify during planning (read `schedule_id.dart` + `alarm_runner.dart`). |
| A5 | Native `UserManager.isUserUnlocked()` is reachable from a MethodChannel on `MainActivity` (option A). | Pattern 1 | LOW — standard Android API since API 24; `MainActivity` is a plain `FlutterActivity`. Option B (probe-and-catch) needs no native code if A is undesirable. |

## Open Questions

1. **Should the manifest be narrowed (drop `LOCKED_BOOT_COMPLETED` / `directBootAware`) in addition to the Dart guard?**
   - What we know: The plugin's stock manifest is `BOOT_COMPLETED`-only with no `directBootAware`; Chrono *added* the Direct-Boot opt-in. Removing it would stop `handleBoot()` from firing pre-unlock at the OS level (defense in depth). But some OEMs deliver `BOOT_COMPLETED` itself before full unlock, so the Dart guard is still needed regardless.
   - What's unclear: Whether removing `directBootAware` from `MainActivity` (`:38`) affects the alarm full-screen-intent-over-lock-screen behavior (it shouldn't, since pre-unlock *firing* is out of scope D-07, but verify).
   - Recommendation: **Dart guard is primary and mandatory** (Pattern 1). Manifest narrowing is an optional secondary; if done, keep it minimal (the receiver actions) and test boot on an FBE device. Do NOT remove `directBootAware` from the aamp components (they may legitimately need early arming). Treat as a planning decision, not a locked default.

2. **Does the `flutter_boot_receiver` executor's own callback-handle read (default CE SharedPreferences) throw pre-unlock, before our Dart guard can run?**
   - What we know: `FlutterBackgroundExecutor` reads `getSharedPreferences("com.flux.flutter_boot_receiver")` (CE). If that read throws pre-unlock, the Dart callback never even starts — meaning the *plugin* fails before our guard, but **fails safely** (no Chrono code runs, no partial reschedule).
   - What's unclear: Whether that native read throws or silently returns 0 (handle absent) on a locked device across OEMs.
   - Recommendation: This is *acceptable either way* under D-07 (defer-until-unlock) — if the plugin can't start pre-unlock, deferral happens for free. The Dart guard covers the case where it *does* start (e.g., on a device that delivers the broadcast at/after unlock). Verify on-device; if the plugin itself crashes loudly pre-unlock, manifest narrowing (Q1) becomes more attractive.

3. **Timeout duration for the time-boxed splash (Claude's discretion per D-06).**
   - What we know: Init does timezone load, package/device info, notifications, alarm-manager init, storage seeding, settings load, and a full reschedule — cold-start on a slow device can take seconds.
   - Recommendation: Start at ~6–8s for the storage+reschedule segment specifically (not the whole `Future.wait`), tune on-device. The goal is "never infinite," not "fast."

## Environment Availability

> This phase changes app code + manifest; building/verifying needs the Flutter toolchain and an FBE Android device/emulator. No new external services.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Build, l10n gen, tests | Assumed (CI pins 3.22.2) | 3.22.2 | — |
| Android device/emulator API 24+ with secure lock (PIN/pattern) + FBE | On-device verification of BOOT-01/02/03 (reboot-before-unlock) | **Unknown in this env** | — | Emulator with screen lock set; `adb reboot` then test before unlock. **No software fallback** — the boot-before-unlock path can only be *truly* validated on-device. |
| `flutter gen-l10n` | The new "alarms reset" ARB string | Comes with Flutter SDK (`flutter:generate: true`) | — | — |
| Existing `test/` infra (`flutter_test`, `withClock`/`Clock.fixed`) | Unit tests for atomic write, salvage, guarded decode, idempotent reschedule | Present (`test/{alarm,settings,common,...}`) | SDK | — |

**Missing dependencies with no fallback:**
- A secure-lock FBE Android device/emulator for the **reboot-before-unlock** validation of BOOT-01/02/03. The code guard can be unit-tested (probe-and-catch / mocked `isUserUnlocked`), but the *real* pre-unlock crash only reproduces on-device. Flag a manual verification step in the plan.

**Missing dependencies with fallback:**
- None — all build tooling is standard Flutter.

## Project Constraints (from CLAUDE.md)

- **Tech stack:** Flutter 3.22.x / Dart 3.4+, Android-only; Kotlin 1.8, Java 17. **minSdk 23** is the *milestone* target but is raised in **Phase 4** — this phase's `build.gradle` still has `minSdkVersion 21`. The Direct Boot guard must therefore tolerate API 21–23 (Direct Boot is API 24+, so the guard no-ops below 24). New deps must support this toolchain — **this phase adds none.**
- **Architecture:** No state-management library; `setState` + `ListenerManager` + isolate `IsolateNameServer` ports. New config follows `SettingGroup` JSON pattern. (The "alarms lost" notice uses `setState`/a flag, not a new state lib.)
- **Background execution:** Alarm firing in a separate isolate; the boot path (`handleBoot`) is its own background isolate spawned by `flutter_boot_receiver` — the unlock guard lives there.
- **Logging conventions:** `logger.t/i/e/f` from `lib/developer/logic/logger.dart` (`logger.e` for recovered errors, `logger.i` for lifecycle/deferral, `logger.f` for isolate-fatal). Reuse — no new logging infra.
- **Serialization:** `toJson()`/`fromJson()` contract; `Json = Map<String, dynamic>?` typedef. Per-entry salvage operates on this contract.
- **Naming/files:** `snake_case.dart`, `UpperCamelCase` classes, files match primary class. Test files mirror source under `test/`.
- **No unsafe logging:** do not log alarm payloads beyond what existing patterns do; remove the `print(setting.value)` leak (`dynamic_toggle_setting_card.dart:39`) **only if** working in settings-card code (out of this phase's core scope — note, don't force).
- **Accessibility:** the one-time notice MUST be screen-reader reachable (`Semantics`) and localized.
- **Licensing:** clean-room; not relevant to this phase (no scanner/Alarmy code).

## Sources

### Primary (HIGH confidence)
- `github.com/AhsanSarwar45/flutter_boot_receiver` — `CHANGELOG.md` ("1.1.0 Added direct boot support"), `README.md` (stock manifest = `BOOT_COMPLETED` only, no `directBootAware`), `android/src/main/AndroidManifest.xml` (empty `<application>` — receiver is app-declared), `BootBroadcastReceiver.java` (matches `LOCKED_BOOT_COMPLETED`/`QUICKBOOT_POWERON`, no unlock check), `BootHandlerService.java` (JobIntentService + background isolate), `FlutterBackgroundExecutor.java` (reads default CE SharedPreferences), `lib/flutter_boot_receiver.dart` (`BootReceiver.initialize(callback)` API). Fetched via `gh api`. `[VERIFIED]`
- `developer.android.com/privacy-and-security/direct-boot` — CE vs DE storage, `LOCKED_BOOT_COMPLETED`/`USER_UNLOCKED`/`BOOT_COMPLETED` timeline, `UserManager.isUserUnlocked()`, `createDeviceProtectedStorageContext()`, `directBootAware`, API 24+. `[CITED]`
- Chrono source read this session: `android/app/src/main/AndroidManifest.xml` (`:38` MainActivity `directBootAware`, `:91-142` boot receivers + `LOCKED_BOOT_COMPLETED` + `directBootAware`), `lib/system/logic/handle_boot.dart` (`:20` `initializeIsolate` outside try/catch), `lib/system/logic/initialize_isolate.dart`, `lib/common/utils/list_storage.dart` (`:82-91` non-atomic write, `:14` queue), `lib/common/utils/json_serialize.dart` (`:44-58` `listFromString` rethrow), `lib/settings/types/setting_group.dart` (`:257-268` unguarded decode + GetStorage fallback), `lib/settings/logic/initialize_settings.dart` (`:55-60` `clearSettingsOnDebug`), `lib/main.dart` (`:43-50` no-timeout init), `lib/alarm/logic/update_alarms.dart` (`cancelAllAlarms` + reschedule funnel), `lib/alarm/logic/schedule_alarm.dart` (`:47,79-93` cancel-then-`oneShotAt`, `rescheduleOnReboot:true`), `lib/alarm/types/alarm.dart` (`:249-348` schedule/update/disable/handleDismiss), `lib/common/data/paths.dart` (`getApplicationDocumentsDirectory`), `android/app/src/main/kotlin/.../MainActivity.kt` (plain FlutterActivity), `pubspec.yaml`/`pubspec.lock` (resolved versions). `[VERIFIED]`
- `pubspec.lock` — resolved: `flutter_boot_receiver 1.1.0` (pub.dev), `android_alarm_manager_plus 4.0.1` (fork `alarm_show_intent`, ref `ae6c11c3`), `flutter_foreground_task 6.5.0` (fork). `[VERIFIED]`

### Secondary (MEDIUM confidence)
- pub.dev `android_alarm_manager_plus` changelog / freeCodeCamp tutorial — `rescheduleOnReboot` default `false`, `RebootBroadcastReceiver` ships `enabled="false"` and is dynamically enabled when a `rescheduleOnReboot:true` alarm is registered. `[CITED]`
- `.planning/research/PITFALLS.md`, `SUMMARY.md`, `.planning/codebase/CONCERNS.md`, `ARCHITECTURE.md` — corroborating line-level root causes (boot, dual-store, non-atomic write, `json.decode(null)`). `[CITED]`

### Tertiary (LOW confidence — validate on hardware)
- pub.dev *rendered* `flutter_boot_receiver` docs — describe `BOOT_COMPLETED` only; **stale vs shipped 1.1.0 source**; do not rely on for boot-action behavior.
- Exact pre-unlock behavior of the plugin's native handle read across OEMs (Q2) — verify on-device.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new deps; all versions resolved from `pubspec.lock`; relevant APIs (`File.rename`, `json.decode`, `UserManager.isUserUnlocked`) are stable SDK/OS primitives.
- Architecture / Direct-Boot plumbing (primary target): HIGH — resolved from the plugin's actual Java source + changelog + Chrono's own manifest; the BOOT-02 mechanism is fully traced.
- Reschedule idempotency (BOOT-03): MEDIUM-HIGH — `updateAlarms` is verifiably cancel-then-schedule; the third-path (aamp fork) reboot behavior (A3) and `scheduleId` stability (A4) need a short planning confirmation.
- Pitfalls: HIGH — each maps to a confirmed source line.
- On-device boot behavior: MEDIUM — code-level fix is high-confidence; the reboot-before-unlock reproduction requires hardware (flagged).

**Research date:** 2026-05-30
**Valid until:** ~2026-06-29 (stable — no fast-moving deps; the only mutable input is the aamp fork branch, which is already pinned by resolved-ref).
