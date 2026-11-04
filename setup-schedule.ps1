# Registers the hourly Naukri profile refresh in Windows Task Scheduler.
#
#   Install:  powershell -ExecutionPolicy Bypass -File setup-schedule.ps1
#   Status:   powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Status
#   Remove:   powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Remove
#
# Optional live auto-apply tasks (submits real applications):
#   powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -IncludeApply
#
# The task runs when you log in and then every hour, with no console window: Task
# Scheduler starts wscript.exe, which runs node hidden. No admin rights needed.
#
# Why not a boot trigger: Chrome cannot run headless here (Naukri's Akamai bot-check
# blocks headless browsers), so every run needs a real desktop session to draw into.
# A boot trigger would fire before one exists, so the task is bound to logon instead.
#
# run-hidden.vbs is machine-specific (absolute paths) and git-ignored, so this script
# generates it. The previous version expected it to already exist, failed with
# "run-hidden.vbs not found", and registered nothing.

param(
  [switch]$Remove,
  [switch]$Status,
  [switch]$IncludeApply,
  [switch]$NoStart
)

$ErrorActionPreference = 'Stop'

$repo    = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs     = Join-Path $repo 'run-hidden.vbs'
$user    = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USERNAME }
$refresh = Join-Path $repo 'naukri-profile-refresh.js'

$core = @(
  @{ Name = 'NaukriProfileRefresh'
     Args = 'naukri-profile-refresh.js'
     Desc = 'Hourly Naukri profile refresh (headline dot cycle + daily resume re-upload). Runs hidden at logon and every hour.' }
)

$optional = @(
  @{ Name = 'NaukriAutoApply'
     Args = 'auto-apply-runner.js naukri --live --scheduled'
     Desc = 'Hourly Naukri auto-apply. 10 per run, 50/day cap, 09:00-23:00 only. Runs hidden; a new trigger replaces a stale run.' }
  @{ Name = 'WellfoundAutoApply'
     Args = 'auto-apply-runner.js wellfound --live --scheduled'
     Desc = 'Hourly Wellfound auto-apply. 10 per run, 50/day cap, 09:00-23:00 only. Runs hidden; a new trigger replaces a stale run.' }
)

$defs = if ($IncludeApply) { $core + $optional } else { $core }

function Get-NodePath {
  $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($cmd -and (Test-Path $cmd.Source)) { return $cmd.Source }
  $fallback = Join-Path $env:ProgramFiles 'nodejs\node.exe'
  if (Test-Path $fallback) { return $fallback }
  throw 'Node.js was not found. Install it from https://nodejs.org/ and re-run this script.'
}

function Find-Chrome {
  $candidates = @(
    (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
  )
  return $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

# [long], not [int]: Task Scheduler reports HRESULT-style failures like 0x80070420 as
# 2147946720, which overflows Int32 and crashed -Status with a cast error.
function Format-Result([long]$code) {
  switch ($code) {
    0          { '0 (success)' }
    267009     { '267009 (running)' }
    267011     { '267011 (has not run yet)' }
    2147942402 { '2147942402 (file not found - re-run setup)' }
    2147946720 { '2147946720 (another instance is already running)' }
    -2147024894 { '-2147024894 (file not found - re-run setup)' }
    1          { '1 (script exited with an error - see the run log in the repo folder)' }
    default    { "$code" }
  }
}

function Show-Trigger($trigger) {
  $cls = $trigger.CimClass.CimClassName
  if ($cls -eq 'MSFT_TaskLogonTrigger') {
    $delay = if ($trigger.Delay) { " (starts $($trigger.Delay) after logon)" } else { '' }
    Write-Host "  trigger: at logon$delay"
  } elseif ($cls -eq 'MSFT_TaskDailyTrigger') {
    $rep = if ($trigger.Repetition.Interval) { "every $($trigger.Repetition.Interval)" } else { 'no repeat' }
    Write-Host "  trigger: daily from $($trigger.StartBoundary), $rep"
  } elseif ($cls -eq 'MSFT_TaskTimeTrigger') {
    Write-Host "  trigger: once at $($trigger.StartBoundary), repeat $($trigger.Repetition.Interval)"
  } else {
    Write-Host "  trigger: $cls"
  }
}

function Show-StatusFor($def, [bool]$isOptional) {
  # Write-Host for the details: pipeline output from this function is the boolean
  # health result, and mixing strings into it made callers and -Status misread it.
  $t = Get-ScheduledTask -TaskName $def.Name -ErrorAction SilentlyContinue
  Write-Host ""
  Write-Host "$($def.Name)"
  if (-not $t) {
    if ($isOptional) { Write-Host '  NOT REGISTERED (optional - add -IncludeApply to enable)' }
    else            { Write-Host '  NOT REGISTERED - run: powershell -ExecutionPolicy Bypass -File setup-schedule.ps1' }
    return $false
  }

  $i = Get-ScheduledTaskInfo -TaskName $def.Name -ErrorAction SilentlyContinue
  Write-Host "  state   : $($t.State)"
  Write-Host "  action  : $($t.Actions[0].Execute) $($t.Actions[0].Arguments)"
  $t.Triggers | ForEach-Object { Show-Trigger $_ }
  Write-Host "  next run: $(if ($i.NextRunTime) { $i.NextRunTime } else { '(none scheduled)' })"
  Write-Host "  last run: $(if ($i.LastRunTime -and $i.LastRunTime.Year -gt 1999) { "$($i.LastRunTime)  result $((Format-Result ([long]$i.LastTaskResult)))" } else { 'never' })"
  Write-Host "  launcher: $(if (Test-Path $vbs) { 'ok (run-hidden.vbs)' } else { 'MISSING - re-run setup' })"

  $hourly = @($t.Triggers | Where-Object { $_.Repetition -and $_.Repetition.Interval -eq 'PT1H' })
  $logon  = @($t.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' })
  $ok = ($hourly.Count -gt 0) -and ($logon.Count -gt 0) -and ($t.Actions[0].Execute -match 'wscript')
  if (-not $ok) {
    Write-Host '  PROBLEM : expected a logon trigger, an hourly (PT1H) trigger, and wscript.exe - re-run setup'
  }
  return $ok
}

if ($Status) {
  $healthy = $true
  foreach ($d in $core)     { if (-not (Show-StatusFor $d $false)) { $healthy = $false } }
  foreach ($d in $optional) { Show-StatusFor $d $true | Out-Null }

  ""
  if ($healthy) {
    "Hourly refresh is registered correctly. Log: $repo\naukri-refresh.log"
    exit 0
  }
  "Hourly refresh is NOT registered correctly - run setup-schedule.ps1 to fix it."
  exit 1
}

if ($Remove) {
  foreach ($d in ($core + $optional)) {
    try {
      Unregister-ScheduledTask -TaskName $d.Name -Confirm:$false -ErrorAction Stop
      "removed: $($d.Name)"
    } catch { "not present: $($d.Name)" }
  }
  return
}

# ---------------------------------------------------------------- pre-flight
$node = Get-NodePath
$chrome = Find-Chrome
if (-not $chrome) {
  throw 'Google Chrome was not found in the standard install locations. Install Chrome and re-run this script.'
}
if (-not (Test-Path $refresh)) {
  throw "naukri-profile-refresh.js not found next to this script ($refresh)"
}
if (-not (Test-Path (Join-Path $repo '.env'))) {
  Write-Warning '.env is missing - copy .env.example to .env and fill it in before the first run.'
}
if ($IncludeApply -and -not (Test-Path (Join-Path $repo '.wellfound-chrome-profile'))) {
  Write-Warning 'Wellfound has no saved session - run: node auto-apply-runner.js wellfound login'
}

# ---------------------------------------------------------------- hidden launcher
# sh.Run(..., 0, True): window style 0 hides the console, True waits for node to exit.
# Waiting keeps the task state "Running" for the length of the run. Apply tasks use
# StopExisting so a run frozen by sleep cannot block the next hour's trigger; the
# runner's own apply-lock-<site>.json guard is what keeps two browsers off one profile.
$vbsContent = @'
' Auto-generated by setup-schedule.ps1 - contains absolute paths, do not edit.
Option Explicit
Dim sh, nodeExe, cmd, i, code
Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = "__REPO__"
nodeExe = "__NODE__"
cmd = """" & nodeExe & """"
For i = 0 To WScript.Arguments.Count - 1
  cmd = cmd & " """ & WScript.Arguments(i) & """"
Next
code = sh.Run(cmd, 0, True)
WScript.Quit code
'@
$vbsContent = $vbsContent.Replace('__REPO__', $repo).Replace('__NODE__', $node)
Set-Content -Path $vbs -Value $vbsContent -Encoding ASCII
"launcher: $vbs"
"node    : $node"
"chrome  : $chrome"
""

# ---------------------------------------------------------------- register
$ok = 0; $bad = 0
$registered = @()

foreach ($d in $defs) {
  try { Unregister-ScheduledTask -TaskName $d.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}

  try {
    # Do not quote {1}: it can be several arguments (extra-apply runs), and the
    # launcher re-quotes each one for node. Quoting the whole string made wscript see
    # one argument, so node got no script name and exited 1 with a usage message.
    $action = New-ScheduledTaskAction -Execute 'wscript.exe' `
                -Argument ('"{0}" {1}' -f $vbs, $d.Args) -WorkingDirectory $repo

    # 1) at logon, 2 minutes after the desktop settles (covers "I just opened the laptop").
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $user
    $logon.Delay = 'PT2M'

    # 2) hourly cadence with a real StartBoundary. The old registration used a -Once
    #    trigger that serialised with an empty StartBoundary, so Windows had no next
    #    run time and nothing fired after the first manual start. A daily trigger with
    #    a one-day repetition window gives Windows a concrete "next run" immediately
    #    and keeps ticking every hour even when the laptop was logged in before setup.
    $now = Get-Date
    $startAt = $now.Date.AddHours($now.Hour + 1).AddMinutes(2)
    $daily = New-ScheduledTaskTrigger -Daily -At $startAt
    $daily.Repetition = New-CimInstance -ClassName MSFT_TaskRepetitionPattern `
                          -Namespace Root/Microsoft/Windows/TaskScheduler -ClientOnly `
                          -Property @{
                            Interval            = 'PT1H'
                            Duration            = 'P1D'
                            StopAtDurationEnd   = $false
                          }

    # StartWhenAvailable also catches a run missed while the laptop was asleep or off.
    # Apply runs want StopExisting: a run frozen by sleep can hold the single-instance
    # slot for hours and silently skip every hourly trigger, so the new trigger wins.
    # New-ScheduledTaskSettingsSet's enum only offers Parallel/Queue/IgnoreNew, so
    # StopExisting is patched into the task XML right after registration.
    $settings = New-ScheduledTaskSettingsSet `
                  -StartWhenAvailable `
                  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                  -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
                  -MultipleInstances IgnoreNew `
                  -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5)

    Register-ScheduledTask -TaskName $d.Name -Action $action `
      -Trigger @($logon, $daily) -Settings $settings `
      -Description $d.Desc -RunLevel Limited -ErrorAction Stop | Out-Null

    if ($d.Name -like '*AutoApply') {
      $xml = (Export-ScheduledTask -TaskName $d.Name) -replace
        '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>',
        '<MultipleInstancesPolicy>StopExisting</MultipleInstancesPolicy>'
      Register-ScheduledTask -TaskName $d.Name -Xml $xml -Force -ErrorAction Stop | Out-Null
    }

    # Verify instead of assuming. The old script printed "registered" from a loop that
    # never checked, and reported success for tasks that had failed to register.
    $t = Get-ScheduledTask -TaskName $d.Name -ErrorAction Stop
    $hourly = @($t.Triggers | Where-Object { $_.Repetition -and $_.Repetition.Interval -eq 'PT1H' })
    $hasLogon = @($t.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' })
    if ($hourly.Count -eq 0)      { throw 'registered, but no hourly (PT1H) trigger is present' }
    if ($hasLogon.Count -eq 0)    { throw 'registered, but the logon trigger is missing' }
    if ($t.Actions[0].Execute -notmatch 'wscript') { throw "registered, but the action is '$($t.Actions[0].Execute)', not wscript.exe" }

    $info = Get-ScheduledTaskInfo -TaskName $d.Name
    $next = if ($info.NextRunTime) { $info.NextRunTime } else { '(set after next logon)' }
    "  OK   $($d.Name)  (logon + every hour, next: $next)"
    $ok++
    $registered += $d.Name
  }
  catch {
    "  FAIL $($d.Name)  $($_.Exception.Message)"
    $bad++
  }
}

""
"$ok registered, $bad failed."
if ($bad -gt 0) {
  "Some tasks did not register - nothing will run on a schedule until that is fixed."
  exit 1
}

# ---------------------------------------------------------------- prove it runs now
if (-not $NoStart) {
  ""
  "Starting one run now to prove the launcher works..."
  foreach ($name in $registered) { Start-ScheduledTask -TaskName $name }
  Start-Sleep -Seconds 8
  foreach ($name in $registered) {
    $i = Get-ScheduledTaskInfo -TaskName $name
    "  $name : $((Format-Result ([long]$i.LastTaskResult)))"
  }
  ""
  "The first run takes about 1-2 minutes and stays hidden."
  "Check results in: $repo\naukri-refresh.log"
}

""
"Verify:      powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Status"
"Pause one:   Disable-ScheduledTask NaukriProfileRefresh"
"Resume one:  Enable-ScheduledTask NaukriProfileRefresh"
"Remove all:  powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Remove"
