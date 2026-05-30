# Technology Stack

**Analysis Date:** 2026-05-30

## Languages

**Primary:**
- Dart 3.4.0+ - All Flutter application logic in `lib/`
- Kotlin 1.8.0 - Native Android code in `android/app/src/main/kotlin/com/vicolo/chrono/`

**Secondary:**
- XML - Android resources, manifests, and widget layouts in `android/app/src/main/res/`
- Python 3.x - Build scripts in `scripts/contributors.py` and `scripts/patreons.py`

## Runtime

**Environment:**
- Flutter 3.22.2 (stable channel, pinned in CI workflows)
- Android only — no iOS, web, or desktop targets configured in build workflows

**Package Manager:**
- Pub (Flutter/Dart package manager)
- Lockfile: `pubspec.lock` present and committed

## Frameworks

**Core:**
- Flutter 3.22.x (SDK `>=3.22.0`) - Full UI framework; Material Design 3
- Material Design 3 with `uses-material-design: true` in `pubspec.yaml`

**Testing:**
- `flutter_test` (SDK built-in) - Widget and unit tests in `test/`
- No additional test framework required; uses built-in Flutter testing

**Build/Dev:**
- Gradle 7.6.4 - Android build system (`android/gradle/wrapper/gradle-wrapper.properties`)
- Kotlin 1.8.0 - JVM target `1.8` (`android/build.gradle`)
- Java 17 - CI build environment (`android-build.yml`, `android-release.yml`)
- `change_app_package_name: ^1.1.0` - Dev utility for renaming the app package
- `dependency_validator: ^3.2.3` - Dev utility for checking unused dependencies
- `dart_code_metrics: ^5.5.1` - Static analysis beyond base linting
- `flutter_lints: ^3.0.1` - Standard Flutter lint rules

**Localization:**
- `flutter_localizations` (SDK built-in) - ARB-based l10n
- `intl: 0.19.0` - Internationalization support
- `locale_names: ^1.1.1` - Human-readable locale display names
- ARB files in `lib/l10n/` covering 20+ languages (bn, cs, de, en, es, fa, fr, hu, it, ko, nb, nl, pl, pt, ru, sr, ta, tr, uk, vi, zh)
- Config: `l10n.yaml` (`arb-dir: lib/l10n`, template: `app_en.arb`)

## Key Dependencies

**Critical:**
- `android_alarm_manager_plus: 4.0.1` (git fork) - Android exact alarm scheduling; forked at `https://github.com/AhsanSarwar45/plus_plugins` branch `alarm_show_intent`
- `awesome_notifications: ^0.9.3` - Full-screen notifications and alarm notification display
- `flutter_foreground_task: 6.5.0` (git fork) - Foreground service for active alarms/timers; forked at `https://github.com/vicolo-dev/flutter_foreground_task`
- `flutter_boot_receiver: ^1.1.0` - Reschedule alarms after device reboot
- `background_fetch: ^1.3.7` - Periodic background task for alarm/timer updates
- `just_audio: ^0.9.31` - Audio playback for ringtones and alarm sounds
- `sqflite: ^2.2.2` - Local SQLite database for timezone data (`assets/timezones.db`)
- `get_storage: ^2.1.1` - Lightweight key-value persistent storage for settings

**Infrastructure:**
- `timezone: ^0.9.1` - Timezone-aware datetime handling; uses bundled `assets/timezones.db`
- `path_provider: ^2.0.11` - Access to app data directories
- `permission_handler: ^11.3.1` - Runtime permission requests (alarms, storage, audio)
- `device_info_plus: ^10.1.0` - Android version detection for permission handling
- `package_info_plus: ^6.0.0` - App version and build info
- `home_widget: 0.7.0` (git fork) - Android home screen widgets; forked at `https://github.com/AhsanSarwar45/home_widget`
- `vibration: ^1.7.6` - Haptic feedback for alarms
- `audio_session: ^0.1.13` - Audio focus management
- `flutter_system_ringtones: ^0.0.6` - Access to system ringtone list
- `file_picker: ^8.0.7` - Custom audio file selection
- `receive_intent: ^0.2.5` - Handle Android intents (SET_ALARM, SHOW_ALARMS, etc.)
- `quick_actions: ^1.0.7` - App shortcut actions on long-press launcher icon
- `auto_start_flutter: ^0.1.1` - Guide users to manufacturer auto-start settings
- `move_to_background: ^1.0.2` - Send app to background on back navigation
- `flutter_show_when_locked: ^0.0.4` - Show alarm screen over lock screen
- `flutter_fgbg: ^0.3.0` - Detect app foreground/background transitions

**UI:**
- `flutter_slidable: ^3.1.0` - Swipe actions on list items
- `flutter_animate: ^4.5.0` - Declarative animation framework
- `dynamic_color: ^1.7.0` - Material You dynamic color (Android 12+)
- `material_color_utilities: ^0.8.0` - HCT color space and tonal palettes
- `flex_color_picker: 3.3.0` (git fork) - Color picker widget; forked at `https://github.com/vicolo-dev/flex_color_picker`
- `table_calendar: ^3.0.8` - Calendar widget for date alarm scheduling
- `timer_builder: ^2.0.0` - Reactive widgets that rebuild on a timer
- `analog_clock: ^0.1.1` - Static analog clock face widget
- `animated_analog_clock: ^0.1.0` - Animated analog clock face widget
- `introduction_screen: ^3.1.12` - Onboarding flow screens
- `app_settings: ^5.1.1` - Deep links into system settings screens
- `flutter_html: ^3.0.0-beta.2` - Render HTML content (used for reliability instructions)
- `url_launcher: ^6.2.2` - Open URLs in browser/apps
- `flutter_oss_licenses: ^3.0.2` - Display OSS license information in-app

**Utilities:**
- `watcher: ^1.1.0` - File system watching
- `queue: ^3.1.0+2` - Task queuing
- `fuzzywuzzy: ^1.1.2` - Fuzzy string matching (timezone city search)
- `vector_math: ^2.1.4` - Vector mathematics for UI animations
- `mime: ^1.0.6` - MIME type detection for audio files
- `clock: ^1.1.1` - Mockable clock abstraction for testing
- `http: ^0.13.6` - HTTP client (imported, currently only used in commented-out code)
- `logger: ^2.4.0` - Structured logging

## Configuration

**Environment:**
- No `.env` files used
- Signing configured via `android/key.properties` (gitignored) and `android/app/release-key.jks` (gitignored)
- CI secrets: `KEY_PASSWORD`, `KEY_STORE_PASSWORD`, `KEY_ALIAS`, `KEYSTORE_JKS_RELEASE` in GitHub Actions secrets

**Build:**
- `pubspec.yaml` - Dart/Flutter dependencies and asset declarations
- `analysis_options.yaml` - Linting config (extends `package:flutter_lints/flutter.yaml`)
- `android/build.gradle` - Root Gradle config, Kotlin version `1.8.0`
- `android/app/build.gradle` - App Gradle config; compileSdk 34, minSdk 21, two flavors: `prod` (app name "Chrono") and `dev` (app name "Chrono Dev", suffix `.dev`)
- `l10n.yaml` - Localization config
- `.vscode/settings.json` - VS Code project settings

## Platform Requirements

**Development:**
- Flutter SDK 3.22.x (stable)
- Java 17 JDK (for Gradle)
- Android SDK with compile SDK 34
- NDK version managed by Flutter

**Production:**
- Android only (minSdk 21 = Android 5.0+, targeting SDK 34)
- Distributed via: Google Play Store (AAB, `prod` flavor) and GitHub Releases (APK, `prod` flavor)
- F-Droid compatible (fastlane metadata present in `fastlane/metadata/android/`)
- Two flavors: `prod` for release distribution, `dev` for development/testing

---

*Stack analysis: 2026-05-30*
