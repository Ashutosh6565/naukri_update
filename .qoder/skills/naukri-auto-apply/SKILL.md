---
name: naukri-auto-apply
description: Run, monitor, schedule and troubleshoot the live Naukri + Wellfound job auto-apply automation in this repo. Use when the user says "run auto apply", "apply to jobs", "run naukri", "run wellfound", "apply 100 jobs a day", "check today's applications", "why did the run stop", or asks about applications.csv, apply-state files, auto-apply-*.log, external employer forms, captcha-gated forms, or Gemini-answered form questions.
---

# Naukri + Wellfound auto-apply

Playwright drives a saved Chrome profile per site, injects the site script into the job
feed, fills each application, submits it (`--live`), verifies it landed where the site
exposes an applied list, and appends a row to `applications.csv`.

## Commands

Run from the repo root (`C:\Users\DELL\OneDrive\Desktop\naukri_update`).

| Goal | Command |
|---|---|
| Both sites at once (recommended) | `node run-both.js --live` |
| Naukri only | `node auto-apply-runner.js naukri --live` |
| Wellfound only | `node auto-apply-runner.js wellfound --live` |
| Dry run (fills, never submits) | `node run-both.js` or drop `--live` on a single site |
| One-time login | `node auto-apply-runner.js naukri login` / `... wellfound login` |
| Health check | `node check-setup.js` |
| Today's status | `node .qoder/skills/naukri-auto-apply/scripts/status.cjs` |
| Enable hourly live runs | `powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -IncludeApply` |
| Scheduler status / run now / pause | `setup-schedule.ps1 -Status` / `Start-ScheduledTask NaukriAutoApply` / `Disable-ScheduledTask NaukriAutoApply` |

Window flags: hidden by default; `--minimize` keeps it in the taskbar, `--show` leaves it
on screen. `node show-windows.js` restores a hidden window.

## The 100/day target

Caps live in `SITES` in [auto-apply-runner.js](../../../auto-apply-runner.js): Naukri
`dailyCap: 50, perRun: 10`, Wellfound `dailyCap: 50, perRun: 10` — 50 + 50 = 100.

- The cap is a ceiling, not a quota. `perRun` is what one run tries; the hourly task
  (09:00–23:00) is what accumulates toward it.
- `apply-state-<site>.json` holds `{date, count}` and survives restarts; the run target is
  `min(perRun, dailyCap - count)`. Raising `perRun` is the lever for reaching 100 sooner.
- **Inventory is the real limit on Naukri.** ~85–90% of dev listings are "Apply on company
  site" (`🔗 EXTERNAL`). Those go to the employer's ATS, where many forms are captcha-gated,
  empty, or account-required and are skipped by design. A day that ends at 30 Naukri
  applications is usually a listing-supply result, not a bug. Say so instead of "fixing" code.
- Wellfound throttles on speed: keep `MIN_DELAY_MS`/`MAX_DELAY_MS` at 60 s+.

## Monitoring

- Per-site logs: `auto-apply-naukri.log`, `auto-apply-wellfound.log` (scheduled runs write
  here; console output is lost when started by the hidden `.vbs`).
- `applications.csv` — Date, Site, Role, Company, CTC/Salary, Skills, Job Link, Verified, JD.
  `Verified` is `verified` only when the site's own applied list confirmed the submission;
  `n/a` means the site exposes no applied list to check against.
- Progress lines look like `==> 4/10 this run (14/50 today)`.
- A run ends on target, on the 100-minute deadline, or after 8 browser restarts.

## Answering questions the answer bank misses

1. `answerFor()` in [external-apply.js](../../../external-apply.js) has the local bank — add
   patterns there first; it's instant and deterministic.
2. Remaining **required** fields are batched into one Gemini request by
   [answer-ai.js](../../../answer-ai.js) (`aiAnswers`), ~1–2 s per form. Page-script chatbot
   questions call Gemini directly with the key from `window.__APPLY_CONFIG`.
3. Model chain is `gemini-3.5-flash` → `gemini-flash-lite-latest` → `gemini-2.5-flash-lite`.
   `gemini-2.0-flash`/`gemini-2.5-flash` are retired (404) and `gemini-flash-latest` throws
   503; do not switch back. `thinkingConfig.thinkingBudget: 0` is what keeps latency at ~1 s.
4. `answer-ai.js` refuses captcha/recaptcha/hcaptcha/password/OTP prompts. Keep it that way.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `page looks logged-out or bot-checked` | Session expired. Run the `login` command for that site and complete any 2-step/captcha manually. `node check-setup.js` names which profile is dead. |
| `profile in use by a running job` | Another run holds the same Chrome profile. Stop it, or don't run two runners for the same site. |
| `Another <site> run is active (pid …)` | The lock `apply-lock-<site>.json` names a live runner. Let it finish; the hourly trigger takes over on its own once that run is stale (>110 min). |
| `Previous <site> run (pid …) is N min old — terminating it` | Stale-run takeover: a run frozen by laptop sleep was killed together with its Chrome. Expected, not an error. |
| `0 job cards found` on every page | DataDome/bot check. Log in visibly, solve it once, re-run. |
| `human captcha on the employer form — apply manually: <host>` | Intentional skip on external ATS forms. Never automate around it; report the host so the user can apply by hand. |
| `no submit button` | `SUBMIT_RE` doesn't match the button text. Log at `buttons: [...]`, extend the regex, add the label to `external-apply.test.js`. |
| `no application form here` right after clicking Apply | Form opened in a new tab; the Zoho-style new-tab follow should catch it. If not, check the `pagesBefore`/`pages` diff. |
| `no apply modal found` | Job opened as a full page. Skipped safely, not counted. |
| `submit did NOT go through` | Leftover React modal being reused (fixed 2026-11-04). The log names unanswered fields — extend the answer bank with those labels. |
| Browser restarted in a loop | 3 cycles with no submit and no external work. Usually a logged-out feed or bot check — check the log above the restart line. |
| CSV is short of the counter | Was a race with async applied-list verification; now awaited via `pendingCsv` before `ctx.close()`. If it recurs, check that path, don't hand-edit without re-validating 9 fields per row. |
| Want to reset today's count | Delete `apply-state-<site>.json` (only after confirming the day should restart). |

## Rules

- **Never** print, echo or read `.env` values into chat; it holds real `GOOGLE_PASSWORD`
  and `GEMINI_KEY`.
- `--live` submits real applications. Use it only when the user asked for a live run, and
  confirm before the first live run of a session.
- Never automate captcha solving, and never send captcha/password/OTP text to Gemini.
- Prefer `run-both.js` so both sites share one terminal and one Ctrl+C.

## Files

| File | Purpose |
|---|---|
| `run-both.js` | Spawns both runners, tags output `[naukri]`/`[wellfound]`, kills both on Ctrl+C |
| `auto-apply-runner.js` | Profiles, searches, daily caps, injection, CSV, external queue, restarts |
| `naukri-auto-apply.js` / `wellfound-auto-apply.js` | Per-site apply logic (also pasteable in DevTools) |
| `external-apply.js` | Drives employer ATS forms from Node; answer bank in `answerFor` |
| `answer-ai.js` | Batched Gemini answers + model fallback chain |
| `config.js` | `.env` loader (CV data, `GEMINI_KEY`) |
| `window-utils.js` | Off-screen window handling |
| `scripts/status.cjs` | Today's counts, caps and recent log lines at a glance |
