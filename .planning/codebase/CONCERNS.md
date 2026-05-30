# Codebase Concerns

**Analysis Date:** 2026-05-30

---

## Tech Debt

**Unimplemented setting-schema migration system:**
- Issue: `loadValueFromJson` in `SettingGroup` has a version field and a comment `//TODO: Add migration code`. The only migration present is a partial, hardcoded block for `AlarmSettings`. All other `SettingGroup` version bumps have no migration logic, so old persisted data silently loads into the new schema without transformation.
- Files: `lib/settings/types/setting_group.dart:198-249`
- Impact: Upgrading a setting schema version for anything other than `AlarmSettings` will silently discard old user data rather than migrating it.
- Fix approach: Implement a versioned migration dispatch table keyed by setting group name and version number.

**Dual storage strategy (GetStorage + flat text files):**
- Issue: The app uses two independent persistence backends: `get_storage` (key-value store) and plain `.txt` files managed by `list_storage.dart`. The fallback in `SettingGroup.load()` silently reads from `GetStorage` when the text file is missing, which means the two stores can drift.
- Files: `lib/common/utils/list_storage.dart`, `lib/settings/types/setting_group.dart:257-268`
- Impact: Users migrating from an older version may get data from the wrong store. The silent fallback hides the problem.
- Fix approach: Decide on one canonical store; add an explicit one-time migration step with logging on first run.

**Hardcoded setting-lookup strings scattered everywhere:**
- Issue: Settings are accessed by magic string paths throughout the codebase (e.g., `appSettings.getGroup("Alarm").getSetting("Dismiss Action Type")`). There is no compile-time safety. Any rename of a setting name silently breaks all consumers.
- Files: `lib/alarm/screens/alarm_notification_screen.dart:79-83`, `lib/timer/screens/timer_notification_screen.dart:28-37`, `lib/widgets/logic/update_widgets.dart:9-45`, and many others.
- Impact: Typos and renames cause runtime exceptions caught only by broad `catch (e)` blocks.
- Fix approach: Introduce typed constants or a generated accessor layer for setting path segments.

**`EnableConditionParameter` naming acknowledged as poor:**
- Issue: The file `lib/settings/types/setting_enable_condition.dart` opens with `// TODO: OMG ALL THESE NAMES ARE SO BAD, PLEASE THINK OF NEW ONES :(`. The API uses `EnableConditionParameter`, `EnableConditionEvaluator`, `GeneralConditionEvaluator`, `ValueConditionEvaluator`, and `CompoundConditionEvaluator` — opaque naming that makes the condition system hard to extend.
- Files: `lib/settings/types/setting_enable_condition.dart`
- Impact: Ongoing readability/maintenance friction in one of the more complex parts of settings logic.
- Fix approach: Rename to domain-meaningful terms (e.g., `SettingVisibilityRule`, `DependsOnSetting`, `CompositeVisibilityRule`).

**`SpinnerTimePicker` has an unimplemented `didUpdateWidget`:**
- Issue: `// TODO: implement didUpdateWidget` is present in `SpinnerTimePicker` with no implementation, alongside a noted Flutter assertion crash risk.
- Files: `lib/common/widgets/spinner_time_picker.dart:309`
- Impact: Widget state may not update correctly when its parent rebuilds with new props.
- Fix approach: Implement `didUpdateWidget` to synchronise the scroll controllers with incoming `widget` values.

**Commented-out code left as entire file contents:**
- Issue: Several Dart files consist entirely of commented-out code, meaning dead feature code is tracked in git indefinitely.
  - `lib/alarm/widgets/show_next_schedule_snackbar.dart` — entire snackbar feature commented out
  - `lib/common/logic/lock_screen_flags.dart` — entire `LockScreenFlagManager` commented out (was using `flutter_windowmanager`)
  - `lib/theme/logic/theme_extension.dart` — entire file commented out
  - `lib/settings/screens/reliability_instructions.dart` — full screen commented out
  - `lib/settings/screens/vendor_list_screen.dart` — full screen commented out
- Files: All five files listed above.
- Impact: Increases codebase noise, confuses contributors about what is active.
- Fix approach: Delete dead files; if the feature may return, track it via a git branch or issue instead.

**Debug `clearSettingsOnDebug` runs by default in debug builds:**
- Issue: `initializeStorage()` (called from `lib/main.dart`) defaults `clearSettingsOnDebug = true`, which erases all user data on every debug-mode launch.
- Files: `lib/settings/logic/initialize_settings.dart:55-60`, `lib/main.dart:46`
- Impact: Developers must remember to pass `false` or risk destroying all local test data on every run.
- Fix approach: Default the flag to `false`; opt in to clearing explicitly during development.

---

## Known Bugs

**Double subscription in `watchTextFile`:**
- Symptoms: Every call to `watchTextFile` registers `callback` on the same stream twice — once saved to `subscription` (tracked in `watcherSubscriptions`) and once discarded.
- Files: `lib/common/utils/list_storage.dart:26-27`
- Trigger: Any call to `watchList` or `watchTextFile`; the callback fires twice per file change event.
- Workaround: `watchList`/`watchTextFile` are currently not called anywhere in the production app (only defined), so the bug is dormant. It will surface if the file-watching API is enabled.

**SQL injection in city search:**
- Symptoms: User input from the search field is interpolated directly into a raw SQLite query string without parameterisation.
- Files: `lib/clock/screens/search_city_screen.dart:33-34`
- Trigger: Any search query containing SQLite metacharacters (e.g., `'`, `%`, `_`, or SQL keywords).
- Workaround: The database is bundled read-only timezone data, so SQL injection cannot modify data; however, it can crash the query or return unexpected results. Use `rawQuery('... LIKE ?', ['%${text}%'])` instead.

**`TimerNotificationScreen` action widget built before `initState`:**
- Symptoms: `actionWidget` is initialised as a field initializer that calls `getTimerById(widget.scheduleIds.last)` (which can return `null`) and accesses `appSettings`. If the timer list is not yet loaded, `?.addLength.floor()` returns `null` and `toString()` produces `'null:00'` in the UI label.
- Files: `lib/timer/screens/timer_notification_screen.dart:28-37`
- Trigger: Opening the timer notification screen when the timer list has not fully initialised.
- Workaround: `initState` rebuilds `actionWidget` inside a try/catch, so the fallback `SlideNotificationAction` takes over, but silently.

---

## Security Considerations

**SQL injection risk in timezone search:**
- Risk: Unsanitised user text inserted into a `rawQuery` string.
- Files: `lib/clock/screens/search_city_screen.dart:33`
- Current mitigation: The SQLite database is read-only and bundled (not a network database), so data exfiltration or modification is not possible. The worst case is a malformed query crash.
- Recommendations: Replace string interpolation with SQLite parameterised queries: `rawQuery('SELECT * FROM Timezones WHERE City || Country LIKE ? LIMIT 10', ['%$text%'])`.

**Overly broad CI permissions (`permissions: write-all`):**
- Risk: The release workflow grants `write-all` permissions to the GitHub Actions job, meaning any compromised action in the job can write to any repository resource, create releases, modify branch protection, etc.
- Files: `.github/workflows/android-release.yml:13`
- Current mitigation: None.
- Recommendations: Scope permissions to minimum required: `contents: write` for creating releases; remove all others.

**`print()` statement left in production widget code:**
- Risk: `print(widget.setting.value)` in a production widget leaks setting values to device logs.
- Files: `lib/settings/widgets/dynamic_toggle_setting_card.dart:39`
- Current mitigation: None.
- Recommendations: Remove the `print` call entirely.

---

## Performance Bottlenecks

**`SELECT *` from timezone database on every keypress:**
- Problem: The city search listener fires on every character typed, issues a full `SELECT * FROM Timezones WHERE ...` raw query, and calls `setState` with the results. There is no debounce.
- Files: `lib/clock/screens/search_city_screen.dart:26-46`
- Cause: The `_filterController.addListener` callback is synchronous and triggers the async database query immediately for every keystroke.
- Improvement path: Add a debounce (e.g., 200–300 ms) before issuing the query.

**Lazy `loadListSync` inside `setState` in `SearchCityScreen.initState`:**
- Problem: `loadListSync('favorite_cities')` reads a file synchronously on the main thread inside `setState` during widget init.
- Files: `lib/clock/screens/search_city_screen.dart:63-65`
- Cause: The sync file read blocks the UI thread; for large favorite city lists this will cause a visible frame drop.
- Improvement path: Use `loadList<City>` (async) with a `FutureBuilder` or load before `setState`.

**Rising-volume implementation uses `Future.delayed` loops without cancellation tracking:**
- Problem: The volume ramp in `RingtonePlayer._play` schedules 11 `Future.delayed` callbacks. The cancellation flag `_stopRisingVolume` is shared state but the futures are not tracked or cancelled; they can fire after the player has been stopped and a new alarm started.
- Files: `lib/audio/types/ringtone_player.dart:119-129`
- Cause: `Future.delayed` is fire-and-forget; `_stopRisingVolume` is a static bool that only the most recent call controls.
- Improvement path: Replace with a `Timer`-based approach that can be `cancel()`-ed, or use `CancelableCompleter`.

---

## Fragile Areas

**Settings access by magic string — runtime crash on typo:**
- Files: All files calling `appSettings.getGroup(...)`, `getSetting(...)`, `getSettingItem(...)` — concentrated in `lib/alarm/screens/`, `lib/timer/screens/`, `lib/widgets/logic/`, `lib/settings/data/`.
- Why fragile: `getGroup`, `getSetting`, and `getSettingItem` all call `firstWhere` and rethrow on miss. Any string typo causes a runtime exception.
- Safe modification: Always verify against the schema definition in `lib/settings/data/settings_schema.dart` and `lib/alarm/data/alarm_settings_schema.dart` before adding or renaming a setting string.
- Test coverage: No unit tests cover the settings-path resolution chain.

**`SettingGroup.load()` falls back to `GetStorage` silently:**
- Files: `lib/settings/types/setting_group.dart:257-268`
- Why fragile: If the text file is missing (first run after schema change, file deletion, backup restore), `GetStorage().read(id)` may return `null`, which then causes `json.decode(null)` to throw, and the outer `catch (e)` swallows the error leaving settings in an undefined state.
- Safe modification: Add a null check before `json.decode(value)` and fall back to defaults explicitly.
- Test coverage: No tests cover the load-failure path.

**`json_serialize.dart` factory registry must be manually updated:**
- Files: `lib/common/utils/json_serialize.dart:22-38`
- Why fragile: Adding a new `JsonSerializable` type requires a manual entry in `fromJsonFactories`. Missing this step causes a runtime exception (`No fromJson factory for type`) the first time a list of that type is loaded.
- Safe modification: When adding a new serializable type, always add its factory to this map.
- Test coverage: No test validates that all registered `JsonSerializable` subtypes are present in the map.

**Unpinned git dependencies (mutable branch refs):**
- Files: `pubspec.yaml:28-81`
- Why fragile: Four dependencies are sourced from git at `ref: master`, `ref: main`, or `ref: alarm_show_intent` — all mutable branch tips. An upstream push to any of these branches changes the resolved package without a `pubspec.yaml` change, breaking reproducible builds silently.
  - `android_alarm_manager_plus` — `ref: alarm_show_intent` (fork branch)
  - `flex_color_picker` — `ref: master` (fork)
  - `home_widget` — `ref: main` (fork)
  - `flutter_foreground_task` — `ref: master` (fork)
- Safe modification: Pin each to a specific commit SHA.
- Test coverage: CI rebuilds will fail non-deterministically if any upstream changes.

---

## Dependencies at Risk

**`flutter_html: ^3.0.0-beta.2` and `http: ^0.13.6` — dead packages in pubspec:**
- Risk: Both packages are declared in `pubspec.yaml` but their only consumers (`reliability_instructions.dart`, `vendor_list_screen.dart`) are fully commented out. The packages are fetched, compiled, and increase the app binary unnecessarily.
- Impact: Larger binary, slower pub get, additional unvetted transitive dependencies.
- Migration plan: Remove both from `pubspec.yaml` until the features are re-implemented. Re-add only when the screens are restored.

**`intl: any` with `dependency_overrides: intl: any`:**
- Risk: The `intl` version is unconstrained in both `dependencies` and `dependency_overrides`. This means `intl` may resolve to incompatible versions between environments and pub upgrades.
- Impact: Potentially inconsistent date/number formatting behaviour across build environments.
- Migration plan: Pin `intl` to a specific version range (e.g., `^0.19.0`) once the Flutter SDK constraint is known.

**Four forked git dependencies without upstream sync plan:**
- Risk: `android_alarm_manager_plus`, `flex_color_picker`, `home_widget`, `flutter_foreground_task` are all forks by the project author or organisation. As the upstream packages release new versions, the forks will diverge, making security patches and API updates harder to apply.
- Impact: Long-term maintenance burden; security fixes in upstream may not reach the app.
- Migration plan: Document which changes are fork-specific; periodically rebase forks or upstream the changes.

---

## Test Coverage Gaps

**No tests for settings persistence or migration:**
- What's not tested: `SettingGroup.load()`, `SettingGroup.save()`, and the version-migration block in `loadValueFromJson`.
- Files: `lib/settings/types/setting_group.dart`
- Risk: Silent data loss or corruption on schema version changes goes undetected until reported by users.
- Priority: High

**No tests for alarm/timer notification screens:**
- What's not tested: `AlarmNotificationScreen` and `TimerNotificationScreen` — particularly the fallback `SlideNotificationAction` path triggered by the `catch (e)` block, and the `_setNextWidget` task-navigation loop.
- Files: `lib/alarm/screens/alarm_notification_screen.dart`, `lib/timer/screens/timer_notification_screen.dart`
- Risk: Regressions in the most user-critical path (alarm dismissal) may ship undetected.
- Priority: High

**No tests for `RingtonePlayer`:**
- What's not tested: Audio playback, volume ramp, vibration lifecycle, and stop/pause behaviour.
- Files: `lib/audio/types/ringtone_player.dart`
- Risk: The rising-volume `Future.delayed` cancellation bug and multi-player state bugs are invisible to CI.
- Priority: Medium

**No tests for `list_storage.dart` file I/O:**
- What's not tested: `saveTextFile`, `loadTextFileSync`, `saveList`, `loadList`, and the `watchTextFile` double-subscription bug.
- Files: `lib/common/utils/list_storage.dart`
- Risk: File storage regressions (data not written, wrong encoding, queue ordering) are only found in manual testing.
- Priority: Medium

**`test/alarm/logic/alarm_time.dart` is not a test file (missing `_test` suffix):**
- What's not tested: The file `test/alarm/logic/alarm_time.dart` contains test helpers but no `group`/`test` calls at the top level. It is not discovered by the test runner unless explicitly imported.
- Files: `test/alarm/logic/alarm_time.dart`
- Risk: Any tests intended to live in this file are silently skipped.
- Priority: Low

**No integration or end-to-end tests:**
- What's not tested: Full alarm creation → scheduling → notification → dismissal flows; backup/restore round-trips; widget home-screen update cycle.
- Risk: Multi-layer bugs across isolate boundaries (alarm isolate, background fetch, notification callbacks) are not covered by unit tests alone.
- Priority: Medium

---

*Concerns audit: 2026-05-30*
