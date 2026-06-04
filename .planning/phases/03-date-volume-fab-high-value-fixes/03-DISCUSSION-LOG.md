# Phase 3: Date, Volume & FAB High-Value Fixes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-05
**Phase:** 3-Date, Volume & FAB High-Value Fixes
**Areas discussed:** Date format & migration, PR incorporation & credit, FAB fix scope, Regression test coverage

---

## Area selection

User selected all four offered gray areas: Date format & migration, PR incorporation & credit,
FAB fix scope, Regression test coverage.

---

## Date format & migration

### Q1 — Storage format

| Option | Description | Selected |
|--------|-------------|----------|
| ISO date string YYYY-MM-DD | Date-only string; no instant; immune to TZ; changes DateTimeSetting + picker | |
| Year/month/day integers | Store [y,m,d]; explicit components, no parsing ambiguity | |
| Normalized local-midnight epoch | Keep epoch, force local midnight; smallest diff but still stores an instant | |
| You decide | Claude picks cleanest within Tier-1 | ✓ |

**User's choice:** You decide.
**Claude's call:** date-only ISO string `YYYY-MM-DD` → local `DateTime(y,m,d)`; normalize picker output.
Most TZ-change-immune and easiest to migrate. (D-DATE-FORMAT)

### Q2 — Migration of existing epoch values

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-correct on upgrade | Reinterpret old epoch as originally-intended (UTC-midnight) day; affected alarms self-heal | |
| Preserve current, fix new only | Read old epoch as today (local) so nothing shifts; only new picks corrected | |
| You decide | Balance correctness vs no-surprise | ✓ |

**User's choice:** You decide.
**Claude's call:** Auto-correct — `loadValueFromJson` tolerates legacy `int` and reinterprets in UTC to
recover the intended day. Contingent on researcher confirming `table_calendar` midnight-UTC vs noon-UTC.
(D-DATE-MIGRATION)

---

## PR incorporation & credit

### Q1 — Incorporation method

| Option | Description | Selected |
|--------|-------------|----------|
| Cherry-pick upstream commits | Git authorship preserves contributor credit; pulls exact diff | |
| Cherry-pick, then adapt on top | Preserve authorship, layer our follow-up commits | |
| Reimplement + credit trailer | Write ourselves, credit via Co-authored-by trailer | |
| You decide | Per-PR judgment | |
| **Other (free text)** | **"we take all of the credit"** | ✓ |

**User's choice:** Free text — "we take all of the credit" → confirmed on follow-up as: take sole credit.
**Notes:** Claude flagged this **twice** — it inverts the locked "crediting the contributor" wording in
PR-01, PR-02, and ROADMAP success-criterion #4, and raised OSS-attribution etiquette. User confirmed:
*"nah we're taking credit."* It is the user's fork and an informed decision. Locked as D-PR-METHOD:
**reimplement independently** (no cherry-pick, no copy-then-strip), no contributor attribution; PR-01/PR-02
+ criterion #4 to be reworded at next transition.

### Q2 — Quality bar

| Option | Description | Selected |
|--------|-------------|----------|
| Hold to our correctness criteria | PR must meet VOL-01 clean cancellation / FAB-01 no-overlap; adapt if short | ✓ |
| Merge as-is if it resolves the issue | Accept on reported symptom; defer hardening | |
| You decide | Per-PR judgment | |

**User's choice:** Hold to our correctness criteria. (D-PR-QUALITY)

---

## FAB fix scope

| Option | Description | Selected |
|--------|-------------|----------|
| Shared fix at the list/FAB layer | Central bottom-clearance so all ~12 screens inherit it | ✓ |
| Alarm screen only | Fix just #417; leaves latent overlap elsewhere | |
| Alarm + other heavily-used lists | Alarm + timer/clock/stopwatch; skip rare sublists | |
| You decide | Best satisfy FAB-01 without over-reaching | |

**User's choice:** Shared fix at the list/FAB layer. (D-FAB-SCOPE)
**Notes:** FAB is a custom `Positioned` overlay (not a Material Scaffold FAB), so clearance must be an
explicit bottom inset on the scroll content. Planner to confirm a clean central injection point in
`PersistentListView`; per-screen fallback only if not centralizable.

---

## Regression test coverage

| Option | Description | Selected |
|--------|-------------|----------|
| Date + volume-cancel unit tests; FAB on-device | Test the two correctness-critical bugs; FAB on-device | |
| Date only; volume + FAB on-device | Lightest; only the trivially-testable date logic | |
| All three, including FAB widget test | Max CI coverage; FAB widget test brittle | (chosen by directive) |
| You decide | Match Phase 1/2 bar | (resolved by directive) |

**User's response:** Did not pick from the list. First asked a clarifying question — *"how much testing can
we actually do with github actions?"* — answered with a CI capability breakdown (CI = headless `flutter test`
only, no emulator: unit + headless widget tests run; real audio/lock-screen/reboot/real-device layout do not).
User then directed: *"id like you to answer that question & id like to throw it into this projects claude md so
we can default flutter / dart testing to gh actions"* and *"id really like to throw all of the testing that we
can onto github actions, for all phases / plans."*

**Resolution (Claude's call per directive):** Maximize CI — all three fixes get CI-runnable coverage: date
unit test, volume-cancellation unit test (via extracting a pure ramp controller), and a narrow headless FAB
layout widget test (degrades to on-device if too brittle). (D-TEST-COVERAGE)

**Policy change:** Added a project-wide **Testing Policy** to `CLAUDE.md` — default all CI-runnable testing
(unit + headless widget tests) to GitHub Actions for every phase/plan; refactor pure seams for testability;
on-device only for what CI genuinely can't run. (D-CI-TESTING-POLICY)

---

## Claude's Discretion

- Date storage format (D-DATE-FORMAT) — user said "you decide."
- Date migration behavior (D-DATE-MIGRATION) — user said "you decide."
- Test coverage level (D-TEST-COVERAGE) — user directed "maximize CI," Claude chose the specific tests.

## Deferred Ideas

- Reword PR-01 / PR-02 / ROADMAP success-criterion #4 to drop "crediting the contributor" (consequence of
  the sole-credit decision) — next `/gsd-transition`.
- Android emulator / `integration_test` CI job — deferrable infra.
- Broader `RingtonePlayer` test coverage (vibration, multi-player, audio focus) — future audio-hardening.
- Replace settings-by-magic-string access with typed accessors — tech debt, not this phase.
