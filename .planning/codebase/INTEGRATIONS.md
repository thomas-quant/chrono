# External Integrations

**Analysis Date:** 2026-05-30

## APIs & External Services

**Localization/Translation:**
- Hosted Weblate (`https://hosted.weblate.org/projects/chrono`) - Crowdsourced translation platform. Linked from in-app About screen (`lib/settings/screens/about_screen.dart`). Translations delivered as ARB files committed to `lib/l10n/`.

**Funding:**
- Patreon (`https://www.patreon.com/vicolo`) - Linked from in-app About screen (`lib/settings/screens/about_screen.dart`). Patron data fetched offline via `scripts/patreons.py` from a local CSV export, converted to `assets/patreons/patreons.json`, and committed.

**Contributor Data:**
- GitHub REST API (`https://api.github.com/repos/{owner}/{repo}/contributors`) - Polled by `scripts/contributors.py` (Python) to fetch contributor avatars and metadata. Output committed to `assets/contributors/git.json` and `assets/contributors/avatars/`. Not called at runtime.
  - Auth: None (public repo, unauthenticated)

**Battery Optimization Guidance:**
- Don't Kill My App (`https://dontkillmyapp.com`) - Opened via `url_launcher` from the reliability settings (`lib/settings/data/general_settings_schema.dart:336`). Not an API; opened in browser.

**Source / License:**
- GitHub (`https://github.com/vicolo-dev/chrono`) - Linked from About screen. License URL (`blob/master/LICENSE`) opened in browser via `url_launcher`.

## Data Storage

**Databases:**
- SQLite (embedded, via `sqflite: 2.3.2`)
  - Used for: Timezone city search database only
  - Asset file: `assets/timezones.db` (shipped with the app)
  - Initialization: `lib/clock/logic/timezone_database.dart` — copies asset to app data directory on first launch
  - Query location: `lib/clock/screens/search_city_screen.dart`
  - Connection: File path resolved via `path_provider` to app documents directory

**Key-Value Storage:**
- `get_storage: 2.1.1` (GetStorage) — lightweight persistent key-value storage
  - Used for: Settings persistence, onboarding state, list data initialization flags
  - Key usage locations:
    - `lib/app.dart` — reads `'onboarded'` flag
    - `lib/onboarding/screens/onboarding_screen.dart` — writes `'onboarded'` flag
    - `lib/common/utils/list_storage.dart` — `'init_$key'` flags
    - `lib/settings/logic/initialize_settings.dart` — erases all storage on settings reset
  - Storage location: App data directory on device

**File Storage:**
- Local filesystem only — no cloud file storage
- Custom audio ringtones are selected by the user via `file_picker` and stored by path reference
- App data directory managed via `path_provider`

**Caching:**
- None — no in-memory cache layer or external cache service

## Authentication & Identity

**Auth Provider:**
- None — this is a fully local, offline app with no user accounts or authentication

## Monitoring & Observability

**Error Tracking:**
- None — no Crashlytics, Sentry, or equivalent configured

**Coverage:**
- Codecov — test coverage reports uploaded via `codecov/codecov-action@v3` in `.github/workflows/tests.yml`. Token not visible in workflow (uses default GITHUB_TOKEN environment for public repos).

**Logs:**
- `logger: 2.4.0` (dart `logger` package) — structured, leveled logging
  - Logger instance created in `lib/developer/logic/logger.dart`
  - Log levels used: `logger.t` (trace), `logger.i` (info), `logger.f` (fatal)
  - Log output goes to console only (no remote log sink)
  - Log files written to `android/app/src/main/logs/` (device-side)

## CI/CD & Deployment

**Hosting:**
- Google Play Store — production releases as AAB (App Bundle), `prod` flavor
  - Build command: `flutter build appbundle --flavor prod`
- GitHub Releases — APK distribution for sideloading/F-Droid, `prod` flavor
  - Build command: `flutter build apk --release --split-per-abi --flavor prod`
- F-Droid — fastlane supply metadata in `fastlane/metadata/android/` (multilingual descriptions and changelogs)

**CI Pipeline:**
- GitHub Actions — three workflows:
  - `.github/workflows/android-build.yml` — triggered on PR to any branch; builds `dev` flavor APK, uploads to artifacts (3-day retention)
  - `.github/workflows/android-release.yml` — triggered on tag push; builds `prod` AAB + APK, creates draft GitHub Release with auto-generated changelog
  - `.github/workflows/tests.yml` — triggered on push/PR to any branch; runs `flutter test --coverage`, uploads coverage to Codecov
- Flutter version pinned to `3.22.2` stable across all workflows
- Java 17 (AdoptOpenJDK) via `actions/setup-java@v3`

**Release Automation:**
- `mikepenz/release-changelog-builder-action@v4.1.0` — auto-generates changelogs from PR labels (`feature`, `enhancement`, `bug`, `test`)
- `ncipollo/release-action@v1` — creates GitHub draft releases with artifacts
- `damienaicheh/extract-version-from-tag-action@v1.1.0` — extracts version components from git tags

**Signing:**
- Android keystore: `android/app/release-key.jks` (gitignored)
- Properties: `android/key.properties` (gitignored) — `keyAlias`, `keyPassword`, `storePassword`
- CI secrets: `KEYSTORE_JKS_RELEASE` (base64-encoded JKS), `KEY_PASSWORD`, `KEY_STORE_PASSWORD`, `KEY_ALIAS`
- Release builds: minification enabled (`minifyEnabled true`, `shrinkResources true`)

## Webhooks & Callbacks

**Incoming:**
- Android System Intents handled by `MainActivity` (registered in `android/app/src/main/AndroidManifest.xml`):
  - `android.intent.action.QUICK_CLOCK`
  - `android.intent.action.SHOW_ALARMS`
  - `android.intent.action.SHOW_TIMERS`
  - `android.intent.action.SET_ALARM`
  - `android.intent.action.SET_TIMER`
  - `android.intent.action.DISMISS_ALARM`
  - `android.intent.action.DISMISS_TIMER`
  - `es.antonborri.home_widget.action.LAUNCH` (home widget tap)
- Intent handling implemented in `lib/system/logic/handle_intents.dart` using `receive_intent`

**Outgoing:**
- `url_launcher` opens URLs in the system browser — no programmatic outbound HTTP at runtime
- `http` package is a dependency but currently only present in commented-out code (`lib/settings/screens/reliability_instructions.dart`, `lib/settings/screens/vendor_list_screen.dart`)

## Android System Integrations

**Alarm Scheduling:**
- `android_alarm_manager_plus` (git fork, `alarm_show_intent` branch) — schedules exact alarms via `AlarmService` and `AlarmBroadcastReceiver`
- `flutter_boot_receiver` — reschedules alarms after device reboot via `BootBroadcastReceiver` and `BootHandlerService`
- Requires permissions: `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`

**Foreground Service:**
- `flutter_foreground_task` (git fork, vicolo-dev) — runs during active alarms/timers as `ForegroundService` (type `specialUse`)

**Background Fetch:**
- `background_fetch` — periodic background task (minimum 15-minute interval) to update alarm/timer states without user interaction

**Home Screen Widgets:**
- `home_widget` (git fork, AhsanSarwar45) — powers two Android app widgets:
  - `AnalogueClockWidgetProvider` (`android/app/src/main/kotlin/com/vicolo/chrono/AnalogueClockWidgetProvider.kt`)
  - `DigitalClockWidgetProvider` (`android/app/src/main/kotlin/com/vicolo/chrono/DigitalClockWidgetProvider.kt`)
- Widget update logic: `lib/widgets/logic/update_widgets.dart`

**Notifications:**
- `awesome_notifications: 0.9.3` — manages all app notification channels and full-screen alarm notifications
  - Channels defined in `lib/notifications/data/notification_channel.dart`
  - Alarm notifications: `lib/notifications/logic/alarm_notifications.dart`
  - Stopwatch notifications: `lib/stopwatch/logic/stopwatch_notification.dart`
  - Requires permissions: `USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE`

**Quick Actions:**
- `quick_actions` — app icon long-press shortcuts defined in `lib/system/logic/quick_actions.dart`

**Auto-Start:**
- `auto_start_flutter` — redirects users to manufacturer-specific auto-start settings for battery optimization (`lib/settings/data/general_settings_schema.dart`)

---

*Integration audit: 2026-05-30*
