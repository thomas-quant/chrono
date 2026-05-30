# Pitfalls Research

**Domain:** Flutter/Android alarm app — camera scan-to-dismiss task + reliability bug fixes (boot crash, snooze, date off-by-one, rising volume)
**Researched:** 2026-05-30
**Confidence:** HIGH for the four reliability clusters (corroborated directly against this codebase's `CONCERNS.md` and source files); HIGH for the F-Droid/scanner dependency finding (verified against pub.dev + upstream README); MEDIUM for camera-over-lockscreen specifics (Flutter camera behavior on showWhenLocked activities is sparsely documented and device-dependent).

This file is scoped to **this milestone**. Generic "write tests / handle errors" advice is omitted in favor of the specific traps these six workstreams hit, with the exact Chrono files where each lives.

---

## Critical Pitfalls

### Pitfall 1: Scanner library pulls in Google ML Kit and breaks the F-Droid build

**What goes wrong:**
The obvious modern choice, `mobile_scanner`, uses Google's ML Kit barcode model on Android. ML Kit is a **proprietary, closed-source** Google component (the bundled variant ships the model in-app; the "unbundled" variant downloads it via Google Play Services). F-Droid's inclusion policy forbids non-free dependencies and flags Google/Play-Services libraries as anti-features. The build is either rejected, or someone "solves" it by forking into a crippled FOSS flavor where scan-to-dismiss silently doesn't exist — which means an alarm with a scan task on the F-Droid build can never be dismissed. That is a worst-case bricked alarm.

**Why it happens:**
`mobile_scanner` has the best DX and Flutter docs, so teams adopt it without checking the transitive Android deps. The ML Kit dependency is invisible in `pubspec.yaml` — it only appears in the generated `android/` Gradle graph. F-Droid breakage isn't caught until the F-Droid CI/merge bot rejects it, long after the feature is "done."

**How to avoid:**
- Use a **FOSS scanner with no Google dependency**: `flutter_zxing` (bundles the FOSS ZXing C++ core via Dart FFI, MIT, no Play Services, Android API 21+) is the verified candidate matching Chrono's distribution constraint. It supports QR + the required 1D formats (EAN-8/13, UPC-A/E, Code39/93/128, Codabar, ITF) and provides a `ReaderWidget` camera scanner with torch + pinch-zoom control.
- **Decision gate before any scanner code is written:** confirm the chosen package has zero `com.google.mlkit` / `com.google.android.gms` entries.
- Verify with: `cd android && ./gradlew app:dependencies | grep -Ei 'mlkit|play-services|gms'` after adding the dep — expect **zero** matches for a FOSS build.
- Do **not** assume `mobile_scanner`'s "unbundled" ML Kit variant (`useUnbundled=true`) solves F-Droid — it just moves the model download to **Google Play Services at runtime**, which still isn't free/available on F-Droid. Both `mobile_scanner` variants are non-free for F-Droid purposes (verified: pub.dev + upstream README).
- If `mobile_scanner` is chosen anyway for QR-only, note it would force a build-flavor split; that contradicts the milestone's "F-Droid builds must keep working" constraint, so treat it as rejected unless the constraint changes.

**Warning signs (detect early):**
- `pubspec.yaml` gains `mobile_scanner`, `google_mlkit_*`, or `firebase_ml_*`.
- `android/app/build.gradle` or merged manifest references `com.google.mlkit` / `play-services-*`.
- APK size jumps ~3–10 MB after adding the scanner (bundled ML Kit model).
- The `<application>` element gains `com.google.mlkit.vision.DEPENDENCIES` metadata.

**Phase to address:** Scanner-task foundation phase (dependency selection is the first decision; everything else builds on it). Verification belongs in the same phase's exit criteria, not later.

---

### Pitfall 2: Boot isolate touches storage before the device is user-unlocked

**What goes wrong:**
On Android 7+ with Direct Boot / file-based encryption, after a reboot the device runs with only **device-encrypted (locked) storage** available until the user enters their PIN/pattern. The default `SharedPreferences` (which backs `get_storage` and the `flutter_boot_receiver` reschedule path) lives in **credential-encrypted storage**, which is **not readable before first unlock** — accessing it throws `IllegalStateException: SharedPreferences in credential encrypted storage are not available until after user is unlocked`. Chrono's `handleBoot()` reschedules alarms on `BOOT_COMPLETED`; if it reads settings/alarm JSON before unlock it throws, the boot isolate crashes (it currently only logs the error and continues), and a half-written reschedule leaves partial state. The next foreground launch then reads that partial/corrupt state and **hangs on the splash** (the #442/#420/#448/#489/#498/#516/#514/#483/#289 epic).

**Why it happens:**
`BOOT_COMPLETED` is delivered *after* unlock on most devices, so developers assume storage is always available at boot. But OEMs differ: some deliver `LOCKED_BOOT_COMPLETED` first, some fire boot receivers in direct-boot mode, and some users have alarms set for immediately after a reboot-before-unlock. The path works on the dev's phone and fails on a subset of users — exactly the pattern in the bug cluster. (Confirmed at `lib/system/logic/handle_boot.dart`: the boot handler wraps `updateAlarms`/`updateTimers` in a single broad `try/catch` that just logs `logger.f` — a storage-locked throw is swallowed, not distinguished from corruption, and any partial reschedule already done is left in place.)

**How to avoid:**
- Treat the boot path as "**storage may be unavailable**." Wrap the boot reschedule so a storage-read failure schedules a **retry on first unlock** (`ACTION_USER_UNLOCKED` / app foreground) rather than crashing or silently giving up.
- Do **not** silently catch-and-fallback-to-defaults on boot — that is what masks corruption (see `SettingGroup.load()` swallowing `json.decode(null)`, `CONCERNS.md` fragile-areas). On boot, distinguish "storage locked, retry later" (recoverable, expected) from "data corrupt" (log + recover to defaults, but flag).
- Make boot reschedule **idempotent**: cancel-then-schedule by deterministic alarm id, so a partial/duplicate run can't double-fire or leave orphans (the existing `updateAlarms` reschedule-all pattern must be safe to run twice).
- Add an explicit **null/empty guard before every `json.decode`** in the load path (`setting_group.dart:257-268` is the known offender) so a missing/locked file becomes "use defaults this run," never an unhandled throw.
- Make splash **time-boxed**: if init hasn't completed in N seconds, proceed to a recoverable UI state instead of awaiting forever. A recoverable error must never become a fatal splash hang.

**Warning signs (detect early):**
- Boot reschedule code calls `getStorage`/`getSetting`/`json.decode` with no handling for "storage unavailable."
- Any `catch (e) {}` or catch-and-default in the boot or settings-load path with no logging or no distinction between locked vs corrupt (the current `handle_boot.dart` is exactly this shape).
- Splash screen `await`s an init future with no timeout.
- Crash reports clustered right after reboot; "black screen on open after restart."

**Phase to address:** Boot/storage reliability phase (the CRITICAL cluster). This is the highest-priority fix — owns `handle_boot.dart`, `alarm_isolate.dart`/`initialize_isolate.dart`, and the `setting_group.dart` load path.

---

### Pitfall 3: Silent catch-and-fallback masks corruption (turning a data problem into a mystery)

**What goes wrong:**
The codebase already has broad `catch (e)` blocks that swallow load failures and fall back to defaults or to the *other* storage backend (the GetStorage-vs-text-file dual store, `CONCERNS.md`). When boot writes partial state, the swallow hides it: the user sees alarms silently reset, missed alarms, or a hang, with no log explaining why. Fixing the boot crash without also fixing the silent fallback just moves the failure somewhere quieter.

**Why it happens:**
"Don't crash" is mistaken for "handle the error." Catching everything *feels* safer than letting it throw, but it converts a loud, diagnosable failure into silent data loss/drift. The dual-storage fallback (text file missing → read GetStorage) compounds it: the two stores drift and the user gets data from the wrong one.

**How to avoid:**
- Replace blanket `catch (e)` in load paths with **typed handling**: log the error (the app already has `logger`), then recover *deliberately* (defaults) — never an empty catch.
- For the dual-store drift: pick **one canonical store** for this milestone's touched data and make the fallback an **explicit, logged, one-time migration**, not a silent per-read fallback.
- When recovering to defaults due to corruption, surface it (log + optionally a one-time notice) so it's diagnosable, not invisible.

**Warning signs (detect early):**
- `grep` for `catch (e) {` returning empty bodies or bodies that only `return defaults`.
- Two code paths reading the same logical value from `get_storage` and from a `.txt` file.
- Bug reports of "my alarms disappeared" / "settings reset themselves" with no crash.

**Phase to address:** Boot/storage reliability phase (same cluster as Pitfall 2 — they share the load path).

---

### Pitfall 4: Snooze state machine — fractional snooze floors to 0, and one-shot alarms re-fire after dismiss

**What goes wrong:**
Multiple distinct snooze failures in the #439/#495/#445/#457 cluster:
1. **Fractional `snoozeLength` floors via `.floor()`.** Confirmed in `lib/alarm/types/alarm.dart`: both `snooze()` (line ~226) and `_scheduleSnooze()` (line ~234) use `Duration(minutes: snoozeLength.floor())`. A sub-1-minute snooze length floors to **0 minutes** → the alarm "snoozes" then immediately re-fires (or schedules for now), and the displayed `$snoozeLength` in the log won't match the actual floored duration. (Same `.floor()` class of bug as the timer screen's `'null:00'` label in `CONCERNS.md`.)
2. **One-shot alarm reschedules after snooze→dismiss (#457).** A "once" alarm that is snoozed and then dismissed must go **inactive/deleted**, not reschedule. `snooze()` sets `_isEnabled = true` to re-arm; if the dismiss path then runs the recurring `schedule()` (which also sets `_isEnabled = true` and re-schedules the active schedule) without branching on `OnceAlarmSchedule`, the one-shot gets re-armed and fires again — a one-shot alarm that won't die.

Also in scope: **max-snooze count not enforced** (`_snoozeCount++` in `snooze()` but no observed gate that blocks snoozing past the configured max), and **snooze state lost across the isolate boundary** — snooze is decided in the notification UI / handled in the alarm isolate (`stopAlarm`/`snooze` over `stopAlarmPort`), but if `_snoozeCount`/`_snoozeTime` aren't persisted to disk before the isolate exits, the count resets on the next ring.

**Why it happens:**
- Snooze duration is treated as int-minutes via `.floor()`, so any fractional or seconds-based value silently truncates to 0.
- "Once" alarms reuse the recurring reschedule machinery (`schedule()` iterates all schedules); the special case (don't re-arm a resolved one-shot) is easy to miss because the happy path (dismiss a non-snoozed once alarm) works.
- Snooze count lives on the in-memory `Alarm` instance; whether it survives depends on the alarm being saved to disk before the isolate tears down.

**How to avoid:**
- Define snooze duration in a unit that doesn't truncate (seconds, or `Duration` directly); guard against `<= 0` snooze (clamp to a sane minimum or reject at config). Add a unit test for fractional/zero snooze length.
- Make the **dismiss path explicitly check schedule type**: a `OnceAlarmSchedule` alarm, once dismissed (whether or not it was snoozed), transitions to **disabled/inactive** and is **not** rescheduled. Add tests: once-alarm ring→snooze→dismiss leaves it disabled; ring→snooze→snooze→dismiss likewise.
- **Persist snooze count + `_snoozeTime`/`isSnoozed`** to the saved alarm JSON at the moment of snooze, before crossing the isolate boundary, so the count survives. Enforce max-count at the point of deciding whether the next snooze is allowed (gate before `_snoozeCount++`).
- Treat snooze as an explicit small state machine: `ringing → (snooze[count<max] → snoozed → ringing)* → dismissed/inactive`, with max-count gating the snooze transition. Make illegal transitions (reschedule after dismiss of a once-alarm) impossible by construction.
- **Do not** layer the deferred snooze-feature PRs (#515 custom snooze, #475 fat button) on top until this core is fixed — per the milestone's Out-of-Scope decision.

**Warning signs (detect early):**
- `.floor()`/`.toInt()` anywhere on `snoozeLength` (currently at `alarm.dart` ~226 and ~234).
- Dismiss handler calls `schedule()`/reschedule used by recurring alarms without branching on `OnceAlarmSchedule`.
- `_snoozeCount` read from the in-memory instance with no persisted backing; no gate before `_snoozeCount++`.
- QA: a "once" alarm reappears the next day after being snoozed-then-dismissed; a snoozed alarm re-fires instantly.

**Phase to address:** Snooze reliability phase (the CRITICAL cluster, alongside boot). Sites: `lib/alarm/types/alarm.dart` snooze block (~218–247), the dismiss path in `lib/notifications/logic/alarm_notifications.dart` / `lib/alarm/logic/alarm_isolate.dart`.

---

### Pitfall 5: Date off-by-one — UTC-midnight from table_calendar round-tripping through epoch

**What goes wrong:**
`table_calendar` emits selected days as **UTC-midnight `DateTime`s**. Chrono serializes the picked date to `millisecondsSinceEpoch` and reloads it as **local** time. For users at negative UTC offsets (the Americas), UTC-midnight reloaded as local is the **previous day** — the specific-date alarm fires (or displays) one day early/late (#340/#455/#472). The symmetric trap when fixing it: over-correcting so positive-UTC users (Asia/Pacific) now drift the other way, or a regression where DST-transition days shift the stored date by the DST hour.

**Why it happens:**
`DateTime` in Dart silently carries a UTC-vs-local flag; `millisecondsSinceEpoch` is an absolute instant, so the wall-clock date you get back depends on the timezone you reconstruct in. Mixing a UTC-midnight source with a local reconstruction is the textbook off-by-one. Naive `DateTime` arithmetic (`add(Duration(days:1))`) across a DST boundary adds a day-as-24h, not a calendar day, introducing the symmetric bug when "fixing" it.

**How to avoid:**
- Store and compare a **calendar date as date components** (year/month/day), not as an absolute epoch instant — e.g. normalize the picker output to a local `DateTime(y, m, d)` (or a `YYYY-MM-DD` string) at the boundary, and compare on those components.
- Normalize at **one** boundary: the moment `table_calendar` hands back a value (`date_picker_bottom_sheet.dart:145`), convert `utc-midnight → local date`. Do not also re-convert on load (`DateTimeSetting`, ~`setting.dart:957-967`).
- Use `DateUtils.dateOnly(...)` / `isSameDay` rather than epoch equality for "is this the alarm's day."
- For any date math, build the next date from components, not `Duration(days:1)` arithmetic, to avoid DST 23/25-hour days.
- **Test with frozen non-UTC timezones**: this codebase already uses `withClock`/`Clock.fixed` (TESTING.md). Add round-trip tests asserting the picked calendar date survives toJson/fromJson for a negative-UTC and a positive-UTC offset, and across a DST day. This is the guard against the fix-causes-regression trap.

**Warning signs (detect early):**
- The serialization uses `millisecondsSinceEpoch` for something that is conceptually a *date*, not an instant. Site: `DateTimeSetting` (~`setting.dart:957-967`).
- `.toLocal()`/`.toUtc()` applied asymmetrically (one side only) between save and load.
- Tests run only in the developer's / CI timezone (likely UTC) so the bug is invisible in CI.
- QA in a negative-UTC timezone shows the date one day off.

**Phase to address:** Date/serialization fix phase (the HIGH cluster). Sites: `lib/common/widgets/fields/date_picker_bottom_sheet.dart:145`, `DateTimeSetting` in `lib/settings/types/setting.dart`. Note: full **DST/timezone recompute for recurring alarms (#359) is explicitly out of scope** — keep this fix to the specific-date serialization; don't scope-creep into recurring recompute.

---

### Pitfall 6: Rising volume ramp is fire-and-forget and can't be cancelled on stop

**What goes wrong:**
`RingtonePlayer._play` schedules ~11 `Future.delayed` callbacks to ramp volume (confirmed `ringtone_player.dart:119-129`), gated only by a **static `bool _stopRisingVolume`** (line 20). On stop, the already-scheduled `Future.delayed`s still fire — so after you dismiss/snooze, a stray callback can call `setVolume(...)` and **bump the volume back up**, or a newly-started alarm's ramp collides with a previous one's lingering futures (the static flag can't tell which playback a late callback belongs to). Result: alarm volume that won't go down on dismiss, or that overrides a second alarm. Second half of the bug: the ramp **does** scale to the configured volume (`(i/10)*volume` where `volume = alarm.volume/100`), so verify the chosen fix preserves that and doesn't regress to ramping to `1.0`.

**Why it happens:**
`Future.delayed` is fire-and-forget — it cannot be cancelled. A single static cancellation flag can't disambiguate which alarm instance a late callback belongs to, so the "newest wins" flag fails when two playbacks overlap (snooze re-ring, back-to-back alarms). Note `setVolume()` *also* sets `_stopRisingVolume = true` (line 84), so any explicit volume set mid-ramp halts the ramp as a side effect — subtle coupling that makes the cancellation logic hard to reason about.

**How to avoid:**
- Replace the `Future.delayed` chain with a **cancellable `Timer`/`Timer.periodic`** (or `CancelableOperation`) stored on the player; `stop()`/`pause()` must `cancel()` it. Remove the static `_stopRisingVolume` flag.
- Scope cancellation to the **instance/alarm**, not a static bool, so overlapping playbacks don't cross-cancel or leak. (The player is a static class today, so this likely means tracking the active ramp timer and cancelling it on every new `playAlarm`/`stop`.)
- Keep the ramp target as the **configured volume %** (`alarm.volume/100`), as it already is — confirm the fix doesn't hardcode `1.0`.
- Verify the **stop path actually cancels**: after `stop()`, no further `setVolume` writes occur. This is the explicit "verify cancellation on stop" requirement, and what to check when reviewing/merging community PR #467 — confirm it cancels rather than just flags.
- If merging PR #467: confirm it (a) uses a cancellable timer, (b) cancels on stop, (c) still respects the configured volume — don't merge a fix that only addresses the ramp without the cancellation guarantee.

**Warning signs (detect early):**
- `Future.delayed` used for stepped/scheduled work that has a "stop" action.
- A `static bool` (or any static mutable) used as a cancellation signal (`_stopRisingVolume`).
- `setVolume` doubling as a ramp-stopper via a side-effect flag.
- QA: dismiss during the ramp, then volume rises again a second later; or alarm B's volume is wrong right after dismissing alarm A.

**Phase to address:** Rising-volume fix phase (HIGH cluster) — `lib/audio/types/ringtone_player.dart`, gated on review of PR #467.

---

## Camera-in-an-alarm-context Pitfalls (the scan-to-dismiss feature)

These all belong to the **scanner-task phase**. They are grouped because they share the camera lifecycle. The task widget runs in the **main isolate** (alarm notification screen), not the firing isolate — camera lifecycle must be owned there.

### Pitfall 7: Camera not released — stuck "in use" / green privacy dot after dismiss

**What goes wrong:**
The scanner widget opens the camera but the controller is never stopped/disposed when the task is solved, the screen is popped, or the app is backgrounded mid-scan. The camera stays held: green/orange privacy indicator stuck on, camera unavailable to other apps, battery drain. A documented `mobile_scanner` issue shows the green toast/camera staying active when the page is popped *while the camera is still starting* (back-button during init) — directly relevant since the alarm screen can be dismissed at any instant. The alarm notification screen has multiple exit paths (solve → auto-dismiss, snooze, escape-hatch, system kill) so the dispose path is easy to miss.

**Why it happens:**
Flutter camera/scanner controllers are not auto-released on `dispose` unless wired up (if you pass your own controller, *you* must dispose it). The "popped during start" race leaves a half-initialized camera with no owner to stop it.

**How to avoid:**
- Own the controller in the task widget's `State`; **`stop()` + `dispose()` in `dispose()`** and immediately on `onSolve`.
- Implement `WidgetsBindingObserver`: `stop()` on `paused`/`inactive`, `start()` on `resumed` (this also fixes the camera-freezes-after-backgrounding class of bug). With `flutter_zxing`'s `ReaderWidget` / `mobile_scanner`, prefer the built-in lifecycle handling and `await` the async dispose.
- Stop the camera **the instant the code matches** — before navigating away — so it's never left running during the dismiss animation.
- Guard the **pop-during-start race**: don't start the camera in a way that leaves it orphaned if the widget is disposed before start completes.
- Test: solve, snooze, hit the escape hatch, and background the app mid-scan — verify the privacy indicator turns off in every case.

**Warning signs:** No `dispose()`/`stop()` on the controller; no lifecycle observer; privacy dot stays on after dismiss; "camera in use" errors in other apps; back-button during camera open leaves it running.

---

### Pitfall 8: No torch — scanner is useless in a dark bedroom at 3am

**What goes wrong:**
The whole point is dismissing an alarm — which fires when it's dark and you're half-asleep. A scanner with no torch toggle can't read a code in the dark, so the user can't dismiss and the alarm rings indefinitely (or they rage-uninstall).

**Why it happens:**
Torch is treated as a nice-to-have and deferred. But the alarm use-case is *defined* by low light.

**How to avoid:**
- **Torch toggle is table-stakes, not optional**, for this feature. Both `flutter_zxing` (`ReaderWidget` torch control) and `mobile_scanner` (`torchEnabled`) expose it — surface a visible toggle on the scan screen.
- Consider auto-enabling torch, or brightening the screen, when the scanner opens at low ambient light.

**Warning signs:** Scan screen has no flash/torch button; QA only ever tested in a lit room.

---

### Pitfall 9: No escape hatch / permission denied at 3am with no recourse — the alarm becomes un-dismissable

**What goes wrong:**
Several ways the user genuinely can't scan: they lost/threw away the registered physical code; camera permission was denied (or revoked) and there's no way to grant it from the ringing screen; the camera hardware fails; or it's too dark and there's no torch. Without a fallback, **the alarm cannot be dismissed** — the single worst outcome for an alarm app, and an accessibility/ethics failure.

**Why it happens:**
Copying Alarmy's "make it hard to dismiss" philosophy without Alarmy's escape valves. Permission handling assumes grant-at-setup, but Android can revoke permissions, and "deny" at ring time has no recovery UI.

**How to avoid:**
- **Escape hatch ON by default and configurable** (already the milestone decision): after a threshold of failed attempts and/or elapsed time, allow a plain dismiss. Make the threshold the *default behavior*, not an opt-in the user has to discover.
- If **camera permission is not granted at ring time**, do **not** trap the user: the escape hatch (or a direct dismiss) must be immediately available. Never gate dismiss behind a permission the user can't grant while the alarm is screaming.
- Request/verify camera permission **at task setup** (via the existing `permission_handler`), and re-check at ring time; if missing, degrade gracefully to the escape hatch rather than showing a dead camera view.
- Keep snooze a normal tap (milestone decision) — so even mid-task the user is never fully stuck.

**Warning signs:** No timeout/attempt-count fallback; dismiss path unreachable when permission denied; the only exit is a successful scan.

**Phase to address:** Scanner-task phase — and the escape hatch should be built **before or alongside** the scan-success path, not bolted on after, so the un-dismissable state is impossible from the first working build.

---

### Pitfall 10: Camera init / scan on the main thread → ANR while the alarm rings

**What goes wrong:**
Initializing the camera or doing heavy decode work synchronously on the UI isolate stalls the ring screen. On a cold, just-woken device the camera open can take a second+; if that blocks the main thread you get jank or an Android ANR right when the user is trying to silence the alarm.

**Why it happens:**
Camera open is async but easy to `await` in a way that blocks the first frame; or decode is run per-frame on the platform thread without throttling.

**How to avoid:**
- Open the camera asynchronously; show the scan UI (with torch + escape hatch already visible) immediately, camera preview attaching when ready.
- Let the scanner plugin do detection off the UI isolate (both candidate plugins decode natively — `flutter_zxing` via FFI, `mobile_scanner` via CameraX); don't add per-frame Dart work.
- Don't `await` camera init inside `build`/`initState` in a way that blocks first paint.

**Warning signs:** Ring screen freezes for ~1s when the scan task opens; "App isn't responding" dialog over the alarm; dropped frames on camera attach.

---

### Pitfall 11: Registered-code matching fails on whitespace/encoding differences between setup scan and ring scan

**What goes wrong:**
The user registers a code at setup; at ring time the *same physical code* scans to a string that differs by a trailing newline, leading/trailing whitespace, a different symbology label (`EAN_13` vs `EAN13`), case, or character-encoding (UTF-8 vs Latin-1 for non-ASCII payloads). Exact `==` comparison fails → the correct code is rejected → user can't dismiss. This is the *silent killer* of scan-to-dismiss features (and the subject of Alarmy's own "QR/Barcode recognition is not working well" support article).

**Why it happens:**
Barcode payloads carry incidental whitespace/control chars; QR can encode the same text in different byte sequences; some libraries return raw bytes, some a decoded string, some with the format prefixed. Comparing raw scan strings byte-for-byte is fragile.

**How to avoid:**
- **Normalize both at registration and at match time with the identical function**: `trim()`, strip control chars/newlines, decide a canonical case/encoding. Store the normalized form; compare normalized-to-normalized.
- Prefer matching on normalized *value* to tolerate symbology-label differences; only compare format too if you normalize the format label consistently.
- For non-ASCII/binary payloads, compare on a stable representation (e.g. raw bytes hashed, or a consistently-decoded string) — don't let platform default decoding differ between the two scans.
- Test: register a code, then assert the same payload with added whitespace/newline/case still matches; assert a *different* code does not. (This fits the existing `toJson`/`fromJson` round-trip test style — the registered code is stored in the task's `SettingGroup`.)

**Warning signs:** Match uses `scanned == registered` on raw strings; "it won't accept the right code" reports; the stored registered value includes a trailing newline.

---

### Pitfall 12: Camera over the lock screen — black preview or permission prompt behind the alarm

**What goes wrong:**
The alarm rings over the lock screen (Chrono uses `flutter_show_when_locked` + `USE_FULL_SCREEN_INTENT`). Launching a camera preview from a `showWhenLocked` activity can yield a **black preview** on some OEMs, or a permission/consent dialog that renders *behind* the lock screen and can't be interacted with — so the scan task is unusable specifically in its primary scenario (locked device). Android also restricts camera capture for background/locked contexts in CameraX, so a Preview surface over a secure lock screen is not guaranteed.

**Why it happens:**
`showWhenLocked` + camera is an unusual combination; OEM lock-screen policies and Android's "some surfaces hidden on secure lock screen" behavior are inconsistent and poorly documented. Tested-while-unlocked, it works; on a secure lock screen it doesn't.

**How to avoid:**
- **Test on a secure (PIN/pattern) lock screen specifically**, on more than one OEM, early — not just unlocked.
- Ensure camera permission is **already granted at setup** so no permission dialog is needed at ring time (a dialog over the lock screen is the failure mode).
- If a black-preview/locked-surface issue appears, the escape hatch must still rescue the user; consider whether the scan task requires device unlock first and document that, rather than shipping a silently-broken locked path.

**Warning signs:** Black camera preview only when the device is locked; permission dialog never appears / appears behind lock; works on the dev's unlocked phone, fails for users.
**Confidence:** MEDIUM — behavior is device/OEM dependent and under-documented; treat as a thing to *verify on hardware*, not a settled fact.

---

### Pitfall 13: Wakelock/battery — scanning holds the screen + camera with no timeout

**What goes wrong:**
The alarm already holds a wakelock (and a `flutter_foreground_task` service) to keep ringing; adding a live camera preview that runs until a successful scan (with no cap) can drain noticeable battery if the user can't scan, especially combined with the escape hatch being disabled.

**Why it happens:**
The camera runs continuously while the task screen is up; if there's no escape-hatch timeout the worst case is camera + screen + audio + foreground service held indefinitely.

**How to avoid:**
- The escape-hatch elapsed-time threshold doubles as the **camera cap**: after the timeout, stop the camera and allow dismiss.
- Stop the camera while the app is backgrounded (Pitfall 7), so it isn't held when not visible.

**Warning signs:** No time cap on the scan task; camera + audio running together with no upper bound.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use `mobile_scanner` (ML Kit) for nicer DX | Fastest scanner integration | Breaks F-Droid; forces a crippled FOSS flavor where scan-dismiss can't work | **Never** given the F-Droid constraint; only if the milestone drops F-Droid support |
| Use `mobile_scanner` "unbundled" thinking it fixes F-Droid | Smaller APK | Still needs Play Services at runtime; still non-free for F-Droid | Never — it does not solve the constraint |
| Keep silent `catch (e)` → defaults in load/boot paths | "App doesn't crash" | Masks corruption; users see silent data loss / splash hangs | Never in the boot/settings-load path; the whole point of this milestone |
| Static `bool` cancellation flag for the volume ramp | One-line "stop" | Fails on overlapping playbacks; volume rises after dismiss | Never — use a cancellable Timer/operation |
| Store a calendar date as `millisecondsSinceEpoch` | Reuse existing serialization | Off-by-one for non-UTC users; DST drift | Never for *dates*; epoch is fine for *instants* |
| Snooze duration as `int` minutes / `.floor()` | Simpler picker | Fractional/zero snooze floors to 0; no sub-minute | Acceptable only if config rejects/clamps `<=0` |
| Ship scan task before the escape hatch | Demo the headline feature | Un-dismissable alarm if scan fails | Never — escape hatch is part of the first working build |
| Skip secure-lock-screen testing of the camera | Faster iteration | Primary use-case (locked at 3am) may be broken | Never for this feature |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Scanner package | Adopt ML-Kit-backed `mobile_scanner` (bundled or unbundled) without checking Gradle deps | Choose FOSS `flutter_zxing` (ZXing C++ via FFI, no Play Services); verify `./gradlew app:dependencies` has no `mlkit`/`gms` |
| `flutter_boot_receiver` reschedule | Read SharedPreferences/get_storage in `handleBoot()` unconditionally | Tolerate locked storage; retry reschedule on first unlock; idempotent cancel-then-schedule |
| `get_storage` / SharedPreferences | Assume readable immediately at `BOOT_COMPLETED` | Credential-encrypted store unavailable before user unlock; guard + retry (or device-protected storage for direct-boot data) |
| Dual store (GetStorage + text files) | Silent per-read fallback between the two | One canonical store; explicit logged one-time migration |
| `just_audio` volume ramp | `Future.delayed` chain + static stop flag | Instance-scoped cancellable `Timer`; cancel on stop; keep configured volume target |
| `table_calendar` | Use its UTC-midnight `DateTime` directly through epoch | Normalize to local calendar date at the picker boundary; compare with `isSameDay`/date-only |
| `permission_handler` (camera) | Request only at setup; no recovery if denied at ring | Re-check at ring; degrade to escape hatch if not granted; never trap |
| Alarm isolate ↔ main isolate | Hold snooze count in UI/in-memory state | Persist snooze count/flag to alarm JSON before the isolate boundary so it survives re-entry |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Camera init on main isolate | Ring screen freezes ~1s; ANR | Async camera open; show UI first | Cold device, just-woken, slow camera |
| Volume ramp via 11 `Future.delayed` | Stray volume bumps after stop; cross-alarm bleed | Cancellable Timer scoped per instance | Overlapping playbacks (snooze re-ring, back-to-back alarms) |
| Camera held while backgrounded | Battery drain, stuck privacy dot | Stop on lifecycle `paused` | User backgrounds mid-scan |
| No cap on scan task | Camera + audio + foreground service held indefinitely | Escape-hatch timeout stops camera | User can't scan (lost code / dark) |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| "Any code dismisses" instead of a registered code | A saved screenshot/photo of any QR defeats the wake-up purpose | Match a pre-registered, normalized code (already the milestone decision) |
| Logging the scanned/registered code value | Leaks a code the user chose; echoes the existing `print(setting.value)` leak in `CONCERNS.md` (`dynamic_toggle_setting_card.dart:39`) | Don't log scan payloads; remove the existing `print` while working in settings-card code |
| Broad boot/storage `catch` hiding tampered/corrupt state | Corruption silently masked; harder to diagnose | Typed, logged recovery instead of empty catch |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No torch in the scanner | Can't dismiss in a dark bedroom (the whole use-case) | Torch toggle visible by default; consider auto-on in low light |
| Escape hatch off / opt-in | Lost code or dead camera = un-dismissable alarm | Escape hatch ON by default; threshold is the default behavior |
| Gating snooze behind the scan too | User can't even snooze when stuck | Gate dismiss only; snooze stays a normal tap (milestone decision) |
| Rejecting the correct code on whitespace mismatch | "It won't accept the right code" frustration | Normalize both sides identically before comparing |
| Once-alarm re-fires after snooze→dismiss | User thinks alarm is off; it rings again next day | Dismiss makes a one-shot inactive regardless of prior snooze |
| Date one day off for Americas users | Specific-date alarm fires wrong day | Normalize calendar date at the picker boundary |
| Snooze that does nothing (floors to 0) | Snooze button appears broken | Reject/clamp sub-minute snooze; no `.floor()` to 0 |

## "Looks Done But Isn't" Checklist

- [ ] **Scanner dependency:** Looks done — but did you run `./gradlew app:dependencies | grep -Ei 'mlkit|gms|play-services'` and get **zero** hits? Did the F-Droid (`prod` APK) build actually compile with it?
- [ ] **Scan task:** Looks done — but does the escape hatch trigger on attempt-count *and* elapsed time, and is it on by default? Does dismiss work when camera permission is denied?
- [ ] **Camera lifecycle:** Looks done — but is the camera released (privacy dot off) on solve, snooze, escape-hatch, back-button-during-start, *and* backgrounding? Tested on a secure lock screen?
- [ ] **Code matching:** Looks done — but does it still match with a trailing newline / whitespace / different case added to the same payload?
- [ ] **Boot fix:** Looks done — but did you test reboot-then-immediately-open *before unlock*, on an FBE device? Does splash time-box instead of hanging?
- [ ] **Snooze fix:** Looks done — but: fractional snooze length (no `.floor()` to 0)? once-alarm ring→snooze→dismiss stays inactive? max-count enforced and persisted across the isolate boundary?
- [ ] **Date fix:** Looks done — but did you test in a negative-UTC *and* positive-UTC timezone, and across a DST day, with a save→load round-trip?
- [ ] **Volume fix:** Looks done — but after `stop()` does the volume *stay* down (no late `Future.delayed` bump)? Does it still honor the configured volume %, and is the static flag gone?

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Chose `mobile_scanner`, F-Droid rejected | MEDIUM | Swap to `flutter_zxing`; re-test scan + torch; re-verify Gradle deps. Cheaper if caught at the dependency-selection gate (LOW) than after the task UI is built (MEDIUM). |
| Boot reschedule corrupts state in the wild | HIGH | Ship guard + idempotent reschedule + non-fatal load; for already-corrupted installs, detect-and-reset-to-defaults-with-log on next launch |
| Once-alarm re-fires after dismiss | LOW–MEDIUM | Branch dismiss on schedule type; add regression test; no data migration needed |
| Date off-by-one already saved wrong | MEDIUM | Fix normalization; existing wrong epoch values may need a one-time corrective read (interpret old epoch as the intended local date) |
| Volume won't go down on dismiss | LOW | Replace ramp with cancellable Timer; cancel on stop |
| Camera stuck on after dismiss | LOW | Add `dispose()`/`stop()` + lifecycle observer |
| Un-dismissable alarm shipped (no escape hatch) | HIGH (user trust) | Hotfix escape-hatch default-on; this is why it must be in the first build |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 — ML Kit / F-Droid break | Scanner foundation (dependency selection) | `./gradlew app:dependencies` shows no mlkit/gms; F-Droid (`prod`) build compiles |
| 2 — Boot touches locked storage | Boot/storage reliability (CRITICAL) | Reboot-before-unlock test on FBE device; no crash; alarms reschedule on unlock |
| 3 — Silent catch masks corruption | Boot/storage reliability (CRITICAL) | No empty catches in load/boot path; corruption logged + recovered, not hidden |
| 4 — Snooze state machine | Snooze reliability (CRITICAL) | Tests: fractional/zero snooze; once-alarm snooze→dismiss inactive; max-count enforced + persisted |
| 5 — Date off-by-one | Date/serialization fix (HIGH) | Round-trip tests in ±UTC and across DST; `isSameDay` comparisons |
| 6 — Rising volume can't cancel | Rising-volume fix (HIGH) | After stop, no volume writes; static flag removed; respects configured volume (review PR #467) |
| 7 — Camera not released | Scanner task | Privacy dot off on solve/snooze/escape/background/back-during-start |
| 8 — No torch | Scanner task | Torch toggle present; scan works in the dark |
| 9 — No escape hatch / denied perm | Scanner task (escape hatch first) | Dismiss reachable on lost code, denied permission, timeout |
| 10 — Camera init ANR | Scanner task | No frame freeze on task open; async camera attach |
| 11 — Code match whitespace/encoding | Scanner task | Same payload + whitespace/case still matches; wrong code rejected |
| 12 — Camera over lock screen | Scanner task | Tested on secure lock screen, multiple OEMs |
| 13 — Wakelock/battery | Scanner task | Escape-hatch timeout caps camera; camera stopped when backgrounded |

## Sources

- `.planning/codebase/CONCERNS.md` — rising-volume `Future.delayed` cancellation flaw (`ringtone_player.dart:119-129`), silent `SettingGroup.load()` GetStorage fallback + `json.decode(null)` (`setting_group.dart:257-268`), dual-storage drift, `print(setting.value)` leak (`dynamic_toggle_setting_card.dart:39`), `.floor()` `'null:00'` class bug — HIGH (direct codebase audit).
- Direct source review this session: `lib/audio/types/ringtone_player.dart` (static `_stopRisingVolume`, 11×`Future.delayed`, `setVolume` side-effect flag), `lib/alarm/types/alarm.dart` (`snooze()`/`_scheduleSnooze()` `snoozeLength.floor()` ~226/234, `_snoozeCount++`, `_isEnabled=true` re-arm, `schedule()` reschedule-all), `lib/system/logic/handle_boot.dart` (single broad `try/catch` around `updateAlarms`/`updateTimers`) — HIGH.
- `.planning/PROJECT.md` — milestone scope, suspected files, decisions (escape hatch on by default, registered-code match, dismiss-only gating, F-Droid constraint) — HIGH.
- `.planning/codebase/ARCHITECTURE.md`, `STRUCTURE.md`, `INTEGRATIONS.md`, `TESTING.md` — isolate boundary (`stopAlarmPort`/`updatePort`/`setAlarmVolumePort`), task framework, `withClock`/`Clock.fixed` test capability, `flutter_show_when_locked` + `USE_FULL_SCREEN_INTENT`, `flutter_foreground_task` — HIGH.
- pub.dev `mobile_scanner` (v7.2.0) + upstream README — uses ML Kit (proprietary); bundled (+3–10 MB) vs unbundled (Play Services, +~600 KB) — *both* non-free for F-Droid; torch (`torchEnabled`) + `WidgetsBindingObserver` lifecycle + async dispose — HIGH.
- mobile_scanner GitHub issue #505 — camera stays alive in background if page pops while camera is starting — HIGH (relevant precedent).
- pub.dev / docs `flutter_zxing` (v2.3.0, MIT) — ZXing C++ via FFI, no Google Play Services, QR + UPC/EAN/Code39/93/128/Codabar/ITF + 2D, `ReaderWidget` with torch & pinch-zoom, Android API 21+ — verified FOSS candidate for the F-Droid constraint — HIGH.
- F-Droid packages (Binary Eye, ZXing) — confirm ZXing-C++ FOSS scanners are F-Droid-distributable without Play Services — MEDIUM/HIGH.
- Android Direct Boot / FBE docs + multiple library issue reports (orhanobut/hawk #224, Instabug #304, appcenter #1599) — credential-encrypted SharedPreferences unavailable before first user unlock (`IllegalStateException`); `LOCKED_BOOT_COMPLETED`/`ACTION_USER_UNLOCKED`/device-protected storage — HIGH.
- Flutter camera + `showWhenLocked` lock-screen + CameraX background/locked capture restrictions — MEDIUM (OEM-dependent, under-documented; flagged as verify-on-hardware).
- Alarmy support ("QR/Barcode recognition is not working well", emergency-dismiss) — corroborates the code-matching-fragility and escape-hatch-necessity pitfalls from a shipped product — MEDIUM.

---
*Pitfalls research for: Flutter/Android alarm app — scan-to-dismiss + reliability fixes*
*Researched: 2026-05-30*
