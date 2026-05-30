# Phase 1: Storage & Boot Reliability - Pattern Map

**Mapped:** 2026-05-30
**Files analyzed:** 11 (10 modified Dart/Kotlin/XML + 1 new ARB key; 1 optional new native MethodChannel)
**Analogs found:** 11 / 11 (this is a brownfield hardening phase — the "analog" for each change is almost always the *current implementation of the same file* plus an in-repo convention exemplar)

> **Orientation for the planner:** This phase MODIFIES existing files. There are no greenfield "copy this whole file" analogs. For each change below, the **Current state** excerpt is the code being replaced/wrapped, and the **Convention to follow** excerpt is the in-repo pattern the change must match (logging level, `queue` serialization, `toJson`/`fromJson` contract, MethodChannel id style, ARB key style, IsolateNameServer port usage). Do NOT relitigate D-01/D-04 (text storage kept; SQLite/per-file rejected).

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/common/utils/list_storage.dart` (`saveTextFile` :82-91, `saveRingtone` :93-108, `loadList` :58-60) | utility (storage choke point) | file-I/O | itself (current non-atomic write) + existing `queue.add()` closure pattern in same file | self / exact |
| `lib/common/utils/json_serialize.dart` (`listFromString` :44-58) | utility (serialization) | transform / file-I/O | itself + `loadListSync` log-and-return-`[]` pattern (`list_storage.dart:49-56`) | self / exact |
| `lib/settings/types/setting_group.dart` (`load()` :257-268) | model / settings (dual-store load) | file-I/O | itself + the existing log-and-continue catch in `loadValueFromJson` (`:246-249`) | self / exact |
| `lib/system/logic/handle_boot.dart` (`handleBoot` :8-27) | system (boot isolate entry point) | event-driven | itself + isolate `FlutterError.onError`+`logger.f` pattern in `initialize_isolate.dart` | self / exact |
| `lib/system/logic/initialize_isolate.dart` (:12-24) | system (isolate init) | request-response (init chain) | itself (no structural change; called only after guard passes) | self / exact |
| `lib/main.dart` (init chain :43-50) | config / entry point | request-response (init orchestration) | itself + `handleBoot()`'s try/catch reschedule pattern | self / exact |
| `lib/alarm/logic/update_alarms.dart` (`updateAlarms` :41-60) | service (reschedule funnel) | batch / event-driven | itself — **already idempotent**, treat as the D-08 spine; document, don't rewrite | self / exact |
| `lib/timer/logic/update_timers.dart` (parallel funnel) | service (reschedule funnel) | batch / event-driven | `update_alarms.dart` (mirror) | role-match (mirror) |
| `lib/app.dart` (`_AppState` / `_messangerKey` :58, root route :206-225) | component (UI surface for notice) | request-response | `App` already owns `scaffoldMessengerKey` + uses `AppLocalizations` (:204) | self / exact |
| `lib/l10n/app_en.arb` (new `alarmsResetNotice` key) | config (l10n) | n/a | existing flat-key + `@key`-metadata entries (`app_en.arb:1-12`) | self / exact |
| `android/.../MainActivity.kt` (optional `isUserUnlocked` MethodChannel) | native (platform channel) | request-response | existing `com.vicolo.chrono/documents` channel id style + the already-declared `CHANNEL = "com.vicolo.chrono/alarm"` constant in MainActivity | role-match |
| `android/app/src/main/AndroidManifest.xml` (optional boot-action narrowing :104-139) | config (manifest) | n/a | itself | self / exact |

---

## Pattern Assignments

### `lib/common/utils/list_storage.dart` (utility, file-I/O) — STOR-01 / D-02

**Analog:** itself (the `saveTextFile` body) + the surrounding `queue.add()` convention.

**Convention to follow — every write is wrapped in the single shared `queue`** (must stay inside it; do NOT rename outside the queued closure):
```dart
final queue = Queue();                              // :14 — one shared serializer for ALL file I/O

Future<void> saveTextFile(String key, String content) async {
  await queue.add(() async {                         // :83 — keep the atomic write INSIDE this closure
    String appDataDirectory = getAppDataDirectoryPathSync();
    File file = File(path.join(appDataDirectory, '$key.txt'));
    if (!file.existsSync()) {
      file.createSync();
    }
    await file.writeAsString(content, mode: FileMode.writeOnly);  // :89 — NON-ATOMIC truncate-in-place (the bug)
  });
}
```

**Current state being replaced** (`saveTextFile` :82-91, and the same `FileMode.writeOnly` in `saveRingtone` :93-108): truncate-in-place; a kill between truncate and full write leaves a partial file.

**Fix shape (temp+rename, stays inside `queue.add`):** write to a `$key.txt.tmp` sibling in the **same dir** (`getAppDataDirectoryPathSync()` — same filesystem so `rename` is POSIX-atomic), `writeAsString(..., flush: true)`, then `tmp.rename(target.path)`. Apply the identical pattern to `saveRingtone` (`writeAsBytes` → temp → rename) per D-06 discretion ("apply unless a reason not to surfaces"). `saveList`/`SettingGroup.save()` call `saveTextFile` transitively, so they inherit the fix for free — do not touch them for atomicity.

**`loadList` must wrap the salvage** (`:58-60`) — current code does NOT catch:
```dart
Future<List<T>> loadList<T extends JsonSerializable>(String key) async {
  return listFromString<T>(await loadTextFile(key));   // :59 — throws propagate; align with loadListSync below
}
```
The sync sibling already does the right thing — **match it** (the convention for "load list, never throw"):
```dart
List<T> loadListSync<T extends JsonSerializable>(String key) {
  try {
    return listFromString<T>(loadTextFileSync(key));
  } catch (e) {
    logger.e("Error loading list ($key): $e");        // :53 — logger.e for recovered storage error
    return [];
  }
}
```
> The per-entry salvage itself lives in `listFromString` (below); once that no longer rethrows, `loadList`'s top-level wrap mirrors `loadListSync`.

---

### `lib/common/utils/json_serialize.dart` (utility, transform) — BOOT-04 / D-04 (per-entry salvage)

**Analog:** itself + the factory-lookup convention it already uses.

**Current state being replaced** (`listFromString` :44-58) — decodes the whole array, maps with NO per-element guard, then `rethrow`s (one bad alarm = whole list lost):
```dart
List<T> listFromString<T extends JsonSerializable>(String encodedItems) {
  if (!fromJsonFactories.containsKey(T)) {
    throw Exception(
        "No fromJson factory for type '$T'. Please add one in the file 'common/utils/json_serialize.dart'");  // dev error — KEEP loud
  }
  try {
    List<dynamic> rawList = json.decode(encodedItems) as List<dynamic>;   // :50 — top-level decode (guard separately)
    Function fromJson = fromJsonFactories[T]!;
    List<T> list = rawList.map<T>((json) => fromJson(json)).toList();     // :52 — no per-entry guard (the bug)
    return list;
  } catch (e) {
    logger.e("Error decoding string: ${e.toString()}");
    rethrow;                                                              // :56 — rethrow loses the whole list
  }
}
```

**Convention to follow — the existing factory-lookup style is preserved.** The factory map and the `fromJsonFactories[T]!` lookup stay exactly as-is:
```dart
final fromJsonFactories = <Type, Function>{
  Alarm: (Json json) => Alarm.fromJson(json),       // :23
  ClockTimer: (Json json) => ClockTimer.fromJson(json),
  ScheduleId: (Json json) => ScheduleId.fromJson(json),
  // ...
};
```

**Fix shape (per-entry salvage — see RESEARCH.md Code Examples for the full sketch):**
1. Keep the "no factory for `T`" throw loud (dev error, not a data error).
2. Wrap the **top-level** `json.decode(...) as List` in its own try/catch → on failure log via `logger.e` and return `[]` (whole-list reset; set the "alarms lost" flag if `T == Alarm`).
3. Loop `rawList`, mapping each element through `fromJson` inside its **own** try/catch → keep good ones, `logger.e`+skip bad ones (set the flag if `T == Alarm` and ≥1 skipped).
4. Do NOT rethrow.
> Flag mechanism (where the "alarms lost" boolean lives) is Claude's discretion (D-06 / RESEARCH "SalvageReport" sketch) — must be readable by `main.dart`/`App` and set only for `Alarm` loss (Pitfall 5: never for routine recovery).

---

### `lib/settings/types/setting_group.dart` (model, file-I/O) — STOR-02 / D-05 (null-guard the dual store)

**Analog:** itself + the log-and-continue catch already present at `:246-249`.

**Current state being replaced** (`load()` :257-268) — `GetStorage().read(id)` returns `null` for an absent key → `json.decode(null)` throws:
```dart
Future<void> load() async {
  String value;
  try {
    value = loadTextFileSync(id);
  } catch (e) {
    logger.e("Error loading $id: $e");
    value = GetStorage().read(id);     // :263 — may be null; assigned to non-nullable String
  }
  loadValueFromJson(json.decode(value));   // :265 — UNGUARDED decode (the crash vector)
}
```

**Convention to follow — the file's own log-and-continue recovery** (already used a few lines up in `loadValueFromJson`), reuse this exact shape, do NOT throw:
```dart
} catch (e) {
  logger.e(
      "Error loading value from json in setting group ($name): ${e.toString()}");  // :247 — logger.e, keep defaults, continue
}
```

**Fix shape (see RESEARCH.md Code Examples "Guarded SettingGroup.load()"):** make `value` a `String?`; KEEP the GetStorage fallback (D-05 — do not remove it, do not add migration); if `value == null || value.isEmpty` → `logger.e` "using defaults" and `return` (schema defaults already in place); wrap `loadValueFromJson(json.decode(value))` in try/catch → on invalid JSON `logger.e` and keep defaults. Distinguish "absent/empty" (silent-ish default) from "present but corrupt" (logged) — but never throw.

---

### `lib/system/logic/handle_boot.dart` (system, event-driven) — BOOT-01 / BOOT-02 / D-07

**Analog:** itself + the isolate fatal-error convention.

**Current state being replaced** (`handleBoot` :8-27) — `initializeIsolate()` is awaited **OUTSIDE** the try/catch and there is **no unlock guard**:
```dart
@pragma('vm:entry-point')                               // :7 — KEEP this pragma (isolate entry point)
void handleBoot() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.f("Error in handleBoot isolate: ${details.exception.toString()}");  // :17 — logger.f for isolate-fatal
  };

  await initializeIsolate();                            // :20 — OUTSIDE try/catch + touches CE storage pre-unlock (crash)
  try {
    await updateAlarms("handleBoot(): Update alarms on system boot");   // :22 — the idempotent funnel
    await updateTimers("handleBoot(): Update timers on system boot");
  } catch (e) {
    logger.f("Error in handleBoot isolate: ${e.toString()}");
  }
}
```

**Convention to follow — `logger.f` for isolate-fatal, `logger.i` for lifecycle/deferral** (CONVENTIONS.md logging levels). The deferral log must be `logger.i` ("device locked — deferring"); any caught crash stays `logger.f`.

**Fix shape (see RESEARCH.md Pattern 1):** at the very top, before any storage touch, `if (await isDeviceLocked()) { logger.i(...deferring...); return; }`; then move `await initializeIsolate()` INSIDE the try/catch alongside the two reschedule calls. The OS redelivers `BOOT_COMPLETED` after unlock, so deferral loses nothing. `isDeviceLocked()` mechanism is Claude's discretion: (A) native `UserManager.isUserUnlocked()` over a MethodChannel (recommended), or (B) probe-and-catch a cheap CE read. API-gate: Direct Boot is API 24+, so on `androidInfo?.version.sdkInt < 24` the guard no-ops (use `androidInfo` from `lib/system/data/device_info.dart`).

---

### `lib/system/logic/initialize_isolate.dart` (system, request-response) — no structural change

**Analog:** itself. **No edit required for correctness** — it is now only ever called *after* the `handleBoot` guard passes (device unlocked). Listed here so the planner knows NOT to add a guard inside it (the guard belongs in `handleBoot`, the only Chrono-owned boot path). Its init order (`initializeStorage` → `initializeSettings` → ... at :18-19) is the same chain `main.dart` runs.

---

### `lib/main.dart` (config / entry point, request-response) — BOOT-01 / D-06 (time-box) + D-08 (same funnel) + notice flag

**Analog:** itself + `handleBoot()`'s try/catch-around-reschedule shape.

**Current state being hardened** (:43-50) — `await Future.wait([...])` then `await initializeStorage()` then `await updateAlarms(...)` with **NO timeout** → any hang = permanent splash:
```dart
await Future.wait(initializeData);     // :43
await initializeStorage();             // :46 — relies on initializeAppDataDirectory
await initializeSettings();            // :47
await updateAlarms("Update Alarms on Start");   // :49 — SAME funnel as handleBoot (D-08 — good, keep)
await updateTimers("Update Timers on Start");   // :50
// ...
runApp(const App());                   // :56 — must ALWAYS be reached
```

**Fix shape (see RESEARCH.md Pattern 3):** wrap the storage+reschedule segment (`:46-50`, NOT the whole `Future.wait`) in `.timeout(Duration(seconds: ~6-8))` (duration is Claude's discretion) with `on TimeoutException`/`catch` → `logger.f(...)` and fall through to `runApp` regardless. `updateAlarms`/`updateTimers` stay the single funnel both here and `handleBoot` call (D-08 — already true; preserve it). After init, read the "alarms lost" flag set during salvage and pass it to `App` (or have `App` read it) so it can show the one-time notice.

---

### `lib/alarm/logic/update_alarms.dart` (service, batch) — BOOT-03 / D-08 (the idempotent spine)

**Analog:** itself — **already idempotent by construction.** The phase work is to *document and preserve* this as the shared primitive (Phases 2 & 4 reuse it), NOT rewrite it.

**Convention to preserve — cancel-all-by-stable-id then reschedule + notify-via-port:**
```dart
Future<void> cancelAllAlarms() async {
  List<ScheduleId> scheduleIds = await loadList<ScheduleId>('alarm_schedule_ids');  // :12 — stable persisted ids
  for (var scheduleId in scheduleIds) {
    await cancelAlarm(scheduleId.id, ScheduledNotificationType.alarm);              // :15
  }
  scheduleIds.clear();
  await saveList('alarm_schedule_ids', scheduleIds);                                // :18
}

Future<void> updateAlarms(String description) async {
  await cancelAllAlarms();                          // :42 — cancel-then-schedule = safe to run N times
  List<Alarm> alarms = await loadList("alarms");    // :44
  for (Alarm alarm in alarms) { await alarm.update(description); /* ... */ }
  await saveList("alarms", alarms);                 // :55
  // Notify other isolates listening for alarm updates:
  SendPort? sendPort = IsolateNameServer.lookupPortByName(updatePortName);          // :58 — port convention
  sendPort?.send("updateAlarms");                                                   // :59
}
```
**Idempotency confirmed (resolves RESEARCH assumptions A4):** `scheduleAlarm` (`schedule_alarm.dart:40-93`) removes the prior `scheduleId` from the persisted list (`:41`), calls `AndroidAlarmManager.cancel(scheduleId)` (`:47`) BEFORE `oneShotAt(startDate, scheduleId, ...)` (`:79`) — same stable id replaces, never duplicates. `ScheduleId.fromJson` (`schedule_id.dart:10-16`) already null-guards. **No change needed for BOOT-03** beyond (a) the boot guard (Pattern 1, in `handle_boot.dart`) so this never runs on locked/partial state, and (b) keeping `main.dart` + `handleBoot` both funnelling here.

---

### `lib/timer/logic/update_timers.dart` (service, batch) — mirror of update_alarms

**Analog:** `lib/alarm/logic/update_alarms.dart` (mirror). Same `cancelAllTimers` → reschedule → `IsolateNameServer` `"updateTimers"` send pattern. Same treatment: preserve as part of the single funnel; apply the same "no edit unless funnel/idempotency requires it." (Read it during planning to confirm it mirrors `update_alarms.dart` before assuming.)

---

### `lib/app.dart` (component, request-response) — D-06 one-time localized notice

**Analog:** itself — `App` **already has every primitive the notice needs.**

**Convention to follow — `App` already owns a ScaffoldMessenger and uses AppLocalizations:**
```dart
class _AppState extends State<App> {
  final _messangerKey = GlobalKey<ScaffoldMessengerState>();   // :58 — use this to show a SnackBar
  // ...
  return MaterialApp(
    scaffoldMessengerKey: _messangerKey,                       // :190 — wired
    localizationsDelegates: AppLocalizations.localizationsDelegates,  // :204 — l10n ready
    supportedLocales: AppLocalizations.supportedLocales,       // :205
    // ...
    initialRoute: Routes.rootRoute,                            // :201 → NavScaffold after onboarding (:222)
```

**Fix shape:** after first frame on the normal (post-onboarding) route, if the "alarms lost" flag is set, show a dismissible localized notice via `_messangerKey.currentState?.showSnackBar(...)` (or a banner) using `AppLocalizations.of(context)!.alarmsResetNotice`; wrap in `Semantics` so it is screen-reader reachable (D-06 / accessibility constraint); clear the flag after showing once. Gate strictly on the salvage flag (Pitfall 5 — never on routine recovery). Exact widget (SnackBar vs banner) and where the flag is cleared are Claude's discretion. NavScaffold (`nav_scaffold.dart`) is the post-onboarding landing if the planner prefers to surface it there instead of `App`.

---

### `lib/l10n/app_en.arb` (config / l10n) — D-06 new string

**Analog:** the existing flat-key + `@key`-metadata entries at the top of the file.

**Convention to follow — flat key, then `@key` metadata object with `description`** (779-line file, English baseline only; other locales come via Weblate, NOT in this phase):
```json
"clockTitle": "Clock",
"@clockTitle": {
  "description": "Title of the clock screen"
},
```
(Some entries use an empty `"@key": {}` — but a user-facing recovery string SHOULD include a `description`.)

**Fix shape (see RESEARCH.md Code Examples):** add `alarmsResetNotice` + `@alarmsResetNotice` with a description like "Shown once after boot recovery when ≥1 alarm was dropped/reset". Run `flutter gen-l10n` (or rely on `flutter: generate: true`) so `AppLocalizations.alarmsResetNotice` is generated. Add ONLY to `app_en.arb`.

---

### `android/.../MainActivity.kt` (native, request-response) — OPTIONAL, BOOT-02 mechanism (A)

**Analog:** the existing `com.vicolo.chrono/documents` MethodChannel (invoked from `android_platform_file.dart:28`/`:64` and `ringtones.dart:58`) + the already-declared (currently unused) channel constant in MainActivity.

**Convention to follow — namespaced `com.vicolo.chrono/<topic>` channel id; MainActivity already imports the MethodChannel classes and declares a CHANNEL constant:**
```kotlin
class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.vicolo.chrono/alarm"        // :18 — already declared, handler not yet wired

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)         // :21 — add MethodChannel(...).setMethodCallHandler { } here
    }
}
```
Dart-side invocation convention (from `android_platform_file.dart`):
```dart
static const methodChannel = MethodChannel('com.vicolo.chrono/documents');   // namespaced const
final result = await methodChannel.invokeMethod('getFileChunk', arguments);  // invokeMethod by string name
```

**Fix shape (only if mechanism A chosen over probe-and-catch):** register a `MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.vicolo.chrono/<name>")` in `configureFlutterEngine`; handle e.g. `"isUserUnlocked"` → return `getSystemService(UserManager::class.java)?.isUserUnlocked ?: true` (true on API < 24 / null service). **Caveat (BOOT-02):** the boot isolate (`handleBoot`) runs WITHOUT a `MainActivity` / FlutterEngine attached, so a `MainActivity`-scoped channel may not be reachable from the boot isolate — the planner must verify the channel is reachable from the boot isolate or implement the native check via the application/plugin registrant or fall back to mechanism (B) probe-and-catch (no native code). This is the key open implementation decision for the guard. (RESEARCH Pattern 1, A5; Open Question Q2.)

---

### `android/app/src/main/AndroidManifest.xml` (config) — OPTIONAL, BOOT-02 defense-in-depth

**Analog:** itself. Current boot receiver registers `BOOT_COMPLETED` + `LOCKED_BOOT_COMPLETED` + `QUICKBOOT_POWERON` with `directBootAware="true"` (`:131-139`), and `MainActivity` is also `directBootAware="true"` (`:38`).

**Fix shape (secondary, NOT primary — Dart guard is mandatory regardless; RESEARCH Open Question Q1):** optionally drop `LOCKED_BOOT_COMPLETED` from the `BootBroadcastReceiver` actions (`:137`) so `handleBoot` can't fire pre-unlock at the OS level. Do NOT touch the `android_alarm_manager_plus` components' `directBootAware`. Whether to remove `directBootAware` from `MainActivity` (`:38`) is a planning decision — verify it doesn't break the alarm full-screen-intent-over-lock-screen path first. Treat as belt-and-suspenders only.

---

## Shared Patterns

### Recovery logging (apply to ALL storage/boot changes)
**Source:** `lib/developer/logic/logger.dart` (singleton `logger`)
**Apply to:** every change in this phase — reuse the singleton, add NO new logging infra.
```dart
logger.e("Error loading list ($key): $e");   // recovered storage/decode error (list_storage.dart:53, setting_group.dart:247)
logger.i("...");                              // lifecycle / boot-deferral ("device locked — deferring")
logger.f("Error in handleBoot isolate: ...$e");  // isolate-fatal (handle_boot.dart:17,25)
logger.t("Scheduled alarm $scheduleId ...");  // low-level scheduling detail (schedule_alarm.dart:95)
```
Mapping: corrupt-data recovery (D-03/D-04) → `logger.e`; boot deferral (D-07) → `logger.i`; isolate crash → `logger.f`. (CONVENTIONS.md / CLAUDE.md logging levels.)

### Serialized file I/O via the shared `queue`
**Source:** `lib/common/utils/list_storage.dart:14` `final queue = Queue();`
**Apply to:** the atomic-write change (STOR-01). The temp-write + rename MUST stay inside `queue.add(() async { ... })` so it remains serialized with every other write — introduces no new race. Do NOT add a second queue or rename outside the queued closure.

### `JsonSerializable` `toJson()`/`fromJson()` contract
**Source:** `lib/common/types/json.dart` (`typedef Json = Map<String, dynamic>?`), exemplar `lib/common/types/schedule_id.dart`
**Apply to:** per-entry salvage (D-04) operates on this contract — each list element round-trips through `fromJsonFactories[T]!` (`json_serialize.dart:22-38`). `fromJson` constructors already null-guard their `Json?` arg (e.g. `ScheduleId.fromJson` returns a sentinel on null) — salvage's per-entry try/catch is the second line of defense for malformed (non-null but wrong-shape) entries. Format is UNCHANGED this phase (D-01) — no migration.

### Cross-isolate update notification via `IsolateNameServer`
**Source:** `lib/system/logic/initialize_isolate_ports.dart:10-11` (register `updatePortName`), `update_alarms.dart:58-59` (lookup + send)
**Apply to:** the reschedule funnel (D-08). Keep the existing `IsolateNameServer.lookupPortByName(updatePortName)` + `sendPort?.send("updateAlarms"/"updateTimers")` signalling intact — the funnel coordinates the main isolate's `ListenerManager.notifyListeners(...)` over it. Do not add new ports.

### Namespaced platform-channel id
**Source:** `com.vicolo.chrono/documents` (`android_platform_file.dart:28,64`, `ringtones.dart:58`), `com.vicolo.chrono/alarm` (`MainActivity.kt:18`)
**Apply to:** the optional native unlock-check channel — follow `com.vicolo.chrono/<topic>` naming and `invokeMethod('<name>', args)` style.

### Localized, screen-reader-reachable user notice
**Source:** `lib/app.dart` (`_messangerKey` :58, `AppLocalizations` :204) + ARB key style `app_en.arb:1-12`
**Apply to:** the D-06 notice — flat ARB key (English only), `AppLocalizations.of(context)`, `Semantics`-wrapped SnackBar/banner via the existing `ScaffoldMessenger`.

---

## No Analog Found

None. Every change maps to an existing file's current implementation plus an in-repo convention exemplar (this is a brownfield hardening phase, not a greenfield build). RESEARCH.md patterns supplement (not replace) these in-repo analogs.

The **only** genuinely new artifacts are:
1. One ARB key (`alarmsResetNotice`) — style analog: `app_en.arb` existing entries.
2. The "alarms lost" flag mechanism — Claude's discretion (D-06); no existing analog, but it is a trivial bool/file flag, not a new subsystem (do NOT introduce a state-management library — use a module-level flag / file, per CLAUDE.md architecture constraint).
3. (Optional) native `isUserUnlocked` MethodChannel handler — style analog: `com.vicolo.chrono/documents` channel; reachability from the boot isolate is the open implementation question (Q2).

---

## Metadata

**Analog search scope:** `lib/common/utils/`, `lib/system/logic/`, `lib/settings/types/`, `lib/settings/logic/`, `lib/alarm/logic/`, `lib/common/types/`, `lib/common/data/`, `lib/`, `lib/l10n/`, `lib/system/types/`, `lib/audio/logic/`, `android/app/src/main/kotlin/`, `android/app/src/main/AndroidManifest.xml`
**Files scanned (read):** list_storage.dart, json_serialize.dart, handle_boot.dart, setting_group.dart (:230-269 + :1-19), initialize_isolate.dart, main.dart, update_alarms.dart, logger.dart, MainActivity.kt, android_platform_file.dart, initialize_settings.dart, paths.dart, initialize_isolate_ports.dart, schedule_alarm.dart, schedule_id.dart, app.dart, app_en.arb (head), AndroidManifest.xml (boot + activity blocks); grep for MethodChannel / IsolateNameServer / native channel handlers
**Pattern extraction date:** 2026-05-30
