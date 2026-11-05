# Naukri + Wellfound Auto-Apply

Job-application automation that runs locally in real Chrome via Playwright:

- **100 applications/day target** — Naukri 50 + Wellfound 50, 10 per hourly run.
- **Auto-apply on both sites**, including "Apply on company site" forms on the employer's own ATS.
- **Answers form questions** from a local answer bank, falling back to **Gemini** for anything it doesn't know.
- **Keeps your Naukri profile fresh** every hour (headline update + resume re-upload).
- **Records everything** in `applications.csv`, and verifies submissions where the site exposes an applied list.
- **Scheduled** via Windows Task Scheduler, hidden, daytime only.

All personal data and credentials live in `.env`; nothing personal is hard-coded. The repo is private.

---

## Requirements

| Requirement | Notes |
|---|---|
| Windows 10/11 | Task Scheduler is used for the hourly runs. Manual runs work anywhere Node does. |
| Node.js 18+ | `npm install` pulls `playwright-core` and the stealth plugin. |
| Google Chrome | Runs are headed but off-screen; headless is blocked by both sites' bot checks. |
| Naukri account | Signed in with Google, with a resume uploaded. |
| Wellfound account | Profile and resume completed. |
| Resume PDF | Path set in `RESUME_FILE`; attached to external forms and uploaded to Naukri. |
| Gemini API key | Optional (`GEMINI_KEY`), free tier is enough. Without it, only the local answer bank is used. |

---

## Setup

**1. Clone and install**

```bash
git clone https://github.com/Ashutosh6565/naukri_update.git
cd naukri_update
npm install
```

**2. Create `.env`**

```bash
copy .env.example .env
```

Fill in every field. The important groups:

| Variable | Purpose |
|---|---|
| `GOOGLE_EMAIL`, `GOOGLE_PASSWORD` | Google sign-in used by the Naukri refresh and `wellfound-login.js` |
| `NAUKRI_PROFILE_URL` | Default `https://www.naukri.com/mnjuser/profile` works for every account |
| `RESUME_FILE` | Resume PDF, relative to the repo or absolute |
| `NAME`, `EMAIL`, `PHONE`, `LOCATION` | Identity used on every form |
| `CURRENT_ROLE`, `COMPANY`, `EDUCATION`, `YEARS_EXPERIENCE`, `SKILLS` | Profile and application answers |
| `HIGHLIGHTS` | Up to 5 achievements separated by `\|\|` |
| `NOTICE_PERIOD`, `CURRENT_CTC`, `EXPECTED_CTC`, `DOB`, `GENDER`, `WORK_AUTH` | Screening answers |
| `GITHUB_URL`, `LINKEDIN_URL`, `PORTFOLIO_URL` | Added to cover letters and link fields |
| `GEMINI_KEY` | Optional; enables AI answers for unmatched questions |

`.env` is git-ignored. Never commit it or paste its contents into a chat.

**3. Log in once per browser profile**

```bash
node naukri-profile-refresh.js login                 # .naukri-chrome-profile  (profile refresh)
node auto-apply-runner.js naukri login               # .naukri-apply-profile   (Naukri applications)
node auto-apply-runner.js wellfound login            # .wellfound-chrome-profile
```

Each opens a visible Chrome window. Sign in (approve any 2-step prompt or captcha by hand),
then close the window. Sessions persist in the profile folders.

`wellfound-login.js` can automate the Google half of Wellfound sign-in:
`node wellfound-login.js` (or `--check` to only test the session).

**4. Verify everything**

```bash
node check-setup.js           # config, resume, sessions, applied-list parser
node check-setup.js --quick   # no browser windows
```

Stop any running job first — a profile already used by a run is reported as "in use".

**5. Dry run, then go live**

```bash
node run-both.js              # both sites, fills forms but never submits
node run-both.js --live       # both sites, really submits
```

---

## Commands

### Auto-apply

| Command | What it does |
|---|---|
| `node run-both.js --live` | Naukri + Wellfound together in one terminal; Ctrl+C stops both |
| `node run-both.js` | Same, dry run (nothing is submitted) |
| `node auto-apply-runner.js naukri --live` | Naukri only |
| `node auto-apply-runner.js wellfound --live` | Wellfound only |
| `node auto-apply-runner.js <site>` | Dry run for that site |
| `node auto-apply-runner.js <site> login` | Save that site's session |
| `node auto-apply-runner.js <site> --show` | Leave the Chrome window on screen |
| `node auto-apply-runner.js <site> --minimize` | Keep it in the taskbar (hidden by default) |
| `node show-windows.js [naukri\|wellfound\|refresh]` | Bring a hidden window back; `--hide` hides again |

Sites are `naukri`, `wellfound` and `indeed`. Flags are passed through by `run-both.js`.

### Naukri profile refresh

| Command | What it does |
|---|---|
| `node naukri-profile-refresh.js` | One refresh (headline dot cycle + resume re-upload) |
| `node naukri-profile-refresh.js login` | Interactive sign-in for `.naukri-chrome-profile` |
| `node naukri-profile-refresh.js --show` | Run with a visible window |

### Scheduling

```powershell
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1                    # refresh only
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -IncludeApply      # + live apply tasks
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Status            # state + next run
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -IncludeApply -NoStart  # skip the proof run
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Remove            # remove all tasks
```

```powershell
Start-ScheduledTask NaukriAutoApply       # run one now
Disable-ScheduledTask NaukriAutoApply     # pause (Enable-ScheduledTask to resume)
```

The script registers `NaukriProfileRefresh`, and with `-IncludeApply` also
`NaukriAutoApply` and `WellfoundAutoApply`. All run hidden through `run-hidden.vbs`
(generated by the script) at logon +2 minutes and then hourly. No admin rights needed.

### Monitoring

| Command | What it does |
|---|---|
| `node .qoder/skills/naukri-auto-apply/scripts/status.cjs` | Today's counts vs caps, recent log lines, counter/CSV mismatch check |
| `node .qoder/skills/naukri-auto-apply/scripts/status.cjs 20` | Same, with more log lines |
| `node check-setup.js` | Full pass/fail report |

Logs: `auto-apply-naukri.log`, `auto-apply-wellfound.log`, `naukri-refresh.log`.
Records: `applications.csv`. Counters: `apply-state-<site>.json`.

### Tests

```bash
node external-apply.test.js     # answer bank, submit/success matching, live form fill
node naukri-helpers.test.js     # Naukri helper parsing
```

---

## How the 100/day target works

Caps live in `SITES` at the top of `auto-apply-runner.js`:

```js
naukri:    { dailyCap: 50, perRun: 10, externalApply: true }
wellfound: { dailyCap: 50, perRun: 10 }
```

- The hourly task fires between **09:00 and 23:00**, waits a random **0–14 minutes**
  (so runs don't start at `HH:00:00` every hour), then submits up to **10**.
- `apply-state-<site>.json` stores `{date, count}` and survives restarts; each run's
  target is `min(perRun, dailyCap - count)`. Dry runs never increment it.
- A run also stops at 100 minutes or after 8 browser restarts.
- **The cap is a ceiling, not a quota.** Naukri dev listings are mostly "Apply on
  company site", and many employer forms are captcha-gated or account-required and are
  skipped on purpose. On a thin day Naukri finishes below 50 — that's listing supply,
  not a bug. Wellfound runs dry once its feed is exhausted.

To raise the pace, increase `perRun`; to change coverage, edit the `searches` array.
The Naukri seen-list in the profile is permanent, so more search feeds means more
inventory — the default list has twelve.

## Stale-run handling

A frozen run (laptop asleep) used to hold the task's single-instance slot and silently
skip every hourly trigger. Both apply tasks now use the **`StopExisting`** instance
policy, and the runner adds its own guard:

- `apply-lock-<site>.json` holds `{pid, startedAt}` while a run is alive.
- A second instance sees a live lock under 110 minutes old and exits
  (`Another <site> run is active`).
- A lock older than that is verified as a real runner, killed with its Chrome, and the
  new run proceeds (`Previous <site> run … terminating it`).

This keeps exactly one browser per profile, because Task Scheduler can leave the node
child alive when it stops the task.

---

## How questions are answered

1. **Answer bank first** — `answerFor()` in `external-apply.js` plus the per-site chat
   handlers. Fast, deterministic, covers the common fields (name, email, phone, CTC,
   experience, notice period, relocation, consent boxes).
2. **Gemini for the rest** — only *required* fields the bank misses are sent, batched
   into **one request per form** (~1.6 s), so a long form doesn't cost a minute of
   waiting. The page scripts send unanswered chatbot questions directly.
3. **Model chain** — `gemini-3.5-flash` → `gemini-flash-lite-latest` →
   `gemini-2.5-flash-lite`, with `thinkingBudget: 0`. `gemini-2.0-flash` and
   `gemini-2.5-flash` are retired (404); don't switch back.
4. **Never sent to the model**: captcha/reCAPTCHA/hCaptcha prompts, passwords, OTPs.
   Captcha-gated employer forms are skipped and named in the log so you can apply by hand.

## Verification and records

`applications.csv` columns:

`Date, Site, Role, Company, CTC/Salary, Skills, Job Link, Verified, Job Description`

- **Wellfound** — every submission is checked against the account's applied list (read
  from its GraphQL responses) before the row is written. `Verified` is `verified` when
  the job id appears in that list, `missing` when the list was readable but didn't
  contain it, and `unknown` when it couldn't be read (e.g. session expired).
- **Naukri** — native applies have no applied list to check against (`unknown` or `n/a`);
  external employer-site rows are written after the form's success text (`n/a`).
- Rows are written only in live mode; dry runs log `DRY_RUN — would click`.
- To reset a day's counter, delete `apply-state-<site>.json`.

## Customizing

**Wellfound** — `CONFIG` at the top of `wellfound-auto-apply.js`:

| Setting | Effect |
|---|---|
| `TITLE_KEYWORDS` | Apply only when the title contains one of these |
| `TITLE_BLOCKLIST` | Skip titles containing any of these |
| `MAX_APPLICATIONS` | Per-run cap (the runner overrides it with the remaining daily allowance) |
| `MIN_DELAY_MS` / `MAX_DELAY_MS` | Gap between applications (60–150 s; faster trips bot checks) |

**Naukri** — `SITES.naukri.searches` in `auto-apply-runner.js`, and the `CONFIG` block in
`naukri-auto-apply.js` for title filters and chatbot answers.

Both site scripts can also be pasted into the DevTools console for a one-off manual run,
but the runner is what injects them on every page load.

---

## Qoder skill

This repo ships a project skill at `.qoder/skills/naukri-auto-apply/` that teaches the
agent the commands above, the 100/day math, and the failure modes.

```
/naukri-auto-apply            # in Qoder
```

It bundles `scripts/status.cjs`, the one-command status report.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `page looks logged-out or bot-checked` | Session expired. Run the `login` command for that site; complete 2-step/captcha by hand. `node check-setup.js` names the dead profile. |
| `0 job cards found` on every page | DataDome/bot check on Wellfound. Log in visibly, solve the slider once, re-run. |
| `profile in use by a running job` | Another run holds the profile. Wait for it, or stop it (`apply-lock-<site>.json` names the PID). |
| `Another <site> run is active (pid …)` | Expected: a live run under 110 minutes is left alone. The next hourly trigger takes over once it's stale. |
| `human captcha on the employer form — apply manually: <host>` | Intentional skip. The host is named so you can apply by hand. |
| `no submit button` | The button text doesn't match. The log lists the visible `buttons: [...]`; extend `SUBMIT_RE` and add the label to `external-apply.test.js`. |
| `no application form here` | Handoff landed on a job-search page or an empty ATS. Skipped, not counted. |
| `submit did NOT go through` | Leftover React modal from the previous job. The log names unanswered fields — add them to the answer bank. |
| Gemini answers stopped | Missing/expired `GEMINI_KEY`, or a retired model. Check the chain in `answer-ai.js`. |
| Hourly runs skipped all afternoon | A run froze with the laptop asleep. Fixed by `StopExisting` + the lock; verify with `setup-schedule.ps1 -Status`. |
| Task result `1` | The run itself failed. Read `auto-apply-<site>.log` or `naukri-refresh.log`. |
| Want to watch a hidden run | `node show-windows.js`; `node show-windows.js --hide` to hide again. |

---

## Files

| File | Purpose |
|---|---|
| `auto-apply-runner.js` | Playwright supervisor: profiles, searches, caps, injection, CSV, external queue, restarts, lock |
| `run-both.js` | Runs Naukri and Wellfound side by side with per-site output tags |
| `naukri-auto-apply.js` | Naukri apply logic (also pasteable into DevTools) |
| `wellfound-auto-apply.js` | Wellfound apply logic (also pasteable into DevTools) |
| `external-apply.js` | Drives employer ATS forms; local answer bank (`answerFor`) |
| `answer-ai.js` | Batched Gemini fallback with model chain |
| `naukri-profile-refresh.js` | Hourly profile refresh + resume re-upload |
| `wellfound-login.js` | Google sign-in helper for Wellfound |
| `config.js` | Minimal `.env` loader |
| `check-setup.js` | One-command setup verification |
| `window-utils.js`, `show-windows.js` | Off-screen window handling |
| `setup-schedule.ps1` | Registers/removes the Windows tasks, generates `run-hidden.vbs` |
| `naukri-helpers.js` | Small Naukri parsing helpers |
| `*.test.js` | Tests for the answer bank, submit matching and helpers |
| `.qoder/skills/naukri-auto-apply/` | Project skill + `scripts/status.cjs` |
| `.env` | Your data and credentials (git-ignored) |
| `applications.csv` | Every submitted application (git-ignored) |
| `apply-state-<site>.json` | Today's count toward that site's cap (git-ignored) |
| `apply-lock-<site>.json` | Present only while a run is alive (git-ignored) |
| `auto-apply-<site>.log`, `naukri-refresh.log` | Run history (git-ignored) |
| `.naukri-chrome-profile/`, `.naukri-apply-profile/`, `.wellfound-chrome-profile/` | Saved sessions (git-ignored) |

---

## Disclaimer

Automating applications and profile updates may violate Naukri's and Wellfound's Terms
of Service, and can get an account rate-limited or banned. Delays are deliberately
human-like and everything runs on your own machine with your own account. The tool
deliberately does not solve captchas. Use at your own risk.
