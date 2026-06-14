# 04 — Lock-Screen / Full-Screen-Intent Spike & GAP-B Verdict

**Plan:** 04-08 (GAP-B closure — full-screen-intent / `showWhenLocked` path)
**Status:** authorable audit + decision COMPLETE; per-device on-device verdict PENDING (04-08 Task 4, blocking-human)
**Subsumes:** the deferred **04-03** lock-screen camera spike. 04-03 measured the same question
(does a live preview surface + decode over a SECURE keyguard via Chrono's `FlutterShowWhenLocked().show()`
window across ≥2 OEMs). That spike is now folded into this doc — do NOT also run 04-03 separately.

---

## 1. GAP-B root-cause audit (04-08 Task 1 — read-only, line-referenced)

GAP-B (from `04-VERIFICATION.md`, truth #13): on the test device the fired alarm did **not** surface
over a secure (PIN/pattern) keyguard — the user had to unlock and tap the notification. This is a
different subsystem from GAP-A (camera layout): it is the **full-screen-intent (FSI) / `showWhenLocked`**
path. Audited end-to-end:

| # | Audit question | Finding | Evidence (file:line) |
|---|----------------|---------|----------------------|
| 1 | Is `USE_FULL_SCREEN_INTENT` declared in the manifest? | **YES** | `android/app/src/main/AndroidManifest.xml:8-9` (`<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />`). Also present: `WAKE_LOCK` (6-7), `SCHEDULE_EXACT_ALARM` (15-16), `USE_EXACT_ALARM` (17). `MainActivity` is `singleTop` + `directBootAware="true"` (42,47). NOT present (by design): `android:showWhenLocked`/`android:turnScreenOn` on the activity (Chrono uses the `flutter_show_when_locked` plugin instead) and no `DISABLE_KEYGUARD`/`SYSTEM_ALERT_WINDOW` (the deferred overlay fallback — out of scope). |
| 2 | On Android 14+ (API 34, the compileSdk), is the FSI permission auto-granted, or does it need a runtime grant the app never requests? | The app **already requests it at startup.** `requestPermissionToSendNotifications(permissions: [NotificationPermission.Alert, NotificationPermission.FullScreenIntent])` is called every cold start when notifications are not yet allowed. | `lib/notifications/logic/notifications.dart:7-13` (request), called from `initializeNotifications()` → `lib/notifications/logic/notifications.dart:21` → `lib/main.dart:38`. Also re-requestable from settings: `lib/settings/data/general_settings_schema.dart:322`. |
| 3 | Does `awesome_notifications` **0.9.3** even expose an FSI-permission API? | **YES.** `NotificationPermission.FullScreenIntent` is a valid enum member on the installed `awesome_notifications 0.9.3+1` and is passed to `requestPermissionToSendNotifications`. Conclusive evidence: this code **compiles GREEN in CI** (`tests.yml` 212/212 + `test-apk.yml` dev-APK build, per STATE.md) against `0.9.3+1` — a non-existent enum member would fail the build. | `pubspec.lock` → `awesome_notifications … version: "0.9.3+1"`; `lib/notifications/logic/notifications.dart:11`. (Context7/ctx7 unavailable in this env — in-repo compile-against-0.9.3 is the authoritative evidence.) |
| 4 | Is the alarm notification channel at `Max`/`High` importance + `criticalAlerts` (required for FSI)? | **YES.** `importance: NotificationImportance.Max`, `criticalAlerts: true`, `locked: true`. A channel below Max/High would suppress the FSI — it is at Max. | `lib/notifications/data/notification_channel.dart:19-20` (and `locked: true` at 18). |
| 5 | Does the notification CONTENT request the full-screen intent + wake/lock flags + Alarm category? | **YES.** `fullScreenIntent: true`, `wakeUpScreen: true`, `locked: true`, `category: NotificationCategory.Alarm`. | `lib/notifications/logic/alarm_notifications.dart:81-85`. |
| 6 | Is `FlutterShowWhenLocked().show()` invoked BEFORE the activity is pushed (so the window carries `FLAG_SHOW_WHEN_LOCKED` over the keyguard)? | **YES, correct ordering.** `show()` runs first, then `pushNamedAndRemoveUntil`. `hide()` runs on close. | `lib/notifications/logic/alarm_notifications.dart:182` (`show()`) precedes the push at `:190`; `hide()` at `:105`. |

**Audit conclusion:** Every grantable / configurable lever on the FSI + `showWhenLocked` path is **already
correctly wired** — the manifest permission is declared, the Android-14 runtime FSI grant is already
requested at startup via a supported 0.9.3 API, the channel is `Max` + `criticalAlerts`, the notification
sets `fullScreenIntent/wakeUpScreen/locked/category:Alarm`, and `FlutterShowWhenLocked().show()` fires in
the correct order before the push. There is **no missing permission to request** and **no
mis-configured notification/channel field to correct.**

---

## 2. Classification & fix-or-accept decision (04-08 Task 1 → Task 2)

**Classification: [C] — expected OEM / Android-14 no-go.**

- It is **not [A]** (grantable-permission fix): the `USE_FULL_SCREEN_INTENT` runtime grant is already
  declared (manifest) **and** already requested at runtime (`notifications.dart:11`) on a supported
  0.9.3 API — there is nothing un-requested to surface.
- It is **not [B]** (notification-config fix): channel importance (`Max`), `criticalAlerts`, `category:
  Alarm`, `fullScreenIntent`, `wakeUpScreen`, `locked`, and the `show()`-before-push ordering are all
  already correct.
- It **is [C]:** with all app-side levers correct, an alarm that still does not surface over a SECURE
  keyguard is **OEM keyguard policy / Android-14 FSI behavior** — i.e. some OEMs (and Android 14's FSI
  tightening) block an activity composited over a secure lock screen, or require the user to have
  explicitly toggled the system "Allow full-screen notifications" setting for this app. That is outside
  app code and is the **expected, accepted no-go** per **D-LOCK-SHIP**.

**Task 2 action taken: NO code change.** Per the [C] classification, no permission request is added and
no notification/channel field is altered. Specifically **not** added (explicitly out of scope / deferred):
the overlay path — `SYSTEM_ALERT_WINDOW` / `DISABLE_KEYGUARD` / runtime keyguard-dismiss. No new
dependency is introduced (`awesome_notifications`, `flutter_show_when_locked`, `app_settings` are all
existing deps), so the **BUILD-02 zero-ML-Kit / F-Droid-clean** gate is preserved.

**Why accepting [C] is safe (T-04-21 / T-04-11 disposition = mitigate):** the **default-on escape hatch**
is the universal safety net and the **unlock-to-scan** degradation (D-LOCK-NOGO-UX) covers no-go devices —
the alarm keeps ringing until unlocked and the escape hatch fires underneath, so the user is **never
trapped** and the alarm is **never un-stoppable**. The feature ships regardless (**D-LOCK-SHIP**).

> Residual: if the on-device run (Task 4) shows the alarm DOES surface over a secure keyguard once the
> user has granted the system "Allow full-screen notifications" toggle, the verdict becomes GO/REQUIRES-
> UNLOCK per device and GAP-B is FIXED-as-already-wired (no code change needed either way). Only a
> hardware run can disambiguate GO vs NO-GO vs REQUIRES-UNLOCK per OEM — see the table below.

---

## 3. Per-device verdict table (04-08 Task 4 — fill in on hardware, ≥2 OEMs)

Mirrors `MANUAL-VERIFICATION-LOG.md` §B columns. Verdict legend:
- **GO** — the alarm surfaces over the SECURE keyguard automatically (no manual unlock + notification tap);
  the camera preview renders over-lock → direct over-lock scan works.
- **NO-GO** — the alarm does NOT surface over a secure keyguard (and/or the camera preview is black over
  lock) → fall back to **unlock-to-scan** (D-LOCK-NOGO-UX). Accepted per D-LOCK-SHIP.
- **REQUIRES-UNLOCK** — notification arrives but the activity/camera only fully renders after the user
  unlocks → treat as no-go for the over-lock scan; unlock-to-scan is the norm.

| Device / OEM | Android ver. | Skin | "Allow full-screen notifications" state | Alarm surfaces over SECURE keyguard? | Camera preview renders over-lock? | Verdict |
|--------------|--------------|------|-----------------------------------------|--------------------------------------|-----------------------------------|---------|
| _(e.g. Pixel / AOSP)_ | _Android 14_ | _AOSP_ | _granted / denied_ | _GO / NO-GO / REQUIRES-UNLOCK_ | _renders / black / n-a_ | _PENDING_ |
| _(e.g. Samsung)_ | _Android 14_ | _OneUI_ | _granted / denied_ | _PENDING_ | _PENDING_ | _PENDING_ |
| _(optional: Xiaomi/MIUI — most aggressive over-lock restrictor; cf. flutter_zxing #114)_ | _—_ | _MIUI_ | _—_ | _PENDING_ | _PENDING_ | _PENDING_ |

**Overall verdict:** _PENDING the Task 4 on-device run across ≥2 OEMs._

---

## 4. Documented expected default per device class (D-LOCK-NOGO-UX)

- **GO devices:** the alarm surfaces over the secure keyguard; the scanner renders over-lock; the user
  scans the registered code to dismiss without unlocking. (Best case.)
- **NO-GO / REQUIRES-UNLOCK devices (the documented expected default for restrictive OEMs / Android-14):**
  show the **"unlock to scan"** prompt; the alarm **keeps ringing** until the device is unlocked; once
  unlocked the scanner opens and the registered code dismisses. The **escape hatch is always underneath**
  (default-on, time- OR failed-attempt-triggered) so the user is never trapped.

This is **not** a per-OEM runtime switch in code — Plan 04-04's `ScanTask` triggers the unlock-to-scan
prompt off a **runtime camera-failure signal** (`onControllerCreated` exception), not a manufacturer
lookup. This doc records the **expected default** each device class lands on.

## 5. Ship decision (D-LOCK-SHIP)

The feature **ships regardless** of the per-device verdict. The lock-screen result decides only the
PRIMARY path each device class gets — never whether to ship. The default-on escape hatch + unlock-to-scan
degradation make the alarm dismissable on every device, including no-go OEMs. **D-LOCK-SHIP is restated
here as binding:** a no-go keyguard is an accepted, documented limitation, not a release blocker.

---

## 6. Subsumes 04-03

This document **subsumes the deferred 04-03 lock-screen camera spike.** 04-03's goal (a documented
go / no-go / requires-unlock decision for a live `flutter_zxing` `ReaderWidget` over a SECURE keyguard
on ≥2 OEMs, reusing the real `FlutterShowWhenLocked().show()` path) is captured by §3's per-device table
and §2's classification. 04-03 need not be run separately; its on-device matrix is folded into 04-08
Task 4 and `MANUAL-VERIFICATION-LOG.md` §B. (No throwaway `// SPIKE` scaffold is needed for GAP-B — the
real ring path already drives the camera via the shipped `ScanTask`; the GAP-A fix in 04-07 makes that
preview render, so the Task 4 run exercises the genuine, non-throwaway over-lock path.)
