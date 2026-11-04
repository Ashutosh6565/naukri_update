# Auto-Apply

Job-application automation for **Naukri**, **Wellfound** and **Indeed**, plus an
hourly **Naukri profile refresh** that keeps your profile at the top of recruiter
searches. Everything runs locally in Chrome via Playwright, and every personal
detail lives in `.env` — nothing is hard-coded in the scripts.

| What | Entry point |
|---|---|
| Keep the Naukri profile "recently updated" (hourly) | `node naukri-profile-refresh.js` |
| Auto-apply on Naukri + Wellfound together | `node run-both.js --live` |
| Auto-apply on Naukri | `node auto-apply-runner.js naukri` |
| Auto-apply on Wellfound | `node auto-apply-runner.js wellfound` |
| Auto-apply on Indeed | `node auto-apply-runner.js indeed` |
| Today's counts, caps and last log lines | `node .qoder/skills/naukri-auto-apply/scripts/status.cjs` |

The apply runners start in **DRY RUN** mode — they fill everything but never press
Send — so you can watch them work before adding `--live`.

---

# Part 1 — Naukri profile refresh

Keeps your Naukri profile "recently updated" — recruiters see fresh profiles first.
Every run it cycles trailing dots on your **resume headline** ("" -> "." -> ".." -> ""),
which counts as a profile update on Naukri, and re-uploads your resume PDF whenever
the profile's "Uploaded on" date is not today. Schedule it hourly and forget about it.

- Logs in automatically with your **Google account** (session is saved after the first login).
- Runs in an off-screen Chrome window (Naukri blocks headless browsers).
- Verifies the save actually stuck on the server before reporting success.
- Re-uploads the resume daily; pass `--force-cv` to re-upload even when the date is already today.
- All personal data lives in `.env` — nothing sensitive is in the code.

## Requirements

- Windows 10/11 (uses Task Scheduler for the hourly run)
- [Node.js](https://nodejs.org/) 18+
- Google Chrome installed
- A Naukri account that signs in with Google

## Setup

**1. Clone and install:**

```powershell
git clone https://github.com/ankitbaghel01/naukri_update.git
cd naukri_update
npm install
```

**2. Create your `.env`:**

```powershell
copy .env.example .env
```

Open `.env` and fill in at least:

| Variable | What it is |
|---|---|
| `GOOGLE_EMAIL` | The Google account your Naukri profile uses |
| `GOOGLE_PASSWORD` | Its password (used only for the automated sign-in) |
| `NAUKRI_PROFILE_URL` | Your Naukri profile page — the default `https://www.naukri.com/mnjuser/profile` works for every account |
| `RESUME_FILE` | Resume PDF re-uploaded to the profile daily — filename relative to this folder, or an absolute path |

`.env` is git-ignored, so your credentials never get pushed.

**3. First login (one time, visible browser):**

```powershell
node naukri-profile-refresh.js login
```

A Chrome window opens and signs in with Google. If Google asks for 2-step
verification, approve it once — the session is saved to `.naukri-chrome-profile/`
and reused by every later run.

**4. Test a silent run:**

```powershell
node naukri-profile-refresh.js
```

Check `naukri-refresh.log` — you should see a line like:

```
[27/7/2026, 1:05:12 pm] OK: headline dot 1 added (verified), cv up-to-date → "AI Full Stack Developer | ..."
```

## Run it automatically (one command)

Run this once in PowerShell, from this folder:

```powershell
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1
```

That registers **NaukriProfileRefresh** and starts one run immediately to prove it
works. After that it runs:

- **2 minutes after you log in** — covers opening the laptop for the day,
- **every hour** while you are logged in,
- **hidden** — no console window and no visible browser window,
- **catch-up** — a run missed while the laptop was asleep or off starts when Windows
  is available again (`StartWhenAvailable`).

Nothing to edit: the script finds Node.js and Chrome and generates the hidden
launcher (`run-hidden.vbs`) itself.

```powershell
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Status   # registered? next run?
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Remove   # remove the task
Start-ScheduledTask NaukriProfileRefresh                               # run one extra now
Disable-ScheduledTask NaukriProfileRefresh                             # pause
Enable-ScheduledTask NaukriProfileRefresh                              # resume
```

### What was broken, and what is fixed

The old schedule registered a task that never ran again after its first manual start:

| Problem | Why it broke | Fix |
|---|---|---|
| Setup aborted with `run-hidden.vbs not found` | The hidden launcher is machine-specific and git-ignored, but the setup script expected it to already exist | Setup now generates `run-hidden.vbs` with the real Node.js path every time |
| Task showed a blank **Next run time** and stopped after Oct 27 | It was registered with a `-Once` trigger whose `StartBoundary` serialised empty, so Windows could not compute the next hourly run | Replaced with a logon trigger **plus** a daily trigger repeating every `PT1H`, which always has a real start boundary and next-run time |
| Setup printed success although nothing was registered | The script printed from its loop instead of reading Task Scheduler back | Setup now re-reads each task and fails loudly unless `wscript.exe`, the logon trigger and the hourly trigger are all present |
| Task result was always "success" even if the run failed | `wscript.exe` exited immediately instead of waiting for Node.js | The launcher now waits for Node.js and returns its real exit code; `IgnoreNew` also prevents two browsers using one profile |
| Auto-apply tasks exited immediately with result `1` | Setup wrapped the runner's whole argument list in quotes, so Node received one bogus filename and printed its usage | Arguments are passed separately now, and the launcher quotes each one |
| Hidden apply runs left no evidence | The runner only printed to the console, which a hidden task discards | Each run now also appends to `auto-apply-<site>.log` |
| The README documented the old, broken trigger | The snippet was never updated with the code | This README now documents the actual one-command setup |

Check it any time with:

```powershell
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Status
```

A healthy task shows a logon trigger, an hourly trigger, a **next run** time, and
`last run ... result 0 (success)`.

### Profile optimization (applied 2026-11-03)

The live profile was rewritten so recruiters searching for MERN/full-stack roles can
find it. Every change was saved through Naukri's own editors and re-read from the
profile page afterwards.

| Section | Before | After |
|---|---|---|
| Name | `Ashutosh kumar` | `Ashutosh Kumar` |
| Resume headline | `Full Stack Intern focusing on MERN Stack and Agile development.` | `Full Stack Developer (MERN & Angular) \| React, Node.js, Express.js, MongoDB, REST APIs \| Immediate Joiner` |
| Profile summary | "4+ months" and an unspecified stack | Experience matches the employment dates, plus the three real projects, stack and immediate-joiner line |
| Key skills | 23 chips, including the typo `Expresjs` and no `React`, `HTML`, `TypeScript`, `REST APIs` | 24 recruiter-searchable chips: React, Express.js, TypeScript, HTML, RESTful APIs, Tailwind CSS, PostgreSQL, Docker, Linux, Python, Agile; typo and filler chips removed |
| IT skills | `Expresjs` typo; missing core tools | Typo fixed to `Express.Js`; added TypeScript, PostgreSQL, Docker, Linux, Git, Tailwind CSS with last-used year and experience |
| LinkedIn (Online profile) | old `.../ashutosh-kumar-5594611b1` URL | `https://www.linkedin.com/in/ashutoshkumar90/` |
| Preferred annual salary | ₹5,00,000 | ₹6,00,000 |
| Total experience | 0 years 5 months | 0 years 8 months (matches Apr 2026 → present) |

`.env` was corrected to match the profile so application answers stop contradicting it:
`CURRENT_ROLE` typo (`Full Stack Inter` → `Full Stack Intern`), MCA years (`2021-2025`
→ `2023-2025`), `YEARS_EXPERIENCE` (`4 months internships` → `8 months (Full Stack
Intern …)`), `CURRENT_CTC=1.8` and `EXPECTED_CTC=6` (lakhs). Secrets were not touched.

`FastAPI` is not in Naukri's skill master list, so it stays in the summary and in
`.env` but could not be added as a key skill.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Google login did not complete` in the log | Run `node naukri-profile-refresh.js login` and approve the 2-step verification prompt once manually. |
| `locator.waitFor: Timeout 15000ms exceeded` while the headline dialog is open | Naukri changed the headline field markup. The script now finds the labelled field or the visible textarea/contenteditable instead of relying only on `#resumeHeadlineTxt`. |
| `locator.fill: Element is not an <input>...` | The old selector matched the headline field's wrapper. The script now validates that it selected an editable input, textarea, or contenteditable before filling it. |
| `save did not stick` in the log | The script reloads the profile and checks the server value. If it still shows the old headline, open the saved error screenshot, run `node naukri-profile-refresh.js --show`, and check whether Naukri displayed a validation or sign-in prompt before trying again. |
| `Headline editor stayed open after Save` in the log | This can be normal in Naukri's current editor. The script now reloads the profile and verifies the saved headline directly; check the next log line for `OK` or `save did not stick`. |
| Any other error | Check `naukri-refresh-error-*.png` screenshots in the repo folder — they show exactly what the browser saw when it failed. |
| Task says `NOT REGISTERED`, or has no **next run** | The folder moved or the launcher was deleted. Re-run `setup-schedule.ps1`. |
| Task result is `2147942402` / `-2147024894` (file not found) | Windows cannot find the launcher or Node.js at its recorded path. Re-run `setup-schedule.ps1` to regenerate both paths. |
| Task result is `1` | The run itself failed (for example, the Google session expired or Naukri changed the page). Open `naukri-refresh.log` for the reason. |
| Want to start fresh | Delete the `.naukri-chrome-profile/` folder and run the `login` step again. |

## Files

| File | Purpose |
|---|---|
| `naukri-profile-refresh.js` | The refresh script |
| `setup-schedule.ps1` | Registers/verifies/removes the hidden hourly task |
| `run-hidden.vbs` | Hidden launcher, generated by `setup-schedule.ps1` (git-ignored) |
| `check-setup.js` | One command that checks config, answers, files and sessions (`node check-setup.js`) |
| `config.js` | Loads `.env` (no dependencies) |
| `.env.example` | Template — copy to `.env` and fill in |
| `naukri-refresh.log` | Run history (git-ignored) |
| `.naukri-chrome-profile/` | Saved Chrome session (git-ignored) |

## Disclaimer

Automating your own profile may be against Naukri's Terms of Service. It only
edits your own headline at a slow, human-like rate, but use at your own risk.

---

# Part 2 — Auto-apply (Naukri / Wellfound / Indeed)

Automatically applies to matching jobs on [Naukri](https://www.naukri.com) and
[Wellfound](https://wellfound.com) (ex-AngelList Talent), with a combined target of
**100 applications a day**: 50 per site, 10 per hourly run.

The quickest way in — both sites in one terminal, one Ctrl+C stops both:

```powershell
node run-both.js --live
```

`run-both.js` just spawns the two site runners below side by side. Each keeps its own
Chrome profile, daily counter and log, so they never touch each other's state.

A Playwright runner opens Chrome with the site's saved session, injects the apply
script into the job feed, and the script:

- scrolls the infinite feed and picks jobs whose **title matches your keywords** (and skips a blocklist),
- opens each job's "Apply to *Company*" panel,
- fills the **cover letter** (personalized per company/role from your `.env` data),
- answers extra questions from a built-in Q&A bank and falls back to **Gemini** for the rest
  (one batched request per form, ~1–2 s; captcha/password/OTP prompts are never sent),
- handles location prompts ("I can relocate to…"), dropdowns, radios and checkboxes,
- follows "Apply on company site" listings onto the employer's own form and fills that too
  (Naukri: ~85–90% of dev listings), skipping any form that is captcha-gated,
- submits, logs every application to `applications.csv`, and respects a **50/day cap per site**.

It starts in **DRY RUN** mode by default — it fills everything but never presses Send —
so you can watch it work before going live.

## Requirements

- Windows 10/11 (Task Scheduler used for automatic daily runs — manual runs work anywhere Node does)
- [Node.js](https://nodejs.org/) 18+
- Google Chrome
- A Wellfound account with your profile + resume completed

## Setup

**1. Clone and install:**

```powershell
git clone https://github.com/ankitbaghel01/wellfound_autoApply.git
cd wellfound_autoApply
npm install
```

**2. Create your `.env`:**

```powershell
copy .env.example .env
```

Open `.env` and fill in your details — name, contact, skills, highlights, salary
expectations, links, etc. Every application answer and cover letter is built from
these values; **nothing personal is hard-coded in the scripts**. `.env` is
git-ignored, so your data never gets pushed.

Optional: set `GEMINI_KEY` to a free Google Gemini API key — any application
question the built-in answer bank can't match gets answered by Gemini using your CV.

**3. Log in to Wellfound (one time, visible browser):**

```powershell
node auto-apply-runner.js wellfound login
```

A Chrome window opens — log in to wellfound.com, then close the window.
The session is saved to `.wellfound-chrome-profile/` and reused by every later run.

**3b. Log in to Naukri for applying (one time):**

```powershell
node auto-apply-runner.js naukri login
```

This saves a separate `.naukri-apply-profile/`, so long apply runs never collide with the
hourly profile refresh, which owns `.naukri-chrome-profile/`. Already logged in there?
Copying that folder to `.naukri-apply-profile` works too.

**4. Dry run (watch it, nothing is submitted):**

```powershell
node auto-apply-runner.js wellfound
node auto-apply-runner.js naukri
```

Chrome opens on the jobs feed, and you'll see forms being filled. The log
(`auto-apply-wellfound.log`, `auto-apply-naukri.log`) shows lines like:

```
✍ cover letter filled
🔍 DRY_RUN — would click: Apply
==> 1/10 this run (1/50 today)
```

**5. Go live:**

```powershell
node run-both.js --live          # both sites at once
node auto-apply-runner.js naukri --live
node auto-apply-runner.js wellfound --live
```

Same flow, but Send is actually clicked. Each application is appended to
`applications.csv` (Date, Site, Role, Company, CTC/Salary, Skills, Job Link, Verified,
Job Description) and counted in `apply-state-<site>.json` toward that site's 50/day cap.
`Verified` is filled only when the site's own applied list confirmed the submission.

Check progress any time with:

```powershell
node .qoder/skills/naukri-auto-apply/scripts/status.cjs
```

It prints today's counts against the caps plus the last log lines for both sites, and
flags a counter/CSV mismatch (a sign a CSV write was lost).

**Where the 100/day comes from:** Naukri 50 + Wellfound 50, and the hourly task tries 10
per site per run (`perRun` in `SITES` inside `auto-apply-runner.js`). The cap is a ceiling,
not a promise: Naukri dev listings are mostly "Apply on company site", and many of those
employer forms are captcha-gated or account-required, so they are deliberately skipped.
On a thin listing day Naukri will finish well short of 50 — that is inventory, not a bug.

## Customizing which jobs it applies to

Edit the `CONFIG` block at the top of `wellfound-auto-apply.js`:

| Setting | What it does |
|---|---|
| `TITLE_KEYWORDS` | Apply only when the job title contains one of these (case-insensitive) |
| `TITLE_BLOCKLIST` | Skip when the title contains any of these (senior, manager, .net, …) |
| `MAX_APPLICATIONS` | Per-run cap (the runner overrides it with the daily cap remaining) |
| `MIN_DELAY_MS` / `MAX_DELAY_MS` | Wait between applications (default 60–150 s — human pace; going faster trips Wellfound's bot-check) |

**Locations:** the script applies to whatever your Wellfound search filters show on
`wellfound.com/jobs` — set your filters (remote / worldwide / a city) once in the
browser and it follows them. Jobs in other locations are still handled: when
Wellfound asks, it picks "I can relocate to…" and selects the job's offered location.
Jobs the company has location-blocked are detected and skipped. Jobs posted more than
14 days ago are skipped.

## Run it automatically (Task Scheduler)

Live auto-apply is **opt-in**. The same setup script registers both apply tasks when
you pass `-IncludeApply`:

```powershell
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -IncludeApply
```

That adds `NaukriAutoApply` and `WellfoundAutoApply` — hidden, 2 minutes after logon
and then hourly. Each scheduled run waits a random 0–14 minutes, runs only between
09:00 and 23:00, submits at most 10 applications, and still respects the daily cap
(Naukri 50, Wellfound 50).

Both apply tasks use the `StopExisting` instance policy, so a run still going at the
next hour is replaced rather than silently blocking the rest of the day — which is
what happened when a run froze with the laptop asleep. Because Task Scheduler can
leave the old node process alive, the runner also writes `apply-lock-<site>.json`:
a new run exits if a live run is under 110 minutes old, and kills a stale one before
launching. That keeps two browsers off one Chrome profile either way.

Do this only after:

1. **Wellfound** has its own saved session — `node auto-apply-runner.js wellfound login`, and
2. **Naukri apply** has its own profile — `.naukri-apply-profile`. Either run
   `node auto-apply-runner.js naukri login` once, or copy the already logged-in
   `.naukri-chrome-profile` folder to `.naukri-apply-profile`, and
3. you have watched a dry run and are happy with what it would submit,

because `--live` really submits applications. Without a session the hourly task still
runs, but finds no jobs and logs `page looks logged-out or bot-checked`.

```powershell
powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Status   # all tasks + next run
Start-ScheduledTask WellfoundAutoApply                                 # run one now
Disable-ScheduledTask WellfoundAutoApply                               # pause
Enable-ScheduledTask WellfoundAutoApply                                # resume
```

To remove every task (refresh and apply): `setup-schedule.ps1 -Remove`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `human captcha on the employer form — apply manually: <host>` | Working as intended. External ATS forms behind a captcha are skipped, never solved; the log names the employer host so you can apply by hand. |
| `profile in use by a running job` | Another run still holds that Chrome profile. Stop it (Ctrl+C, or kill the node process) before starting a new one for the same site. |
| Gemini answers stopped appearing | `GEMINI_KEY` is missing/expired, or the model was retired. The chain is `gemini-3.5-flash` → `gemini-flash-lite-latest` → `gemini-2.5-flash-lite` in `answer-ai.js`; `gemini-2.0-flash` and `gemini-2.5-flash` now return 404. |
| `0 job cards found` on every page | Wellfound is showing a DataDome "Verification Required" captcha. Run `node auto-apply-runner.js wellfound login`, solve the slider once manually, close the window, re-run. |
| `Session logged out`, or `check-setup` says `session expired — run node wellfound-login.js` | The auth cookie is gone. `node wellfound-login.js` signs in with the Google account in `.env` and saves the session; only a 2-step prompt or captcha needs you. Check first with `node wellfound-login.js --check`. |
| `check-setup` says `wellfound applied list … no applications yet, nothing to seed` | Not an error: the account has not submitted anything yet, so there are no rows to read. The check now separates this from a real parser failure, which says `GraphQL parser needs updating`. |
| `no apply modal found — skipping` | That job opened as a full page instead of the apply panel — it's skipped safely and not counted. |
| `no Send button found` on many jobs in a row | Usually the bot-check again (see first row). Keep delays at 60 s+. |
| `submit did NOT go through — dialog still open` | Fixed 2026-11-04. A dialog left open by the previous job (SPA navigation keeps the React modal mounted, and its click handlers die) was reused: the script filled that *other* job's form and clicked its Send. The flow now closes any leftover (Cancel → Escape → remove overlay), refuses to use a dialog that existed before its own Apply click, and sweeps leftovers after every job. The log now names the fields the form still considers unanswered (`unanswered: …`) instead of echoing the word "required". |
| Want today's counter reset | Delete `apply-state-wellfound.json`. |

## Files

| File | Purpose |
|---|---|
| `run-both.js` | Runs Naukri and Wellfound side by side; tags output per site, Ctrl+C stops both |
| `auto-apply-runner.js` | Playwright wrapper: opens Chrome, injects the site script, logs to CSV, enforces the daily cap |
| `naukri-auto-apply.js` | The Naukri apply logic (also pasteable directly into the DevTools console) |
| `wellfound-auto-apply.js` | The Wellfound apply logic (also pasteable directly into the DevTools console) |
| `external-apply.js` | Fills and submits "Apply on company site" ATS forms; holds the local answer bank |
| `answer-ai.js` | Batched Gemini fallback for required fields the answer bank misses |
| `config.js` | Tiny no-dependency `.env` loader |
| `.env.example` | Template — copy to `.env` and fill in |
| `applications.csv` | Every submitted application (git-ignored) |
| `apply-state-<site>.json` | Today's application count toward that site's daily cap (git-ignored) |
| `auto-apply-<site>.log` | Run history per site, including hidden scheduled runs (git-ignored) |
| `.wellfound-chrome-profile/`, `.naukri-apply-profile/` | Saved Chrome sessions (git-ignored) |
| `.qoder/skills/naukri-auto-apply/` | Qoder skill: run/monitor/troubleshoot commands and `scripts/status.cjs` |

## Disclaimer

Auto-applying may violate Wellfound's Terms of Service and can get an
account rate-limited or banned. The delays are deliberately human-like and everything
runs on your own machine with your own account — use at your own risk, and review
the dry run before going live.
