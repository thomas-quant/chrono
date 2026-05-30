# Feature Research

**Domain:** Scan-to-dismiss (QR/barcode) alarm dismissal task for Chrono — a Flutter, Android-only, local-first, open-source, deliberately non-predatory alarm app
**Researched:** 2026-05-30
**Confidence:** HIGH on market behavior (official Alarmy + Sleep as Android docs, FOSS reference apps); MEDIUM on community pain points; LOW on exact lock-screen camera behavior (needs device validation)

> **Scope (decisions already locked for this milestone):** match a **pre-registered** code (not any code); gate **full dismiss only** (snooze stays a normal tap); **escape-hatch fallback ON by default and configurable**; accept **QR + common 1D barcodes**; **alarms only** (not timers); **clean-room** (no Alarmy code). Scanner library is **already chosen in sibling STACK.md: `flutter_zxing` pinned to `2.2.1`** — F-Droid-clean, minSdk 21, ships its own `ReaderWidget` camera view with built-in torch/scan-frame. This document sorts the *sub-features* of the task into table stakes / differentiators / anti-features.

## How The Market Does It (grounding)

Three reference points set every user's expectations for this feature:

- **Alarmy** ("QR/Barcode mission" — category leader). Setup: register a *specific* code by scanning any household barcode/QR (toothpaste, shampoo, or a self-generated QR printed and stuck on the fridge). Ring time: the camera opens as part of the mission and the alarm keeps sounding until that **same registered code** is scanned; a different code does not dismiss. Lighting is its #1 troubleshooting tip. Escape hatch: an **"Emergency Mode"** — but it is punitive: tap a moving button **100 times**, and the required taps **increase by +100 every time you use it** (resetting only 30 days after first use). Confidence: HIGH (official Alarmy Android Help Center).
- **Sleep as Android** ("QR code/Barcode CAPTCHA"). Setup: register a code; offers a *toggle* between "any code works" and "a specific code is required," plus the ability to place the tag in another room. Ring time: continuous live scanning; can fall back to an external scanner if the built-in vision API struggles. Escape hatch (humane): a **"skip CAPTCHA if far from home"** option AND a **"Sleeping sheep" fallback task** whose difficulty scales to the configured CAPTCHA difficulty — so the user is never permanently trapped. Confidence: HIGH (official Urbandroid docs).
- **QRAlarm** (FOSS, on F-Droid, GPL-3.0 — the closest direct precedent to Chrono). Notable feature: ships a **downloadable/printable default QR code** so a user can get started immediately, *or* scan their own. Proves the "scan-to-dismiss alarm" pattern is viable as a clean FOSS app. Confidence: HIGH (Google Play listing + F-Droid + GitHub `sweakpl/qralarm-android`).

**Real-world failure mode (design against this):** users routinely get stuck because they **lost, moved, or can't read** the registered code in a dark room; the community workaround is "set a backup normal alarm." Alarmy maintains an entire Help Center article specifically for "can't complete the mission." This directly validates Chrono's escape-hatch-ON-by-default decision. Confidence: MEDIUM (consistent community reports + the existence of dedicated vendor docs).

**Net implication:** Chrono's locked decisions already describe the *humane* version of this proven pattern. The milestone's job is to ship the proven core (specific-code match, continuous scan, alarm-keeps-ringing) while replacing Alarmy's punitive lockout/paywall with a genuinely non-predatory escape hatch.

## Feature Landscape

### Table Stakes (Users Expect These)

Missing any of these makes the feature feel broken or untrustworthy versus Alarmy / Sleep as Android / QRAlarm.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Register a specific target code at setup | The whole point; all three references store a specific code. Locked decision. | LOW–MEDIUM | Scan once in the alarm's task config via `flutter_zxing`'s reader; persist `rawValue` (and ideally `format`) in the existing `SettingGroup`/`AlarmTask` JSON. Remember to register the new type in the `json_serialize.dart` factory map (per CONCERNS — easy to forget, runtime crash if missed). |
| Live camera scanner at ring time, opens automatically | Users expect the viewfinder to appear when the alarm fires, not to hunt for a button | MEDIUM | Lives in `alarm_notification_screen.dart` (main isolate / foreground Activity), NOT the firing isolate — confirmed safe in STACK.md. `ReaderWidget` manages the camera with a result callback. Highest-risk integration is the lock-screen overlay (see risks). |
| Continuous / auto re-scan (no per-attempt button) | Alarmy, Sleep as Android & QRAlarm read frames continuously; you just point until it reads | LOW | `flutter_zxing` `ReaderWidget` streams results via callback; compare each result to the stored value. No manual "scan" press. |
| Match validation: alarm keeps ringing until the correct code | Core contract — a wrong/other code must NOT dismiss; audio continues until match | LOW | Call the existing task `onSolve()` only on exact match; reuse the existing dismiss path. |
| Three-state feedback (no code / wrong code / match) | Groggy users must know whether the camera saw nothing, saw the *wrong* code, or succeeded | LOW | Distinct messaging: "point at your code" vs "that's not your registered code" vs success. |
| Camera permission request + graceful denial | OS requirement; the alarm must stay dismissable even if permission is denied | MEDIUM | `CAMERA` manifest entry + `uses-feature required="false"` (per STACK.md); reuse existing `permission_handler`. If denied at ring time, **must** fall through to the escape hatch — never trap the user. Prefer prompting at setup, not at 6am. |
| Escape-hatch fallback to dismiss (ON by default, configurable) | Locked decision; also the #1 real-world pain. All references ship some fallback. | MEDIUM | After a timeout and/or N failed attempts, allow an alternate dismiss. Configurable (can tighten/disable) but defaulted ON. Must also cover "camera unavailable / permission revoked" (STACK.md safety flag). |
| Clear ring-time instruction text | Matches the existing task convention ("solve to dismiss"); QR needs "Scan your registered code to dismiss" | LOW | New localized strings (English now, others via Weblate — in scope). |
| QR + common 1D barcodes supported | Users register whatever household item they have; product packaging is 1D (UPC/EAN) | LOW | Locked decision. `flutter_zxing` supports QR + EAN-8/13, UPC-A/E, Code39/93/128, ITF, Codabar (and more). Restrict the enabled formats for faster, more reliable decode. |

### Differentiators (Competitive Advantage)

Not required to function, but these make Chrono's version the *better, kinder* one — aligned with its non-predatory Core Value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| "Test scan" / preview in setup | Lets the user confirm the code reads *before* trusting it at 6am — eliminates the lockout panic entirely | LOW–MEDIUM | Reuses the same `ReaderWidget` as ring time. Highest value-for-effort differentiator; strongly recommended for v1. A user already requested scan-to-dismiss (#206), so polish matters. |
| Torch / flashlight toggle | You wake in a **dark room**; without light, scanning fails. Lighting is the top scan-failure cause; Sleep as Android ships this. | LOW | `flutter_zxing` `ReaderWidget` exposes torch control built-in — near-zero cost. Recommend for v1. |
| Haptic + visual confirmation on match | Instantly reassures a half-asleep user that the scan worked | LOW | Short vibration + checkmark; reuse the existing `vibration` dependency already in the stack. |
| Downloadable/printable default code (QRAlarm-style convenience) | Lets a user start instantly without hunting for a household barcode | MEDIUM | Optional generator/printable. *Offer*, never *require* (see anti-features). Defer past v1; nice FOSS parity touch. |
| Registered-item hint (label, optional) | "You registered: Toothpaste" helps a sleepy user remember where the code lives | MEDIUM | Optional text label captured at registration. (A saved *thumbnail* image adds storage + a privacy surface — prefer a plain label.) |
| Configurable threshold (timeout seconds and/or attempt count) before escape hatch | Power users can make it strict; the humane default protects everyone else | LOW–MEDIUM | Mirrors Sleep as Android's difficulty config. Ship one sane default first; expose knobs as polish. |
| Framing reticle / scan-guide overlay | Speeds reads and raises perceived reliability | LOW | `ReaderWidget` already provides a scan frame; minimal extra work. |
| Match on `rawValue` **and** `format` | Avoids rare cross-format value collisions; cheap robustness | LOW | `flutter_zxing` exposes the decoded format per result. |

### Anti-Features (Commonly Requested, Often Problematic)

Most of these tie directly to Chrono's non-predatory + accessibility + F-Droid constraints. Building them would make Chrono just another Alarmy.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Hard lockout with no real way out | "Make it impossible to cheat back to sleep" | The cruelest, most-complained-about failure in the category; a lost/unreadable code = an unstoppable alarm. Conflicts with the project's "must not trap users" constraint. | Escape hatch ON by default after timeout/attempts (locked decision). |
| Punitive escape hatch (Alarmy's 100 taps, escalating +100 each use) | Discourage "abuse" of the fallback | A dark pattern that punishes legitimate emergencies (lost code, dead room light); directly opposed to Chrono's ethics | Neutral, low-friction fallback dismiss; no escalating penalty, no shaming copy. |
| Gating **snooze** behind the scan | "Force them up even to snooze" | Adds friction with zero wake-up payoff and frustrates users mid-sleep; out of milestone scope | Gate **dismiss only** (locked). Snooze stays one tap. |
| Cloud sync / account to store the registered code | "Sync my codes across devices" | Violates Chrono's no-backend, offline-first architecture; adds a privacy surface for what is just a short string | Store the code locally in the alarm's `SettingGroup` JSON (existing pattern). |
| Uploading/transmitting camera frames or images | (implied by any "smart"/cloud scanning idea) | Privacy-hostile and unnecessary — matching is a local string compare; `flutter_zxing` decodes on-device | Decode on-device, compare `rawValue` locally, persist no images. |
| Paywalling the task or its escape hatch | Monetization | Alarmy's aggressive paywall is its top criticism; Chrono's entire edge is being the free, humane FOSS alternative | Ship the task + fallback as standard free functionality. |
| A scanner library that needs Google ML Kit / Play Services | "Best accuracy / most popular" | Breaks F-Droid (NonFreeDep), and mobile_scanner 7.x also breaks minSdk 21 | Already resolved in STACK.md: `flutter_zxing 2.2.1` (FOSS, F-Droid-clean, minSdk 21). Do NOT swap in mobile_scanner / ai_barcode_scanner / google_mlkit_barcode_scanning. |
| Alarmy-style **Photo mission** (photograph a registered place) | "Looks similar, why not add it too" | Image-similarity matching is a fuzzier, heavier, separate problem; scope creep | Out of scope — this milestone is code-matching only. |
| **Requiring** a Chrono-generated / proprietary code | "Guarantee uniqueness" | Forces printing, breaks "register any household barcode," reduces flexibility | Accept any QR/1D code the user registers (locked). A printable code may be *offered* as convenience (QRAlarm does), never required. |
| The scan task on **timers** | "Apply it everywhere" | Timers use a separate dismiss path; out of milestone scope | Alarms only (locked). |
| Silent auto-dismiss when the timeout elapses | "Just give up and stop ringing" | Defeats the alarm — a deep sleeper would sleep through | The escape hatch should still require an explicit (but easy, non-punitive) dismiss action, not silently stop the alarm. |

## Feature Dependencies

```
[CAMERA permission granted]
        └──enables──> [flutter_zxing ReaderWidget on dismiss screen]
                          └──feeds──> [Match validation] ──on match──> [Dismiss via existing onSolve path]

[Registered specific code (setup)] ──required by──> [Match validation]

[Test scan (setup)] ──reuses──> [ReaderWidget]
[Torch toggle]      ──built into──> [ReaderWidget]
[Reticle overlay]   ──built into──> [ReaderWidget]

[Escape-hatch fallback] ──triggered by──> [timeout] OR [attempt count] OR [permission denied / camera unavailable]
        └──must reach──> [existing dismiss path]
        └──IS ALSO──> [Accessibility alternative]  (screen-reader-reachable dismiss for users who cannot aim a camera)
```

### Dependency Notes

- **`ReaderWidget` is the shared dependency.** It already bundles camera + scan frame + torch, so the test-scan, torch toggle, and reticle all come "for free" once the widget is integrated. Build/integrate it once, reuse it at setup (test scan) and at ring time. This is the key ordering insight for phasing.
- **Escape hatch is load-bearing twice.** It is both the safety net (lost/unreadable code, denied permission, camera hardware failure) *and* the accessibility path for blind/low-vision users who realistically cannot frame a camera on a code (well-documented QR-accessibility barrier). Treat it as core, not polish; ensure it is reachable by screen readers and announces the three states via semantics.
- **Permission/hardware failure must route to the escape hatch.** If `CAMERA` is denied or the camera fails at ring time, the only humane outcome is the fallback dismiss — never a dead-end. (STACK.md flags this as safety-critical.)

## MVP Definition

### Launch With (v1)

- [ ] Register a specific code in the alarm task config — the feature is meaningless without it.
- [ ] Ring-time live scanner (`ReaderWidget`) that auto-opens and continuously matches the registered code — the core interaction.
- [ ] Match validation with three-state feedback + alarm-keeps-ringing contract — the wake-up guarantee.
- [ ] Camera permission/hardware handling that falls through to the escape hatch on denial/failure — non-negotiable for "never trap the user."
- [ ] Escape-hatch fallback (ON by default, single sane timeout/attempt trigger) — required by the project's ethics constraint and validated by real-world lockouts.
- [ ] **Torch toggle** — built into `ReaderWidget`; prevents the dominant dark-room scan failure.
- [ ] **Test scan in setup** — prevents lockout panic; reuses `ReaderWidget` for near-zero marginal cost.

### Add After Validation (v1.x)

- [ ] Configurable escape-hatch threshold (expose timeout/attempt knobs) — trigger: users ask for strictness.
- [ ] Registered-item label hint — trigger: confusion reports about "where's my code."
- [ ] Haptic/visual match confirmation polish — trigger: general UX polish pass.

### Future Consideration (v2+)

- [ ] Downloadable/printable default code generator (QRAlarm parity) — defer; optional nicety, never a requirement.
- [ ] Extending the task to timers — defer; explicitly out of this milestone's scope.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Register specific code | HIGH | LOW–MEDIUM | P1 |
| Ring-time live scanner + match | HIGH | MEDIUM | P1 |
| Three-state feedback + keeps ringing | HIGH | LOW | P1 |
| Permission/hardware failure → escape hatch | HIGH | MEDIUM | P1 |
| Escape-hatch fallback (default ON) | HIGH | MEDIUM | P1 |
| Torch toggle | HIGH (dark rooms) | LOW (built into ReaderWidget) | P1 |
| Test scan in setup | HIGH | LOW–MEDIUM | P1 |
| Configurable threshold knobs | MEDIUM | LOW–MEDIUM | P2 |
| Registered-item label hint | MEDIUM | MEDIUM | P2 |
| Haptic/visual confirmation | LOW–MEDIUM | LOW | P2 |
| Printable default-code generator | LOW | MEDIUM | P3 |
| Timer support | LOW (this milestone) | MEDIUM | P3 |

## Competitor Feature Analysis

| Feature | Alarmy | Sleep as Android | QRAlarm (FOSS) | Chrono's Approach |
|---------|--------|------------------|----------------|-------------------|
| Match target | Specific registered code | Toggle: any code OR specific | Default code or user's own | Specific registered code (locked) |
| Gating | Dismiss (mission) | Dismiss (CAPTCHA) | Dismiss | Dismiss only; snooze free (locked) |
| Escape hatch | "Emergency Mode": 100 taps, **escalating +100/use** (punitive) | "Skip if far from home" + "Sleeping sheep" fallback (humane) | (basic) | Humane fallback, ON by default, configurable, **no escalation/penalty** |
| Torch | Lighting is top troubleshooting tip | Yes | Built-in | Yes via ReaderWidget (v1) |
| Test/preview | Limited | Effectively, via setup | Default code to test | Explicit test scan in setup (v1) |
| Default printable code | No (you bring one) | Printable CAPTCHA option | **Yes (downloadable)** | Optional, deferred (v2+) |
| Monetization | Aggressive paywall (top criticism) | Paid app, no dark-pattern lockout | Free FOSS | Free + FOSS |
| Backend | Account/cloud features | Local + optional cloud | Local | Local only (no backend) |
| Scanner stack | Proprietary | Google vision + external fallback | (ZXing-family) | `flutter_zxing 2.2.1` — F-Droid-clean (locked in STACK.md) |

## Risks & Complexity Notes

- **Highest-risk sub-feature:** running the live `ReaderWidget` camera preview inside a **full-screen-intent alarm Activity shown over the lock screen** (Chrono uses `flutter_show_when_locked`; Android 14/15 tightened full-screen-intent rules, though alarm apps are exempt). The camera lifecycle is valid here because the dismiss screen is foreground UI on the main isolate (NOT the firing isolate) — STACK.md confirms this. Still, lock-screen + camera + dispose/resume (Chrono has `flutter_fgbg`) needs **real-device validation, not emulator.** Confidence on exact behavior: LOW — flag for a phase-specific spike.
- **Native build cost (already noted in STACK.md):** `flutter_zxing` is FFI to C++ (CMake/NDK), so first builds are slower and add per-ABI `.so`. Contained by Chrono's existing `--split-per-abi` release. Not a *feature* risk, but it gates the feature landing.
- **Serialization registration gotcha:** the new task type must be added to the `json_serialize.dart` `fromJsonFactories` map (CONCERNS.md), or loading a saved scan-task alarm throws at runtime. Cheap to do, expensive to forget.
- **Lowest-risk sub-features:** local string match, torch toggle, format restriction, haptic feedback — all directly supported by `flutter_zxing`'s `ReaderWidget` and the existing `vibration` dependency. Confidence: HIGH.

## Sources

Competitor / reference products:
- Alarmy Help Center — "How do I use the QR/Barcode mission?": https://alarmy-android.zendesk.com/hc/en-us/articles/360004242494--Mission-How-do-I-use-the-QR-Barcode-mission (HIGH)
- Alarmy Help Center — "Emergency situation … (Photo, QR/Barcode)" (Emergency Mode: 100 taps, escalating +100/use, 30-day reset): https://alarmy-android.zendesk.com/hc/en-us/articles/360004242434 (HIGH)
- Alarmy blog — Wake-Up Missions overview: https://alar.my/en/blog/alarmy-wake-up-mission (MEDIUM)
- Sleep as Android — CAPTCHA docs (any-vs-specific code, skip-if-far, "Sleeping sheep" fallback, external scanner): https://docs.sleep.urbandroid.org/alarms/captcha.html (HIGH)
- Sleep as Android — Alarms / backup alarm: https://sleep.urbandroid.org/documentation/core/alarms/ (HIGH)
- QRAlarm (FOSS) — F-Droid listing (GPL-3.0, downloadable default QR): https://f-droid.org/en/packages/com.sweak.qralarm/ ; source: https://github.com/sweakpl/qralarm-android (HIGH)

Accessibility references:
- AFB — UPC/QR codes for accessible identification (framing difficulty for blind users): https://afb.org/blindness-and-low-vision/using-technology/accessible-identification-systems-people-who-are-blind-1 (MEDIUM)
- BOIA — Are QR codes accessible? (camera-alignment barrier): https://www.boia.org/blog/are-qr-codes-accessible-for-people-with-disabilities (MEDIUM)

Platform / implementation:
- Android — Full-screen intent limits (Android 14/15, alarm-app exemption): https://source.android.com/docs/core/permissions/fsi-limits (HIGH)
- flutter_zxing (ReaderWidget torch/scan-frame, formats, FOSS/ZXing FFI, minSdk 21): https://pub.dev/packages/flutter_zxing and https://github.com/khoren93/flutter_zxing (HIGH)

Internal:
- `.planning/PROJECT.md`, `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STACK.md`, `.planning/codebase/CONCERNS.md`, `.planning/research/STACK.md` (HIGH, internal)

---
*Feature research for: scan-to-dismiss alarm task (Chrono)*
*Researched: 2026-05-30*
