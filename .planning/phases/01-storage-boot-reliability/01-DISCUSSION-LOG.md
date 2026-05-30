# Phase 1: Storage & Boot Reliability - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-30
**Phase:** 1-Storage & Boot Reliability
**Areas discussed:** Corrupt-data recovery, Hardening reach, Boot-failure UX

---

## Gray area selection

| Area | Description | Selected for discussion |
|------|-------------|--------------------------|
| Pre-unlock firing | Must a post-reboot alarm fire while still locked (DE storage) vs. defer until unlock | |
| Corrupt-data recovery | Silent reset vs. salvage valid entries vs. notify on corrupt/half-written data | ✓ |
| Boot-failure UX | Whether the user is told when the time-boxed splash recovers from an error | ✓ |
| Hardening reach | Harden only the text-file path vs. also fix the GetStorage dual-store drift | ✓ |

**Pre-unlock firing** was not selected → decided by Claude (defer-until-unlock; see CONTEXT D-07).

---

## Corrupt-data recovery

| Option | Description | Selected |
|--------|-------------|----------|
| Salvage per-entry | Load every valid alarm, skip + log only the corrupt one(s) | |
| Whole-file reset | Any parse failure resets the entire list to defaults | |
| You decide | Pick whichever fits the storage pattern + core value | |
| Other (free text) | "perhaps would it be better to create an alarm folder, and then each alarm gets its own alarm-NUMBER.txt?" | ✓ |

**User's choice:** Initially proposed **per-file-per-alarm storage**, then asked whether **SQLite**
would be better ("genuinely baffled at the use of plain text storage for alarms"). After a
tradeoff discussion (three tiers: harden text path / per-file / SQLite), chose **Tier 1 — harden
the text path**.

**Notes:**
- Per-file scope, if ever revisited: **alarms only** (user doesn't use timers).
- SQLite weighed and set aside: it would solve atomicity/durability at the engine level, but is a
  full storage rewrite mid-reliability-milestone, the nested `SettingGroup` document model fights a
  relational schema (only a blob-per-row shape is sane), and `sqflite` in the alarm *background
  isolate* is a real validate-before-commit risk.
- Final rationale (user): "Fuck it let's just go for tier one. I haven't had an alarm corrupt on me
  yet so we're fine. Harden the text path." → Tier 1 = atomic temp+rename writes, guarded decode,
  per-entry salvage with whole-list safe-default fallback only when the top-level structure is
  unparseable.

---

## Hardening reach (GetStorage dual-store fallback)

| Option | Description | Selected |
|--------|-------------|----------|
| Keep, make null-safe | Keep the GetStorage→text-file fallback; guard the `json.decode(null)` crash; no migration | ✓ |
| Remove the fallback | Go single-store (text files only) + explicit one-time GetStorage→file migration | |
| You decide | Pick whichever fits the Tier 1 minimal-change principle | |

**User's choice:** Keep, make null-safe.
**Notes:** Consistent with the Tier 1 "don't rewrite storage mid-fix" decision. Guarding the
decode is required by BOOT-04 regardless; removing the dual store + migration was judged too big
for this phase. Dual-store drift remains a documented, now non-fatal, wart.

---

## Boot-failure UX

| Option | Description | Selected |
|--------|-------------|----------|
| Silent + log only | Always reach normal UI; log recovery; never interrupt the user | |
| One-time notice | Show a dismissible notice on any recovery | |
| Notice only if alarms lost | Silent for routine recovery; notice only when alarm data was actually reset/lost | ✓ |

**User's choice:** Notice only if alarms lost.
**Notes:** Time-box the splash so a recoverable error never hangs (always reach the normal UI).
Targets the one-time, localized, dismissible notice to the missed-wake-up case — fires when ≥1
alarm was dropped (per-entry salvage) or the alarm list was reset. Needs a new Weblate string +
"alarms were lost" detection; notice must be screen-reader reachable.

---

## Claude's Discretion

- **Pre-unlock firing** (area not selected) → defer-until-unlock; pure code guard, no
  device-protected (DE) storage work; revisit in planning if on-device boot behavior requires it.
- Splash/init timeout duration + mechanism.
- Atomic-write temp-file naming / fsync strategy.
- Storage location of the "alarms were lost" flag and notice rendering (snackbar vs. banner).
- Whether to apply the same hardening to `timers.txt` / other list files (apply unless a reason not to surfaces).

## Deferred Ideas

- Per-file-per-alarm storage (alarms only) — future storage-refactor milestone.
- SQLite (blob-per-row) persistence — future milestone; requires alarm-isolate validation.
- Remove GetStorage dual store + explicit migration — future single-store refactor.
