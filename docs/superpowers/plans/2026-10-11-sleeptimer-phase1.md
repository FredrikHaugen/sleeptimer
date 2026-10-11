# Phase 1: Polish the CLI Script (v0.1.0) Implementation Plan

**Goal:** Make the `sleeptimer` zsh script reliable enough to be the reference behavior for the later Swift app. That means pausing media more reliably, sleeping safely, providing a `--yolo` flag, stopping cleanly when the Terminal window closes, and turning YOLO off in a way that is checked rather than assumed.

**Architecture:** Everything stays in the single file `sleeptimer`.

- New logic lives in small functions that the test file can call directly: `with_timeout`, `wait_sleep_state` and `hangup`.
- `countdown` now returns a status. The existing I/O wrappers (`pause_media`, `go_to_sleep`, `yolo_cmd`, `yolo_stop`, `main`) are extended.
- Tests use fake `osascript`, `pgrep`, `pmset`, `sudo` and `caffeinate` binaries. Whenever the test file runs the real pause/mute/sleep code, it sets `path=($fake_bin /bin)`, so the real tools can't be reached. A tripwire aborts the suite if `/bin` ever contains one of them.

**Tech Stack:** zsh 5.9 (macOS built-in), macOS `pmset`, `osascript`, `pgrep`, `caffeinate` and `sudo`. Optionally `media-control` (Homebrew).

**Spec:** `plan.md`, section "🛠️ Phase 1: Polish current CLI Script (v0.1.0)". Read it together with `CLAUDE.md`, whose project rules bind this plan.

### How this plan reads the spec

`plan.md` lists _candidate_ commands. Three of them are wrong for this tool or break a project rule, so the plan keeps their intent and uses a different command:

| Spec item                                                                      | Decision                                                                                                                                                                                                                                                   | Why                                                                                                                                                                                            |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Media pause via`osascript … keystroke (key code 103)`, or target Spotify/Music | **Target Music and Spotify directly** with `tell application "<app>" to pause`, only when the app is running. Keep `media-control` for everything else (browsers, YouTube, VLC…).                                                                          | `key code 103` is the **F11** key (Show Desktop), not Play/Pause. System Events can't send the media keys, and `keystroke` needs the Accessibility permission.                                 |
| Safe sleep via`pmset displaysleepnow` or System Events `sleep`                 | **Keep `osascript -e "set volume with output muted" && pmset sleepnow` exactly.** Make it safe around that line: a hung app can't block it, failures are reported, a blocked sleep is detected, and the timer doesn't fire after the Mac slept through it. | CLAUDE.md requires that exact line.`displaysleepnow` only turns the screen off, so the Mac keeps running and audio keeps playing. System Events `sleep` needs an Automation permission prompt. |
| `--yolo` flag via `caffeinate -d`/`-i`                                         | **Add `--yolo` as another spelling of the existing `sleeptimer yolo`**, which already runs `caffeinate -dims`.                                                                                                                                             | Building YOLO a second time would duplicate the root guard and its safety logic.                                                                                                               |
| Closing the terminal mid-countdown                                             | **Closing the window cancels the timer quietly**: nothing is paused, muted or put to sleep. The process exits 129, with no leftover processes and no writes to a terminal that is gone.                                                                    | README Part 2 already promises "don't close it, or the timer stops". Ctrl+C means the same thing, and YOLO already treats a closed window as "stop".                                           |
| `--yolo` cleanly terminates when toggled off                                   | **`yolo_stop` explicitly kills caffeinate, waits until sleep is really back on, and only then says so.** If sleep isn't back on, it prints how to fix it.                                                                                                  | Today it prints "Your Mac can sleep again." before the root guard has restored anything.                                                                                                       |

**Added beyond the spec (an edge case it implies):** the timer can run out while the Mac is already asleep, for example after the lid was closed. `countdown` is based on wall-clock time, so today the Mac would be muted and put back to sleep the moment you wake it. Task 3 fixes this.

## Global Constraints

- `sleeptimer` stays **one self-contained zsh file**. No new runtime dependencies beyond macOS built-ins, and `media-control` stays optional.
- The mute and sleep line must stay byte-for-byte: `osascript -e "set volume with output muted" && pmset sleepnow`.
- Never run `./sleeptimer` without `SLEEPTIMER_DRY_RUN=1`. When experimenting, also set `SLEEPTIMER_CONFIG=<temp file>`.
- Tests must never call the real `sudo`, `pmset`, `osascript`, `pgrep` or `caffeinate`. Code that would reach them runs with `path=($fake_bin /bin)`, or with `PATH=$fake_bin:$PATH` together with `SLEEPTIMER_DRY_RUN=1`.
- Every new or changed user-facing string is updated in all three places: the script, `tests/test_sleeptimer.zsh` (as an asserted substring) and `README.md`. README wording stays simple and non-technical.
- Every new trap handler starts with `(( ZSH_SUBSHELL )) && exit 1  # a $(...) helper caught the signal; the main shell handles it`.
- Work on branch `feat/sleeptimer-phase1` and land it via a PR to `master`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Don't touch the user's real `~/.config/sleeptimer/config`, and don't commit anything outside this plan's files.

## Review Focus

1. **Music or Spotify is installed but not open when the timer ends.** It must not be launched, because `tell application` opens apps. Pinned by Task 1, `pause_media never opens apps`.
2. **The first-run macOS dialog "Terminal wants to control Music" appears at night with nobody there to answer it.** The Mac must still sleep within a few seconds. Pinned by Task 1, `pause_media gives up on a hung app`.
3. **The lid was closed, or the Mac slept on its own, during the countdown.** On wake the Mac must not be muted and put back to sleep. Pinned by Task 3, `e2e late: never sleeps`.
4. **The window is closed during the 3-second "Heads up" pause, before full screen starts.** The timer must exit and never sleep. Pinned by Task 4, `hangup during heads-up never sleeps`.
5. **YOLO is stopped while the root guard is slow, or the guard fails to restore sleep.** The user must be told the truth about whether sleep is back on. Pinned by Task 5, `yolo stuck: tells how to fix`.

Manual check for the reviewer and the user: close the window while the `How long?` prompt is waiting. Closing a real window sends HUP to the whole process group, which the test file can't reproduce reliably. Expected result: the window closes and the Mac doesn't sleep.

---

## File Structure

| File                        | Change                                                                                                                                                                                                                                                  |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sleeptimer`                | New`with_timeout`, `MEDIA_APPS`, `GRACE`, `VERSION`, `hangup` and `wait_sleep_state` (replacing `wait_sleep_disabled`). Changes to `pause_media`, `go_to_sleep`, `countdown`, `yolo_cmd`, `yolo_guard` (comment only), `yolo_stop`, `usage` and `main`. |
| `tests/test_sleeptimer.zsh` | A safety tripwire. New fakes (`osascript`, `pgrep`, a long-running `caffeinate`) and new fake env. New and updated assertions per task.                                                                                                                 |
| `README.md`                 | Step 4 (pausing), the Cancel section, YOLO, the troubleshooting table and the developer section.                                                                                                                                                        |
| `CLAUDE.md`                 | Test hooks, fake env, YOLO architecture and conventions.                                                                                                                                                                                                |
| `plan.md`                   | Tick the Phase 1 checkboxes; nothing else.                                                                                                                                                                                                              |

Run every command from `/Users/figge/Dev/sleep`. Test command for every task: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`. A green run prints exactly one blank line, then `All tests passed`.

---

### Task 0: Branch

- [ ] **Step 1: Create the branch**

```bash
git checkout master && git pull && git checkout -b feat/sleeptimer-phase1
zsh tests/test_sleeptimer.zsh | tail -1
```

Expected: `All tests passed`.

---

### Task 1: Pause Music and Spotify directly, and never let a hung app block sleep

**Files:**

- Modify: `sleeptimer`. Add `with_timeout` and `MEDIA_APPS` just above `pause_media`, and replace `pause_media`.
- Modify: `tests/test_sleeptimer.zsh`. Changes go in the fake-binary block (lines 27–48) and the `pause_media` block (lines 210–221).
- Modify: `README.md`, `CLAUDE.md`.

**Interfaces:**

- Produces:
  - `with_timeout <seconds> <cmd...>`: returns the command's exit status, or 124 if the command was killed after `<seconds>` (an integer).
  - `MEDIA_APPS=(Music Spotify)`.
  - `pause_media`: always returns 0.
  - Fakes: `$fake_bin/osascript` (logs `osascript $*`; `STUB_OSASCRIPT_RC` sets the exit code; `STUB_OSASCRIPT_HANG=1` makes it hang) and `$fake_bin/pgrep` (succeeds when `$2` is in the space-separated `STUB_RUNNING`).
  - The tripwire: tests may use `path=($fake_bin /bin)` to call the real pause/mute/sleep functions safely.

- [ ] **Step 1: Add the tripwire and the new fakes to the test file**

In `tests/test_sleeptimer.zsh`, replace the fake-binary block (from `# Fake sudo / pmset / caffeinate` through `chmod +x $fake_bin/*`) with:

```zsh
# Fake sudo / pmset / caffeinate / osascript / pgrep, so no test ever changes real power settings or pauses real apps.
# The fake pmset remembers "disablesleep N" in $FAKE_STATE; until then "pmset -g" reports $STUB_SLEEP_DISABLED.
# STUB_SUDO_RC != 0 makes every sudo call fail; STUB_SUDO_N_RC != 0 fails only "sudo -n" (background guard).
# The fake sudo points the guard's fixed PATH at the fakes. Every call is appended to $FAKE_LOG.
# STUB_OSASCRIPT_RC sets osascript's exit code, STUB_OSASCRIPT_HANG=1 makes it hang; STUB_SLEEPNOW_RC sets
# "pmset sleepnow"'s; STUB_RUNNING lists the apps the fake pgrep reports as running.
fake_bin=$(mktemp -d)
export FAKE_BIN=$fake_bin FAKE_LOG=$fake_bin/calls.log FAKE_STATE=$fake_bin/state
export STUB_SLEEP_DISABLED=0 STUB_SUDO_RC=0 STUB_SUDO_N_RC=0
export STUB_OSASCRIPT_RC=0 STUB_OSASCRIPT_HANG=0 STUB_SLEEPNOW_RC=0 STUB_RUNNING=
print -l '#!/bin/sh' \
  'if [ "$1" = "-g" ]; then v=$(cat "$FAKE_STATE" 2>/dev/null || echo "$STUB_SLEEP_DISABLED")' \
  '  printf "System-wide power settings:\n SleepDisabled\t\t%s\nCurrently in use:\n sleep 1\n" "$v"; exit 0; fi' \
  'echo "pmset $*" >> "$FAKE_LOG"' \
  '[ "$1" = "sleepnow" ] && exit "$STUB_SLEEPNOW_RC"' \
  '[ "$2" = "disablesleep" ] && echo "$3" > "$FAKE_STATE"' \
  'exit 0' > $fake_bin/pmset
print -l '#!/bin/sh' \
  'echo "sudo $*" >> "$FAKE_LOG"' \
  '[ "$STUB_SUDO_RC" = 0 ] || exit "$STUB_SUDO_RC"' \
  '[ "$1" = "-v" ] && exit 0' \
  'if [ "$1" = "-n" ]; then [ "$STUB_SUDO_N_RC" = 0 ] || exit "$STUB_SUDO_N_RC"; shift; fi' \
  'if [ "$1" = "/bin/zsh" ]; then exec zsh "$2" "$3" "$(printf %s "$4" | sed "s#PATH=/usr/bin#PATH=$FAKE_BIN:/usr/bin#")"; fi' \
  'exec "$@"' > $fake_bin/sudo
print -l '#!/bin/sh' 'echo "caffeinate $*" >> "$FAKE_LOG"' > $fake_bin/caffeinate
print -l '#!/bin/sh' \
  'echo "osascript $*" >> "$FAKE_LOG"' \
  '[ "$STUB_OSASCRIPT_HANG" = 1 ] && exec sleep 30' \
  'exit "$STUB_OSASCRIPT_RC"' > $fake_bin/osascript
print -l '#!/bin/sh' \
  'for app in $STUB_RUNNING; do [ "$app" = "$2" ] && exit 0; done' \
  'exit 1' > $fake_bin/pgrep
chmod +x $fake_bin/*

# Tests that run the real pause/mute/sleep code use path=($fake_bin /bin). That is only safe while /bin
# holds none of the real tools, so stop everything if it ever does.
[[ -z $(path=(/bin); whence -p pmset osascript pgrep caffeinate sudo media-control) ]] ||
  { print "ABORT: /bin has a real pmset/osascript/pgrep/caffeinate/sudo/media-control; tests would touch the system"; exit 1 }
```

- [ ] **Step 2: Write the failing tests**

Replace the whole `pause_media` block (from `# pause_media: calls` through `rm -rf $stub_dir`) with:

```zsh
# with_timeout: passes the exit status through; kills a hung command
assert_eq "with_timeout passes status" "0 1 7" \
  "$(with_timeout 2 true; a=$?; with_timeout 2 false; b=$?; with_timeout 2 sh -c 'exit 7'; print "$a $b $?")"
t0=$EPOCHSECONDS
assert_eq "with_timeout kills hung command" "124" "$(with_timeout 1 sleep 10; print $?)"
assert_eq "with_timeout is quick" "yes" "$( (( EPOCHSECONDS - t0 <= 3 )) && print yes )"

# pause_media: "Now Playing" via media-control, plus Music/Spotify directly when they're running; never fails.
# path=(... $fake_bin /bin): fake pgrep/osascript only, so the tests never pause or open real apps.
stub_dir=$(mktemp -d)
print -l '#!/bin/sh' 'echo "$@" > "$STUB_LOG"; exit 1' > $stub_dir/media-control
chmod +x $stub_dir/media-control
export STUB_LOG=$stub_dir/log
( path=($stub_dir $fake_bin /bin); pause_media )
assert_eq "pause_media sends pause" "pause" "$(<$STUB_LOG)"
assert_eq "pause_media ignores tool failure" "0" "$( path=($stub_dir $fake_bin /bin); pause_media; print $? )"
assert_eq "pause_media missing tool ok" "0" "$( path=($fake_bin /bin); pause_media 2>/dev/null; print $? )"
assert_eq "pause_media missing tool tip" "yes" \
  "$( path=($fake_bin /bin); [[ $(pause_media 2>&1) == *'brew install media-control'* ]] && print yes )"
: > $FAKE_LOG
( path=($fake_bin /bin); export STUB_RUNNING='Music Spotify'; pause_media 2>/dev/null )
assert_eq "pause_media pauses Music and Spotify" \
  'osascript -e tell application "Music" to pause
osascript -e tell application "Spotify" to pause' "$(<$FAKE_LOG)"
: > $FAKE_LOG
( path=($fake_bin /bin); export STUB_RUNNING=; pause_media 2>/dev/null )
assert_eq "pause_media never opens apps" "" "$(<$FAKE_LOG)"
: > $FAKE_LOG; rm -f $STUB_LOG
( path=($stub_dir $fake_bin /bin); export STUB_RUNNING=Music; pause_media )
assert_eq "pause_media both ways" "yes" \
  "$([[ $(<$STUB_LOG) == pause && $(<$FAKE_LOG) == *'"Music" to pause'* ]] && print yes)"
t0=$EPOCHSECONDS
( path=($fake_bin /bin); export STUB_RUNNING=Music STUB_OSASCRIPT_HANG=1; pause_media 2>/dev/null )
assert_eq "pause_media gives up on a hung app" "yes" "$( (( EPOCHSECONDS - t0 <= 5 )) && print yes )"
: > $FAKE_LOG
rm -rf $stub_dir
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: these four fail.

- `FAIL with_timeout passes status`
- `FAIL with_timeout kills hung command`
- `FAIL pause_media pauses Music and Spotify`
- `FAIL pause_media both ways`

The two `with_timeout` tests fail with `command not found: with_timeout`. `pause_media never opens apps` and `gives up on a hung app` pass, because the old code never calls `osascript`. They become meaningful once Step 4 lands. No other failures.

- [ ] **Step 4: Implement**

In `sleeptimer`, replace the whole `pause_media` function, comment included, with:

```zsh
MEDIA_APPS=(Music Spotify)  # paused directly with AppleScript when they're open, media-control or not

# with_timeout <seconds> <cmd...> — run <cmd>, killing it after <seconds>; its exit status, or 124 on timeout.
# Guards the end of the timer: a hung app, or a permission dialog nobody answers, must not stop the sleep.
with_timeout() {
  local secs=$1; shift
  "$@" & local pid=$!
  repeat $(( secs * 5 )); do
    kill -0 $pid 2>/dev/null || { wait $pid; return }
    sleep 0.2
  done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  return 124
}

# pause_media — pause "Now Playing" with media-control (brew install media-control), and Music and
# Spotify directly when they're open. Never fails: nothing playing, a missing tool or a hung app
# must not stop the Mac sleeping.
pause_media() {
  local app
  if (( $+commands[media-control] )); then
    with_timeout 3 media-control pause >/dev/null 2>&1
  else
    print -u2 "Tip: brew install media-control to also pause YouTube and other players."
  fi
  for app in $MEDIA_APPS; do
    pgrep -xq $app 2>/dev/null || continue  # "tell application" would open an app that isn't running
    with_timeout 3 osascript -e "tell application \"$app\" to pause" >/dev/null 2>&1
  done
  return 0
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: one blank line, then `All tests passed`.

- [ ] **Step 6: Update the README**

In `README.md`, Step 4, replace:

```
If you skip this step, sleeptimer still mutes the sound and puts the Mac to
sleep, but it doesn't pause anything.
```

with:

```
If you skip this step, sleeptimer still pauses **Apple Music** and **Spotify**,
mutes the sound and puts the Mac to sleep. It just can't pause YouTube and
other players.

The first time the timer pauses Apple Music or Spotify, macOS may ask whether
**Terminal** may control it. Click **OK**.
```

In the troubleshooting table, replace these two rows:

```
| `Tip: brew install media-control ...` when the timer ends | Nothing was paused because Step 4 was skipped. Do **Step 4** if you want pausing. |
| Music or video didn't pause | Only players that show in the Mac's **Now Playing** control (in Control Center) can be paused. |
```

with:

```
| `Tip: brew install media-control ...` when the timer ends | Only Apple Music and Spotify were paused, because Step 4 was skipped. Do **Step 4** to pause YouTube and other players too. |
| Music or video didn't pause | Only players that show in the Mac's **Now Playing** control (in Control Center) can be paused. For Apple Music or Spotify, check **System Settings → Privacy & Security → Automation** and allow Terminal to control them. |
```

In "For developers", replace the code block after `When the timer ends, it runs exactly:` with:

````
```
media-control pause   # skipped (with a tip) if media-control isn't installed; errors ignored
osascript -e 'tell application "Music" to pause'     # only if Music is open
osascript -e 'tell application "Spotify" to pause'   # only if Spotify is open
osascript -e "set volume with output muted" && pmset sleepnow
```

Each pause is given 3 seconds, then skipped, so a hung app can't keep the Mac awake.
````

- [ ] **Step 7: Update CLAUDE.md**

In `CLAUDE.md`, under "Fake-command env for YOLO tests:", add these bullets after `STUB_SUDO_N_RC`:

```
- `STUB_OSASCRIPT_RC` / `STUB_OSASCRIPT_HANG=1`: the fake `osascript`'s exit code, or make it hang.
- `STUB_SLEEPNOW_RC`: the fake `pmset sleepnow`'s exit code.
- `STUB_RUNNING`: space-separated app names the fake `pgrep` reports as running.

Tests that call the real `pause_media`/`go_to_sleep` code run it with `path=($fake_bin /bin)`. A tripwire at the top of the test file aborts the suite if `/bin` ever contains a real `pmset`/`osascript`/`pgrep`/`caffeinate`/`sudo`/`media-control`.
```

Also, in the "Pure functions vs I/O" bullet, add `with_timeout` to the list of I/O wrappers.

- [ ] **Step 8: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh README.md CLAUDE.md
git commit -m "feat: pause Music and Spotify directly; time out hung pause commands

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Safe sleep — report failures and a blocked sleep

**Files:**

- Modify: `sleeptimer`. Replace `go_to_sleep`.
- Modify: `tests/test_sleeptimer.zsh`. Add a block right after the `pause_media` block.
- Modify: `README.md`.

**Interfaces:**

- Consumes:
  - From Task 1: `pause_media`, the fakes, `STUB_OSASCRIPT_RC`, `STUB_SLEEPNOW_RC` and the `path=($fake_bin /bin)` rule.
  - Existing: `sleep_disabled` (prints `0`/`1`).
- Produces: `go_to_sleep` returns 0 on success. It returns 1 with a message on stderr if the mute/sleep line failed, or if sleep is turned off system-wide afterwards. `main` passes this status on as its exit code, because `go_to_sleep` is its last command.

- [ ] **Step 1: Write the failing tests**

Add after the `pause_media` block:

```zsh
# go_to_sleep, the real (non-dry-run) path, with fakes only: path has no real pmset/osascript (see the tripwire)
gts() { ( path=($fake_bin /bin); unset SLEEPTIMER_DRY_RUN; (( $# )) && export "$@"; go_to_sleep ) }
: > $FAKE_LOG; rm -f $FAKE_STATE
gts_out=$(gts 2>&1); gts_rc=$?
assert_eq "sleep runs mute then sleepnow" \
  'osascript -e set volume with output muted
pmset sleepnow' "$(<$FAKE_LOG)"
assert_eq "sleep ok exit 0" "0" "$gts_rc"
: > $FAKE_LOG
gts_out=$(gts STUB_OSASCRIPT_RC=1 2>&1); gts_rc=$?
assert_eq "mute fails: no sleepnow" "no" "$([[ $(<$FAKE_LOG) == *sleepnow* ]] && print yes || print no)"
assert_eq "mute fails: exit 1" "1" "$gts_rc"
assert_eq "mute fails: says so" "yes" \
  "$([[ $gts_out == *"Couldn't mute the sound and put the Mac to sleep"* ]] && print yes)"
gts_out=$(gts STUB_SLEEPNOW_RC=1 2>&1); gts_rc=$?
assert_eq "sleepnow fails: exit 1" "1" "$gts_rc"
assert_eq "sleepnow fails: says so" "yes" \
  "$([[ $gts_out == *"Couldn't mute the sound and put the Mac to sleep"* ]] && print yes)"
gts_out=$(gts STUB_SLEEP_DISABLED=1 2>&1); gts_rc=$?
assert_eq "sleep blocked: exit 1" "1" "$gts_rc"
assert_eq "sleep blocked: says how to fix" "yes" \
  "$([[ $gts_out == *'may not have gone to sleep'*'sleeptimer yolo off'* ]] && print yes)"
: > $FAKE_LOG; rm -f $FAKE_STATE
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: these four fail.

- `FAIL mute fails: says so`
- `FAIL sleepnow fails: says so`
- `FAIL sleep blocked: exit 1`
- `FAIL sleep blocked: says how to fix`

`sleep runs mute then sleepnow` already passes; it pins the exact command, which must never change. No other failures.

- [ ] **Step 3: Implement**

In `sleeptimer`, replace `go_to_sleep` with:

```zsh
# go_to_sleep — pause, mute and sleep. Returns 1, with the reason, if the Mac couldn't be muted and
# put to sleep, or if sleep is turned off system-wide (pmset sleepnow then does nothing).
# The mute + sleep line must stay exactly as it is.
go_to_sleep() {
  if [[ -n $SLEEPTIMER_DRY_RUN ]]; then
    print "DRY RUN: pause + mute + sleep"
    return
  fi
  pause_media
  if ! { osascript -e "set volume with output muted" && pmset sleepnow }; then
    print -u2 "Couldn't mute the sound and put the Mac to sleep."
    return 1
  fi
  if (( $(sleep_disabled) )); then
    print -u2 "Sleep is turned off system-wide, so your Mac may not have gone to sleep. To fix it: sleeptimer yolo off"
    return 1
  fi
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: one blank line, then `All tests passed`.

- [ ] **Step 5: Update the README**

In the troubleshooting table, add these two rows right after the `Heads up: sleep is turned off system-wide` row:

```
| `Sleep is turned off system-wide, so your Mac may not have gone to sleep` | Same cause as above: something switched sleep off while the timer ran. Type `sleeptimer yolo off`. |
| `Couldn't mute the sound and put the Mac to sleep.` | macOS refused. Put the Mac to sleep from the  Apple menu → **Sleep** this time, and try the timer again tomorrow. If it keeps happening, restart the Mac. |
```

- [ ] **Step 6: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh README.md
git commit -m "feat: report when the Mac couldn't be muted and put to sleep

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Don't fire on wake when the Mac slept through the deadline

**Files:**

- Modify: `sleeptimer`. Add a `GRACE` constant next to `MAX_SECS`, and change the end of `countdown` and of `main`.
- Modify: `tests/test_sleeptimer.zsh`. Changes go in the countdown section and the e2e section.
- Modify: `README.md`, `CLAUDE.md`.

**Interfaces:**

- Consumes: `countdown <total>` (existing) and `run` (the e2e helper in the test file).
- Produces:
  - `GRACE=${SLEEPTIMER_GRACE:-60}`, in seconds.
  - `countdown <total>` returns 0 normally, and 1 if it ended more than `GRACE` seconds after the deadline.
  - `main` prints `Time ran out while your Mac was asleep, so it won't go to sleep now.` and returns 0 without calling `go_to_sleep`.

- [ ] **Step 1: Write the failing tests**

In the compact-mode countdown block, add these two lines right after `assert_eq "countdown duration ok" …` (that block runs with `TICK=0.3`):

```zsh
assert_eq "countdown on time ok" "0" "$(SLEEPTIMER_TUI=0 countdown 1 >/dev/null; print $?)"
assert_eq "countdown late fails" "1" "$(GRACE=0 TICK=2.5 SLEEPTIMER_TUI=0 countdown 1 >/dev/null; print $?)"
```

In the e2e block, add right after `assert_eq "e2e too long exit 1" …`:

```zsh
e2e=$(SLEEPTIMER_TICK=2.5 SLEEPTIMER_GRACE=0 run 1s 2>/dev/null)
assert_eq "e2e late: explains"     "yes" "$([[ $e2e == *'Time ran out while your Mac was asleep'* ]] && print yes)"
assert_eq "e2e late: never sleeps" "no"  "$([[ $e2e == *'DRY RUN'* ]] && print yes || print no)"
```

These work as follows. With a 2.5-second tick, a 1-second timer is checked for the first time at least 1 second late. With `GRACE=0`, that counts as "the Mac was asleep". With the real 1-second tick, `elapsed` grows by at most 1 per check, so a normal run stops at exactly `total` and is 0 seconds late.

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: these three fail.

- `FAIL countdown late fails` (actual `0`)
- `FAIL e2e late: explains`
- `FAIL e2e late: never sleeps`

`countdown on time ok` already passes.

- [ ] **Step 3: Implement**

In `sleeptimer`, add after the `MAX_SECS=…` line:

```zsh
GRACE=${SLEEPTIMER_GRACE:-60}  # seconds late before we assume the Mac slept through the end of the timer
```

In `countdown`, change the comment and add one line after the closing `fi` of the `if use_tui` block. The function then reads:

```zsh
# countdown <total> — redraw until total seconds of wall-clock time pass. Returns 1 if it ended more than
# GRACE seconds late: the Mac was asleep (lid closed) when time ran out, so sleeping now would be wrong.
countdown() {
  local total=$1 start=$EPOCHSECONDS elapsed=0
  local end=$(( start + total ))
  if use_tui; then
    screen_enter
    while (( elapsed < total )); do
      draw_screen $elapsed $total $end
      sleep $TICK
      elapsed=$(( EPOCHSECONDS - start ))
    done
    draw_screen $total $total $end
    screen_leave
  else
    while (( elapsed < total )); do
      printf '\r%s\e[K' "$(render_bar $elapsed $total)"
      sleep $TICK
      elapsed=$(( EPOCHSECONDS - start ))
    done
    printf '\r%s\e[K\n' "$(render_bar $total $total)"
  fi
  (( elapsed - total <= GRACE ))
}
```

In `main`, replace the last two lines, `countdown $secs` and `go_to_sleep`, with:

```zsh
  if ! countdown $secs; then
    print -r -- "Time ran out while your Mac was asleep, so it won't go to sleep now."
    return 0
  fi
  go_to_sleep
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: one blank line, then `All tests passed`.

- [ ] **Step 5: Update the README and CLAUDE.md**

`README.md`, troubleshooting table: add after the `The timer stopped by itself` row:

```
| `Time ran out while your Mac was asleep, so it won't go to sleep now.` | The Mac went to sleep on its own (for example, you closed the lid) before the timer ended. sleeptimer doesn't mute it or put it back to sleep when you wake it. Nothing to fix. |
```

`README.md`, developer env-variable table: add after the `SLEEPTIMER_TICK` row:

```
| `SLEEPTIMER_GRACE` | Seconds late the timer may end before it assumes the Mac was asleep and skips sleeping | `60` |
```

`CLAUDE.md`, "Test hooks" table: add after the `SLEEPTIMER_TICK` row:

```
| `SLEEPTIMER_GRACE` | Seconds late before `countdown` returns 1 (Mac slept through the deadline) |
```

- [ ] **Step 6: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh README.md CLAUDE.md
git commit -m "fix: don't mute and sleep on wake when the Mac slept through the timer

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Closing the Terminal window mid-countdown stops quietly

**Files:**

- Modify: `sleeptimer`. Add `hangup` right after `cancel`, and change the `trap` line in `main`.
- Modify: `tests/test_sleeptimer.zsh`. Add a block right after the "cancelling restores the terminal" block.
- Modify: `README.md`, `CLAUDE.md`.

**Interfaces:**

- Consumes: `screen_leave` and `cancel` (existing). The fake `pmset` is used via `STUB_SLEEP_DISABLED=1` for the heads-up test.
- Produces:
  - `hangup`: the HUP trap for the timer. It restores the screen with errors ignored, prints nothing and exits 129.
  - `cancel` still handles INT and TERM (exit 130, with the message).

- [ ] **Step 1: Write the failing tests**

Add after the block that ends `rm -f $log` following `assert_eq "cancel never sleeps" …`:

```zsh
# end-to-end: closing the window (HUP) mid-countdown stops quietly, fast, and never sleeps
log=$(mktemp)
rm -f $FAKE_STATE
PATH=$fake_bin:$PATH SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_TUI=1 SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20 zsh $SCRIPT 30s >$log 2>&1 &
pid=$!
sleep 1.5
t0=$EPOCHSECONDS
kill -HUP $pid
wait $pid
assert_eq "hangup exit 129"        "129" "$?"
assert_eq "hangup is quick"        "yes" "$( (( EPOCHSECONDS - t0 <= 2 )) && print yes )"
out=$(<$log)
assert_eq "hangup no message"      "no"  "$([[ $out == *Cancelled* ]] && print yes || print no)"
assert_eq "hangup never sleeps"    "no"  "$([[ $out == *'DRY RUN'* ]] && print yes || print no)"
assert_eq "hangup restores screen" "yes" "$([[ $out == *$'\e[?25h\e[?1049l'* ]] && print yes)"
# ...also while the "Heads up" warning pauses for 3 s, before full screen starts
STUB_SLEEP_DISABLED=1 PATH=$fake_bin:$PATH SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_TUI=1 SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20 zsh $SCRIPT 1s >$log 2>&1 &
pid=$!
sleep 1
kill -HUP $pid
wait $pid
assert_eq "hangup during heads-up exit 129"   "129" "$?"
assert_eq "hangup during heads-up never sleeps" "no" "$([[ $(<$log) == *'DRY RUN'* ]] && print yes || print no)"
rm -f $log
assert_eq "hangup in subshell silent" "" "$(hangup 2>&1)"
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: these four fail.

- `FAIL hangup exit 129` (actual `130`)
- `FAIL hangup no message`
- `FAIL hangup during heads-up exit 129` (actual `130`)
- `FAIL hangup in subshell silent` (`command not found: hangup`)

The other hangup assertions pass already. They pin the parts that must keep working.

- [ ] **Step 3: Implement**

In `sleeptimer`, add right after the `cancel` function:

```zsh
# hangup — the Terminal window was closed: stop without pausing, muting or sleeping. Nobody can read a
# message now, so print none, and ignore errors from a terminal that is already gone.
hangup() {
  (( ZSH_SUBSHELL )) && exit 1  # a $(...) helper caught the signal; the main shell handles it
  { screen_leave } 2>/dev/null
  exit 129
}
```

In `main`, replace `trap cancel INT TERM HUP` with:

```zsh
  trap cancel INT TERM
  trap hangup HUP
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: one blank line, then `All tests passed`.

- [ ] **Step 5: Update the README and CLAUDE.md**

`README.md`, "Changed your mind? Cancel it": replace

```
You'll see `Cancelled — not sleeping.`, and nothing gets paused, muted or put to sleep.
```

with

```
You'll see `Cancelled — not sleeping.`, and nothing gets paused, muted or put to sleep.

Closing the Terminal window cancels the timer too, the same way.
```

`CLAUDE.md`, the "Display modes" bullet that starts `` `cancel` (trapped on INT/TERM/HUP)``: replace it with:

```
  - `cancel` (trapped on INT/TERM) must call `screen_leave` before exiting 130. `hangup` (HUP, i.e. the window was closed) restores the screen with errors ignored, prints nothing and exits 129.
```

- [ ] **Step 6: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh README.md CLAUDE.md
git commit -m "feat: closing the window stops the timer quietly (exit 129)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `--yolo` flag and a checked, clean YOLO stop

**Files:**

- Modify: `sleeptimer`.
  - Replace `wait_sleep_disabled` with `wait_sleep_state`.
  - Update the `yolo_guard` comment.
  - Change `yolo_cmd` and `yolo_stop`, plus the `yolo` case and `usage` in `main`.
- Modify: `tests/test_sleeptimer.zsh`. Change the fake `caffeinate`, the fake `pmset` (for `STUB_PMSET_STUCK`) and `yolo_run`, and add assertions.
- Modify: `README.md`, `CLAUDE.md`.

**Interfaces:**

- Consumes: `sleep_disabled`, `yolo_guard <pid> <prev>` (signature unchanged), `yolo_run` and `run` (test helpers).
- Produces:
  - `wait_sleep_state <0|1>`: returns 0 once `sleep_disabled` prints that value, and 1 after about 3 seconds.
  - `YOLO_CAFF`: the pid of YOLO's `caffeinate`, or empty in a dry run.
  - The root guard now watches `$YOLO_CAFF` instead of `$$`.
  - `yolo_stop` exits 0 after a verified restore, or 1 with `Sleep is still turned off. To turn it back on: sleeptimer yolo off`.
  - `main` accepts `--yolo` as another spelling of `yolo`.
  - Fakes: `caffeinate` stays alive while the pid after `-w` lives. It logs `caffeinate pid <its pid>`, and `caffeinate stopped` when it gets TERM. `STUB_PMSET_STUCK=1` makes the fake `pmset` ignore `disablesleep 0`.

Why the guard watches caffeinate: the guard runs as root, so the script can't signal it. Watching `caffeinate` gives `yolo_stop` a handle it is allowed to kill. Killing it makes the guard restore sleep right away, and `yolo_stop` can then wait for that and confirm it. The guarantee after `kill -9` and a closed window still holds: `caffeinate -w $$` exits as soon as the script dies, and the guard follows within a second.

- [ ] **Step 1: Update the fakes**

In `tests/test_sleeptimer.zsh`, replace the fake `caffeinate` line:

```zsh
print -l '#!/bin/sh' 'echo "caffeinate $*" >> "$FAKE_LOG"' > $fake_bin/caffeinate
```

with (args are `-dims -w PID`, so the pid is `$3`):

```zsh
print -l '#!/bin/sh' \
  'echo "caffeinate $*" >> "$FAKE_LOG"; echo "caffeinate pid $$" >> "$FAKE_LOG"' \
  "trap 'echo \"caffeinate stopped\" >> \"\$FAKE_LOG\"; exit 0' TERM" \
  'while kill -0 "$3" 2>/dev/null; do sleep 0.2; done' > $fake_bin/caffeinate
```

In the fake `pmset`, replace:

```zsh
  '[ "$2" = "disablesleep" ] && echo "$3" > "$FAKE_STATE"' \
```

with:

```zsh
  'if [ "$2" = "disablesleep" ] && ! { [ "$3" = 0 ] && [ "$STUB_PMSET_STUCK" = 1 ]; }; then echo "$3" > "$FAKE_STATE"; fi' \
```

Then add `STUB_PMSET_STUCK=0` to the `export STUB_OSASCRIPT_RC=0 …` line. Also add one comment line above the fakes: `# STUB_PMSET_STUCK=1 makes the fake pmset ignore "disablesleep 0" (a guard that never restores).`

- [ ] **Step 2: Run the suite: the fake changes alone must stay green**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: one blank line, then `All tests passed`. The long-running fake caffeinate exits when the script dies, so the old code still behaves the same.

- [ ] **Step 3: Write the failing tests**

In `yolo_run`, replace the lines

```zsh
  wait $pid
  yrc=$?
  sleep 2.5
```

with

```zsh
  wait $pid
  yrc=$?
  ystate=$(cat $FAKE_STATE 2>/dev/null)  # sleep setting at the moment the script exited
  sleep 2.5
```

and change its header comment to end with `sets yrc, ystate, yout, ylog`.

Right after `assert_eq "yolo stop message" …` (the first `yolo_run TERM` block), add:

```zsh
assert_eq "yolo stop waits for sleep to be back" "0" "$ystate"
assert_eq "yolo stop ends caffeinate" "yes" "$([[ $ylog == *'caffeinate stopped'* ]] && print yes)"
cpid=${${(M)${(f)ylog}:#caffeinate pid *}#caffeinate pid }
assert_eq "yolo guard watches caffeinate" "yes" "$([[ -n $cpid && $ylog == *"while kill -0 $cpid "* ]] && print yes)"
```

Right after `assert_eq "yolo kill -9 still restores" …`, add:

```zsh
yolo_run TERM STUB_PMSET_STUCK=1
assert_eq "yolo stuck: tells how to fix" "yes" \
  "$([[ $yout == *'Sleep is still turned off'*'sleeptimer yolo off'* ]] && print yes)"
assert_eq "yolo stuck: exit 1" "1" "$yrc"
rm -f $FAKE_STATE
```

Right after `assert_eq "yolo bad arg exit 2" …`, add:

```zsh
assert_eq "--yolo off works" "yes" "$([[ $(STUB_SLEEP_DISABLED=1 run --yolo off 2>&1) == *'DRY RUN'* ]] && print yes)"
assert_eq "help mentions --yolo" "yes" "$([[ $(run -h) == *'sleeptimer --yolo'* ]] && print yes)"
```

- [ ] **Step 4: Run the tests and confirm they fail**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: these seven fail.

- `FAIL yolo stop waits for sleep to be back` (actual `1`)
- `FAIL yolo stop ends caffeinate`
- `FAIL yolo guard watches caffeinate` (the guard watches the script's pid)
- `FAIL yolo stuck: tells how to fix`
- `FAIL yolo stuck: exit 1` (actual `0`)
- `FAIL --yolo off works`
- `FAIL help mentions --yolo`

- [ ] **Step 5: Implement**

In `sleeptimer`, replace `wait_sleep_disabled` (comment included) with:

```zsh
# wait_sleep_state <0|1> — poll up to ~3 s until sleep_disabled reports <0|1>; false if it never does.
wait_sleep_state() {
  repeat 15; do
    (( $(sleep_disabled) == $1 )) && return 0
    sleep 0.2
  done
  return 1
}
```

Replace the `yolo_guard` comment (keep its body unchanged) with:

```zsh
# yolo_guard <pid> <prev> — the root command YOLO runs: turn sleep off, then put <prev> back once <pid>
# (YOLO's caffeinate, which exits with the script) is gone. It polls instead of trapping, so it still
# restores after kill -9 or a closed window.
# Fixed PATH and detached stdio: root must not run the user's pmset, or die on a closed pipe.
```

In `yolo_cmd`:

- Change the state line to `YOLO_PREV=$(sleep_disabled) YOLO_START=$EPOCHSECONDS YOLO_CAFF=`.
- Replace the whole `else` branch of `if [[ -n $SLEEPTIMER_DRY_RUN ]]` (from `if (( ! YOLO_PREV )); then` through `caffeinate -dims -w $$ >/dev/null 2>&1 &!`) with:

```zsh
    caffeinate -dims -w $$ >/dev/null 2>&1 &!
    YOLO_CAFF=$!
    if (( ! YOLO_PREV )); then
      print -r -- "To stay awake with the lid closed, macOS needs your admin password (used only for: pmset disablesleep)."
      if sudo -v; then
        nohup sudo -n /bin/zsh -f -c "$(yolo_guard $YOLO_CAFF $YOLO_PREV)" >/dev/null 2>&1 &!
        if ! wait_sleep_state 1; then
          lid=0
          print -u2 "Couldn't block lid-close sleep, so closing the lid will still put the Mac to sleep."
        fi
      else
        lid=0
        print -u2 "No admin rights, so closing the lid will still put the Mac to sleep."
      fi
    fi
```

Replace `yolo_stop` (comment included) with:

```zsh
# yolo_stop — leave YOLO mode: stop caffeinate, which makes the root guard put sleep back, and only
# say sleep is back once pmset confirms it.
yolo_stop() {
  (( ZSH_SUBSHELL )) && exit 1  # a $(...) helper caught the signal; the main shell handles it
  [[ -n $YOLO_CAFF ]] && kill $YOLO_CAFF 2>/dev/null
  screen_leave
  print -r -- $'\n'"YOLO off after $(fmt_time $(( EPOCHSECONDS - YOLO_START )))."
  if (( YOLO_PREV )); then
    print -r -- "Sleep was already turned off before YOLO, so it stays off. To turn it on: sleeptimer yolo off"
  elif wait_sleep_state 0; then
    print -r -- "Your Mac can sleep again."
  else
    print -u2 "Sleep is still turned off. To turn it back on: sleeptimer yolo off"
    exit 1
  fi
  exit 0
}
```

In `main`, change `yolo) shift; yolo_cmd "$@"; return ;;` to:

```zsh
    yolo|--yolo) shift; yolo_cmd "$@"; return ;;
```

In `usage`, add this line right after the `sleeptimer yolo off` line:

```
  sleeptimer --yolo          same as sleeptimer yolo
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: one blank line, then `All tests passed`. Then check that no fake guard or fake caffeinate is left running:
`pgrep -fl "$TMPDIR" | grep -E 'caffeinate|disablesleep'`. Expected: no output.

- [ ] **Step 7: Update the README and CLAUDE.md**

`README.md`, YOLO section: replace

```
- Press **Control + C** (or close the Terminal window) and everything goes back
  to normal within a second or two.
```

with

```
- Press **Control + C** (or close the Terminal window) and everything goes back
  to normal within a second or two. After Control + C it tells you
  `Your Mac can sleep again.` once that's really true.
- `sleeptimer --yolo` does the same thing as `sleeptimer yolo`.
```

`README.md`, troubleshooting table: add after the `Time ran out while your Mac was asleep…` row:

```
| `Sleep is still turned off.` after YOLO | Type `sleeptimer yolo off` and enter your Mac password. |
```

`CLAUDE.md`, YOLO paragraph: replace

```
Lid-close sleep needs root: a `nohup sudo -n /bin/zsh -f -c "$(yolo_guard …)"` guard sets `pmset -a disablesleep 1` and polls the script's pid, then writes back the *previous* `SleepDisabled` value (`sleep_disabled`).
```

with

```
Lid-close sleep needs root: a `nohup sudo -n /bin/zsh -f -c "$(yolo_guard …)"` guard sets `pmset -a disablesleep 1` and polls the pid of YOLO's `caffeinate` (`$YOLO_CAFF`, which exits with the script), then writes back the *previous* `SleepDisabled` value (`sleep_disabled`). `yolo_stop` kills that caffeinate and waits with `wait_sleep_state 0` before it claims sleep is back.
```

In the same paragraph, replace `` `wait_sleep_disabled` checks`` with `` `wait_sleep_state 1` checks``. Under "Fake-command env", add:

```
- `STUB_PMSET_STUCK=1`: the fake `pmset` ignores `disablesleep 0` (a guard that never restores). The fake `caffeinate` stays alive while the `-w` pid lives, and logs `caffeinate pid N` and `caffeinate stopped`.
```

In "Conventions", change `` `themes [name]` `` to `` `themes [name]`, `yolo`/`--yolo [off]` ``.

- [ ] **Step 8: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh README.md CLAUDE.md
git commit -m "feat: --yolo flag; YOLO stop kills caffeinate and confirms sleep is back

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: v0.1.0 version and Phase 1 checkboxes

**Files:**

- Modify: `sleeptimer`. Add `VERSION`, a `--version` case in `main` and a usage line.
- Modify: `tests/test_sleeptimer.zsh`, `README.md`, `CLAUDE.md`, `plan.md`.

**Interfaces:**

- Consumes: `main` dispatch and `usage` (existing).
- Produces: `VERSION=0.1.0`. `sleeptimer --version` / `-v` prints `sleeptimer 0.1.0` and exits 0. The later Homebrew cask phases read the version from here.

- [ ] **Step 1: Write the failing test**

Add after `assert_eq "bad option exit 2" …`:

```zsh
assert_eq "version" "sleeptimer 0.1.0" "$(run --version)"
assert_eq "version -v" "sleeptimer 0.1.0" "$(run -v)"
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: `FAIL version` and `FAIL version -v`. Both show an empty actual value, because the `-*` case catches them and the error goes to stderr.

- [ ] **Step 3: Implement**

In `sleeptimer`, add as the first line after the header comment (`# sleeptimer — count down …`):

```zsh
VERSION=0.1.0
```

In `main`'s `case`, add before the `-*)` line:

```zsh
    -v|--version|version) print -r -- "sleeptimer $VERSION"; return 0 ;;
```

In `usage`, add after the `sleeptimer -h` line:

```
  sleeptimer --version       show the version
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `zsh tests/test_sleeptimer.zsh | grep -v '^PASS'`
Expected: one blank line, then `All tests passed`.

- [ ] **Step 5: Docs and plan.md**

`README.md`, after the `**Help:** …` line in Part 2, add:

```

**Version:** `sleeptimer --version`.
```

`CLAUDE.md`, "Conventions", first bullet: change `` `-h`/`--help`/`help` `` to `` `-h`/`--help`/`help`, `-v`/`--version` (prints `VERSION`)``.

`plan.md`: in the "🛠️ Phase 1" section only, change every `- [ ]` to `- [x]`. Change nothing else in `plan.md`.

- [ ] **Step 6: Manual dry-run smoke test (safe)**

```bash
cfg=$(mktemp -d)/config
SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_CONFIG=$cfg SLEEPTIMER_TUI=0 ./sleeptimer 3s
SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_CONFIG=$cfg ./sleeptimer --version
SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_CONFIG=$cfg ./sleeptimer -h | grep -E 'yolo|version'
```

Expected:

- The first command counts down 3 seconds and prints `DRY RUN: pause + mute + sleep`.
- The second prints `sleeptimer 0.1.0`.
- The third prints the `yolo`, `yolo off`, `--yolo` and `--version` help lines.

- [ ] **Step 7: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh README.md CLAUDE.md plan.md
git commit -m "feat: sleeptimer --version (v0.1.0); tick Phase 1 in plan.md

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## After all tasks

- Do the whole-branch review (see the executing skill), then open a PR to `master`.
- For the user to try by hand, never in tests:
  - With Apple Music playing, run `sleeptimer 10s` and allow "Terminal wants to control Music". Music should pause, then the Mac mutes and sleeps.
  - Run `sleeptimer yolo` with `SleepDisabled 0`. Press Ctrl+C: `Your Mac can sleep again.` appears, and `pmset -g | grep SleepDisabled` shows `0`.
  - Close the window at the `How long?` prompt and during a countdown. The Mac must not sleep.
- Tagging `v0.1.0` (`git tag v0.1.0 && git push --tags`) is the user's call after merge.
