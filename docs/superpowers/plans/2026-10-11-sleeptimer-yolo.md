# Sleeptimer YOLO Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `sleeptimer yolo`, the opposite of the timer. It keeps the Mac awake with the screen on, even with the lid closed, until you press Ctrl+C. It then puts the power settings back exactly as it found them. `sleeptimer yolo off` is a manual escape hatch.

**Architecture:** There are two layers:
- **Without the lid:** `caffeinate -dims -w $$` blocks display, idle, disk and system sleep. It needs no admin rights, and macOS drops it automatically when the script's process exits.
- **With the lid closed:** only `pmset -a disablesleep 1` (root) blocks lid-close sleep. A small root *guard* process sets it, then polls the script's pid every second. When the pid is gone it writes back the *previous* value. Because it polls rather than relying on a trap, the restore still happens after Ctrl+C, a closed Terminal window or `kill -9`.

While running, YOLO shows a full-screen "time awake" display built from the existing big-digit renderer.

**Tech Stack:** zsh 5.9, `caffeinate`, `pmset`, `sudo`, `nohup` (all macOS built-ins), and the existing renderer (`render_big`, `fmt_time`, `use_tui`, `term_size`, `screen_enter`/`screen_leave`).

**Spec:** There's no separate spec doc. The user's request, quoted below, and the decisions after it are the spec.

> "make a "sleeptimer yolo" that instead of sleeping will keep the mac awake and screen on, no matter if you close the laptop, and never sleeps, is awake no matter what"

Decisions:
1. **`sleeptimer yolo`** keeps the Mac awake indefinitely, with no duration, until Ctrl+C or the window closing. Then normal sleep comes back.
2. **Screen on:** `caffeinate -d` keeps the display from sleeping or dimming while the lid is open. With the lid closed, the built-in screen turns off physically (macOS hardware behaviour, which software can't change). An external display stays on. The README says this plainly.
3. **Lid closed:** this needs `sudo pmset -a disablesleep 1`, so YOLO explains why and asks for the admin password once (`sudo -v`). If the password is refused or wrong, YOLO still runs with caffeinate only and warns that closing the lid will still sleep.
4. **Restore the previous value, not "on".** `SleepDisabled` may already be `1` before YOLO starts. *This Mac currently has `SleepDisabled 1` set, likely by a keep-awake app.* In that case YOLO skips sudo entirely, because the lid is already blocked, and leaves the setting at `1` afterwards, saying so.
5. **The restore survives everything except a power loss or restart** (Ctrl+C, closing the window, TERM, `kill -9`), within about 1 second. `pmset disablesleep` persists across restarts, so two backstops cover that:
   - `sleeptimer yolo off` turns sleep back on (`sudo pmset -a disablesleep 0`).
   - The normal timer warns before counting down when sleep is off system-wide, because `pmset sleepnow` may then not put the Mac to sleep.
6. **Heat warning** on start: "Don't put it in a bag while this runs. It won't sleep and can get very hot."
7. **Display:**
   - Full screen when stdout is a terminal: a big "time awake" clock (up to 4× scale), centred, plus the lines `YOLO  ·  awake for H:MM:SS`, the lid status, and `Ctrl+C to let your Mac sleep again`.
   - One-line `Awake for MM:SS  (Ctrl+C to stop)` otherwise.
   - Ctrl+C leaves the alternate screen and exits 0, since stopping YOLO is the normal way to end it.
8. **Help:** `sleeptimer -h` lists `yolo` and `yolo off`. An unknown `sleeptimer yolo <x>` exits 2.

## Global Constraints

- The script stays a single self-contained zsh file using macOS built-ins only (installed by copying it).
- Use bare command names (`sudo`, `pmset`, `caffeinate`) so tests can replace them with fakes via `PATH`. The real `sudo` uses its own `secure_path`, which includes `/usr/bin/pmset`.
- **Tests must never run the real `sudo` or change real `pmset` settings.** Every test that can reach them puts `$fake_bin` first on `PATH`.
- The root guard command is built only from integers (`$$` and the 0/1 previous value). Nothing user-typed goes into the `sudo` command line.
- The timer's end-of-timer command stays exactly `osascript -e "set volume with output muted" && pmset sleepnow`.
- Run all tests with: `zsh tests/test_sleeptimer.zsh` (last line `All tests passed`). YOLO's end-to-end tests add about 20 s.

## Review Focus

1. **Window closed or process killed during YOLO.** Expected: sleep comes back to its previous value within about 1 s, and the Mac is never left unable to sleep. Pinned by `yolo kill -9 still restores` (Task 3). The real-sudo path (where `secure_path` and `nohup` are involved) is checked by hand in Task 3 Step 6.
2. **Sleep already disabled before YOLO.** Expected: no password prompt and no change afterwards. Pinned by `yolo already off: …` (Task 3).
3. **Password refused, wrong, or Ctrl+C at the password prompt.** Expected: YOLO still keeps the Mac awake and says the lid will still sleep. Ctrl+C at the prompt exits without having changed anything. Pinned by `yolo no admin: …` (Task 3). The prompt case holds because the trap is installed after `sudo -v`.
4. **Normal timer while sleep is off system-wide** (as on this Mac now). Expected: a warning that it may not sleep, plus the fix. Pinned by `timer warns if sleep off` (Task 1).
5. **Small terminal or resize during YOLO.** Expected: no line wider than the terminal and a one-line fallback below 30×8. Pinned by `yolo frame … fits` / `yolo tiny fallback` (Task 2).

---

## File Structure

| File | Change |
|---|---|
| `sleeptimer` | Add `sleep_disabled`, `yolo_guard`, `draw_frame` (pulled out of `draw_screen`), `render_yolo`, `yolo_cmd`, `yolo_stop` and `yolo_off`. Add the `yolo)` branch in `main`, the timer warning and the help lines |
| `tests/test_sleeptimer.zsh` | Fake `sudo`/`pmset`/`caffeinate` in `$fake_bin`; `run()` uses them; new tests |
| `README.md` | New "YOLO mode" section and a troubleshooting row |
| `CLAUDE.md` | YOLO architecture notes (and commit the file, which is currently untracked) |

zsh notes for the implementer:
- `"${(@f)$(cmd)}"` splits command output into lines and keeps empty ones.
- `&!` starts a background job *disowned*, so the script exiting doesn't take it down.
- A background job in a non-interactive shell starts with SIGINT ignored, so tests stop YOLO with TERM/KILL.
- `$(…)` strips trailing newlines, which is why `render_yolo` returns "at most `rows`" lines.
- The fake-command log variable is `FAKE_LOG`. Don't reuse `STUB_LOG`: the existing `pause_media` test exports and deletes it.

---

### Task 1: Detect disabled sleep; warn in the normal timer; fake power commands for tests

**Files:**
- Modify: `sleeptimer` (add `sleep_disabled` and `yolo_guard` above `# pause_media —`; add the warning in `main` before `countdown $secs`)
- Test: `tests/test_sleeptimer.zsh`

**Interfaces:**
- Produces:
  - `sleep_disabled`: prints `1` if `pmset -g` has a line matching `^\s*SleepDisabled\s+1`, else `0` (also `0` if `pmset` is missing).
  - `yolo_guard <pid> <prev>`: prints the root shell command `trap '' INT HUP TERM; pmset -a disablesleep 1; while kill -0 <pid> 2>/dev/null; do sleep 1; done; pmset -a disablesleep <prev>`.
  - Test fixtures: `$fake_bin` with `pmset`, `sudo` and `caffeinate`, plus env `FAKE_LOG`, `STUB_SLEEP_DISABLED` (0/1) and `STUB_SUDO_RC` (0 = sudo succeeds). `run()` puts `$fake_bin` first on `PATH`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_sleeptimer.zsh`, insert directly before `# parse_duration: bare number uses the default unit…`:

```zsh
# Fake sudo / pmset / caffeinate, so no test ever changes real power settings.
# STUB_SLEEP_DISABLED sets what "pmset -g" reports; STUB_SUDO_RC != 0 makes every sudo call fail;
# every other call is appended to $FAKE_LOG.
fake_bin=$(mktemp -d)
export FAKE_LOG=$fake_bin/calls.log STUB_SLEEP_DISABLED=0 STUB_SUDO_RC=0
print -l '#!/bin/sh' \
  'if [ "$1" = "-g" ]; then printf "System-wide power settings:\n SleepDisabled\t\t%s\nCurrently in use:\n sleep 1\n" "$STUB_SLEEP_DISABLED"; exit 0; fi' \
  'echo "pmset $*" >> "$FAKE_LOG"' > $fake_bin/pmset
print -l '#!/bin/sh' \
  'echo "sudo $*" >> "$FAKE_LOG"' \
  '[ "$STUB_SUDO_RC" = 0 ] || exit "$STUB_SUDO_RC"' \
  '[ "$1" = "-v" ] && exit 0' \
  '[ "$1" = "-n" ] && shift' \
  'exec "$@"' > $fake_bin/sudo
print -l '#!/bin/sh' 'echo "caffeinate $*" >> "$FAKE_LOG"' > $fake_bin/caffeinate
chmod +x $fake_bin/*
```

Change the `run()` helper line to:

```zsh
run() { PATH=$fake_bin:$PATH SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_TUI=0 zsh $SCRIPT "$@" }
```

Directly before the final `rm -rf ${SLEEPTIMER_CONFIG:h:h}` line, add:

```zsh
# sleep_disabled reads pmset -g
assert_eq "sleep_disabled 0" "0" "$( path=($fake_bin $path); STUB_SLEEP_DISABLED=0; sleep_disabled )"
assert_eq "sleep_disabled 1" "1" "$( path=($fake_bin $path); export STUB_SLEEP_DISABLED=1; sleep_disabled )"
assert_eq "sleep_disabled no pmset" "0" "$( path=(/nonexistent); sleep_disabled )"

# yolo_guard: restores the previous value once the pid is gone
assert_eq "yolo_guard command" \
  "trap '' INT HUP TERM; pmset -a disablesleep 1; while kill -0 42 2>/dev/null; do sleep 1; done; pmset -a disablesleep 0" \
  "$(yolo_guard 42 0)"

# normal timer warns when sleep is turned off system-wide
assert_eq "timer warns if sleep off" "yes" "$([[ $(STUB_SLEEP_DISABLED=1 run 1s 2>&1) == *'Heads up: sleep is turned off'*'sleeptimer yolo off'* ]] && print yes)"
assert_eq "timer quiet if sleep on"  "no"  "$([[ $(run 1s 2>&1) == *'Heads up'* ]] && print yes || print no)"

rm -rf $fake_bin
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh 2>/dev/null | grep -E '^FAIL'`
Expected: `FAIL sleep_disabled 0`, `FAIL sleep_disabled 1`, `FAIL sleep_disabled no pmset`, `FAIL yolo_guard command` and `FAIL timer warns if sleep off`. (`timer quiet if sleep on` already passes.)

- [ ] **Step 3: Implement**

In `sleeptimer`, insert directly above `# pause_media — pause whatever is "Now Playing"…`:

```zsh
# sleep_disabled — prints 1 if sleep is turned off system-wide (pmset disablesleep), else 0.
sleep_disabled() {
  local line
  for line in "${(@f)$(pmset -g 2>/dev/null)}"; do
    [[ $line =~ '^[[:space:]]*SleepDisabled[[:space:]]+1' ]] && { print 1; return }
  done
  print 0
}

# yolo_guard <pid> <prev> — the root command YOLO runs: turn sleep off, then put <prev> back
# once <pid> is gone. It polls instead of trapping, so it still restores after kill -9 or a closed window.
yolo_guard() {
  print -r -- "trap '' INT HUP TERM; pmset -a disablesleep 1; while kill -0 $1 2>/dev/null; do sleep 1; done; pmset -a disablesleep $2"
}
```

In `main`, change:

```zsh
  countdown $secs
  go_to_sleep
```

to:

```zsh
  (( $(sleep_disabled) )) && print -u2 "Heads up: sleep is turned off system-wide, so your Mac may stay awake when the timer ends. To fix it: sleeptimer yolo off"
  countdown $secs
  go_to_sleep
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh | tail -1`
Expected: `All tests passed`

- [ ] **Step 5: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: detect system-wide disabled sleep and warn before the timer"
```

---

### Task 2: YOLO full-screen frame

**Files:**
- Modify: `sleeptimer` (split `draw_frame` out of `draw_screen`; add `render_yolo` above `# load_config — read…`)
- Test: `tests/test_sleeptimer.zsh`

**Interfaces:**
- Consumes: `fmt_time`, `big_width`, `render_big`, `C_ACCENT`, `C_DIM`, `C_RESET` (existing).
- Produces:
  - `draw_frame <frame>`: prints `\e[H`, the frame with each `\n` replaced by `\e[K\n`, then `\e[J`.
  - `draw_screen` keeps the same contract, now built on `draw_frame`.
  - `render_yolo <awake-secs> <cols> <rows> <lid 0|1>`: at most `rows` lines, none wider than `cols`, vertically centred (starts with blank lines). Below 30×8 it prints `awake <time>` cut to `cols`.

- [ ] **Step 1: Write the failing tests**

Insert directly before the `# normal timer warns when sleep is turned off system-wide` block:

```zsh
# render_yolo: big "time awake", lid status, centered, never wider than the terminal
yolo_ok() {  # yolo_ok <cols> <rows> — prints "<lines<=rows> <widest<=cols>" as 1/0
  local out=$(render_yolo 65 $1 $2 1) l w=0
  for l in "${(@f)out}"; do (( $#l > w )) && w=$#l; done
  print "$(( ${#${(@f)out}} <= $2 )) $(( w <= $1 ))"
}
assert_eq "yolo frame 60x20 fits"  "1 1" "$(yolo_ok 60 20)"
assert_eq "yolo frame 200x50 fits" "1 1" "$(yolo_ok 200 50)"
assert_eq "yolo frame 30x8 fits"   "1 1" "$(yolo_ok 30 8)"
yframe=$(render_yolo 65 60 20 1)
assert_eq "yolo shows time awake" "yes" "$([[ $yframe == *'YOLO  ·  awake for 01:05'* ]] && print yes)"
assert_eq "yolo shows big clock"  "yes" "$([[ $yframe == *'######  ######'* ]] && print yes)"
assert_eq "yolo lid blocked text" "yes" "$([[ $yframe == *"Closing the lid won't put it to sleep"* ]] && print yes)"
assert_eq "yolo lid open text"    "yes" \
  "$([[ $(render_yolo 65 60 20 0) == *'Closing the lid WILL still put it to sleep'* ]] && print yes)"
assert_eq "yolo centered" "yes" "$([[ $yframe == $'\n'* ]] && print yes)"
assert_eq "yolo tiny fallback" "awake 01:05" "$(render_yolo 65 20 5 1)"
```

(The existing `draw_screen real newlines` / `erases lines` / `no literal escapes` tests guard the `draw_frame` refactor.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh 2>/dev/null | grep -E '^FAIL yolo'`
Expected: FAIL for `yolo frame 60x20 fits`, `yolo frame 200x50 fits`, `yolo frame 30x8 fits`, `yolo shows time awake`, `yolo shows big clock`, `yolo lid blocked text`, `yolo lid open text` and `yolo tiny fallback`. (`yolo centered` may also fail.)

- [ ] **Step 3: Implement**

Replace the whole `draw_screen` function (comment included) with:

```zsh
# draw_frame <frame> — paint a full-screen frame in place, clearing what is left of the previous one.
draw_frame() {
  local nl=$'\e[K\n'  # a $'...' replacement inside "${//}" would stay literal
  printf '\e[H%s\e[J' "${1//$'\n'/$nl}"
}

# draw_screen <elapsed> <total> <end-epoch> — redraw the countdown frame in place.
draw_screen() {
  local -a size=($(term_size))
  draw_frame "$(render_screen $1 $2 $size[1] $size[2] $3 $EPOCHSECONDS)"
}
```

Insert directly above `# load_config — read unit/theme/last…`:

```zsh
# render_yolo <awake-secs> <cols> <rows> <lid-blocked 0|1> — YOLO frame: big "time awake", centered.
# At most <rows> lines, none wider than <cols>. Below 30x8 it falls back to one short line.
render_yolo() {
  local secs=$1 cols=$2 rows=$3 lid=$4
  local clock=$(fmt_time $secs)
  if (( cols < 30 || rows < 8 )); then
    local short="awake $clock"
    print -rn -- ${short[1,cols]}
    return
  fi
  local bw=$(big_width $clock) scale=0 s line i
  local -a info=(
    "YOLO  ·  awake for $clock"
    "${${(M)lid:#1}:+Closing the lid won't put it to sleep}${${lid:#1}:+Closing the lid WILL still put it to sleep}"
    "Ctrl+C to let your Mac sleep again"
  ) tint=("$C_ACCENT" "" "$C_DIM") lines=()
  # Biggest clock that fits: 5s rows + 1 gap + 3 info lines.
  for s in 4 3 2 1; do
    (( bw * 2 * s <= cols - 4 && 5 * s + 4 <= rows )) && { scale=$s; break }
  done
  local height=$(( scale ? 5 * scale + 4 : 3 ))
  repeat $(( (rows - height) / 2 )) lines+=("")
  if (( scale )); then
    local pad=${(l:$(( (cols - bw * 2 * scale) / 2 )):: :)}
    for line in "${(@f)$(render_big $clock $scale)}"; do lines+=("$pad$C_ACCENT$line$C_RESET"); done
    lines+=("")
  fi
  for i in {1..$#info}; do
    line=${info[i][1,cols]}
    lines+=("${(l:$(( (cols - $#line) / 2 )):: :)}$tint[i]$line${tint[i]:+$C_RESET}")
  done
  print -rn -- "${(pj:\n:)lines}"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh | tail -1`
Expected: `All tests passed`

- [ ] **Step 5: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: full-screen YOLO frame showing time awake and lid status"
```

---

### Task 3: `sleeptimer yolo` and `sleeptimer yolo off`

**Files:**
- Modify: `sleeptimer` (add `yolo_cmd`, `yolo_stop` and `yolo_off` above `usage()`; add help lines; add the `yolo)` branch in `main`)
- Test: `tests/test_sleeptimer.zsh`

**Interfaces:**
- Consumes: `sleep_disabled`, `yolo_guard`, the `$fake_bin` fixtures (Task 1); `draw_frame`, `render_yolo` (Task 2); `use_tui`, `term_size`, `screen_enter`, `screen_leave`, `fmt_time`, `TICK`, `IN_TUI` (existing).
- Produces:
  - `yolo_cmd [off]`: runs until a signal, then exits 0 via `yolo_stop`. `off` → `yolo_off`. Anything else → message on stderr, return 2.
  - `yolo_off`: returns 0 if sleep is already on or turned back on, and 1 if `sudo` fails.
  - Globals `YOLO_PREV` (0/1) and `YOLO_START` (epoch).

- [ ] **Step 1: Write the failing tests**

Insert directly before the `# normal timer warns when sleep is turned off system-wide` block:

```zsh
# end-to-end: yolo turns sleep off, keeps the Mac awake, and puts everything back however it ends
yolo_run() {  # yolo_run <signal> [env...] — run "sleeptimer yolo" ~1.5s, stop it, let the guard settle; sets yrc, yout, ylog
  local out=$(mktemp)
  : > $FAKE_LOG
  env PATH=$fake_bin:$PATH SLEEPTIMER_TUI=0 SLEEPTIMER_TICK=0.2 "${@:2}" zsh $SCRIPT yolo >$out 2>&1 &
  local pid=$!
  sleep 1.5
  kill -$1 $pid
  wait $pid
  yrc=$?
  sleep 2.5
  yout=$(<$out) ylog=$(<$FAKE_LOG)
  rm -f $out
}
yolo_run TERM
assert_eq "yolo exit 0"            "0"   "$yrc"
assert_eq "yolo asks for admin"    "yes" "$([[ $ylog == *'sudo -v'* ]] && print yes)"
assert_eq "yolo disables sleep"    "yes" "$([[ $ylog == *'pmset -a disablesleep 1'* ]] && print yes)"
assert_eq "yolo restores sleep"    "yes" "$([[ $ylog == *'disablesleep 1'*'pmset -a disablesleep 0'* ]] && print yes)"
assert_eq "yolo caffeinates"       "yes" "$([[ $ylog == *'caffeinate -dims -w '[0-9]* ]] && print yes)"
assert_eq "yolo warns about heat"  "yes" "$([[ $yout == *"Don't put it in a bag"* ]] && print yes)"
assert_eq "yolo shows time awake"  "yes" "$([[ $yout == *'Awake for 00:0'* ]] && print yes)"
assert_eq "yolo stop message"      "yes" "$([[ $yout == *'YOLO off after'*'Your Mac can sleep again.'* ]] && print yes)"

yolo_run KILL
assert_eq "yolo kill -9 still restores" "yes" "$([[ $ylog == *'disablesleep 1'*'pmset -a disablesleep 0'* ]] && print yes)"

yolo_run TERM STUB_SLEEP_DISABLED=1
assert_eq "yolo already off: no sudo"     "no"  "$([[ $ylog == *sudo* ]] && print yes || print no)"
assert_eq "yolo already off: no pmset"    "no"  "$([[ $ylog == *disablesleep* ]] && print yes || print no)"
assert_eq "yolo already off: stays off"   "yes" "$([[ $yout == *'already turned off before YOLO, so it stays off'* ]] && print yes)"

yolo_run TERM STUB_SUDO_RC=1
assert_eq "yolo no admin: no pmset"       "no"  "$([[ $ylog == *disablesleep* ]] && print yes || print no)"
assert_eq "yolo no admin: lid warning"    "yes" "$([[ $yout == *'closing the lid will still put the Mac to sleep'* ]] && print yes)"
assert_eq "yolo no admin: still awake"    "yes" "$([[ $ylog == *'caffeinate -dims'* ]] && print yes)"

yolo_run TERM SLEEPTIMER_TUI=1 SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20
assert_eq "yolo tui enters alt screen"    "yes" "$([[ $yout == *$'\e[?1049h'*'awake for'* ]] && print yes)"
assert_eq "yolo tui restores terminal"    "yes" "$([[ $yout == *$'\e[?25h\e[?1049l'*'YOLO off'* ]] && print yes)"

assert_eq "yolo bad arg exit 2" "2" "$(run yolo nope >/dev/null 2>&1; print $?)"

# yolo off: turns sleep back on only when it is off
: > $FAKE_LOG
assert_eq "yolo off when on"  "yes" "$([[ $(run yolo off) == *'already on'* ]] && print yes)"
assert_eq "yolo off no sudo"  ""    "$(<$FAKE_LOG)"
assert_eq "yolo off when off" "yes" "$([[ $(STUB_SLEEP_DISABLED=1 run yolo off) == *'Sleep is back on.'* ]] && print yes)"
assert_eq "yolo off runs pmset" "yes" "$( grep -qx 'sudo pmset -a disablesleep 0' $FAKE_LOG && print yes )"
assert_eq "yolo off sudo fails" "1" "$(STUB_SLEEP_DISABLED=1 STUB_SUDO_RC=1 run yolo off >/dev/null 2>&1; print $?)"
assert_eq "help mentions yolo"  "yes" "$([[ $(run -h) == *'sleeptimer yolo off'* ]] && print yes)"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh </dev/null 2>/dev/null | grep -E '^FAIL'`
Expected: FAIL for most `yolo …` end-to-end tests, `yolo off …` and `help mentions yolo`. Today `yolo` is parsed as a bad duration and exits 1 immediately. This takes about 20 s because of the sleeps in `yolo_run`.

- [ ] **Step 3: Implement**

Insert directly above `usage() {`:

```zsh
# yolo_cmd [off] — keep the Mac awake (lid closed too) until Ctrl+C; "off" turns sleep back on for good.
yolo_cmd() {
  case $1 in
    '') ;;
    off) yolo_off; return ;;
    *) print -u2 "Unknown: sleeptimer yolo $1 (try: sleeptimer yolo, or sleeptimer yolo off)"; return 2 ;;
  esac
  local lid=1
  YOLO_PREV=$(sleep_disabled)
  print -r -- "YOLO mode: your Mac stays awake and the screen stays on until you press Ctrl+C."
  print -r -- "Don't put it in a bag while this runs. It won't sleep and can get very hot."
  if (( ! YOLO_PREV )); then
    print -r -- "To stay awake with the lid closed, macOS needs your admin password (used only for: pmset disablesleep)."
    if sudo -v; then
      nohup sudo -n zsh -c "$(yolo_guard $$ $YOLO_PREV)" >/dev/null 2>&1 &!
    else
      lid=0
      print -u2 "No admin rights, so closing the lid will still put the Mac to sleep."
    fi
  fi
  caffeinate -dims -w $$ >/dev/null 2>&1 &!
  YOLO_START=$EPOCHSECONDS
  trap yolo_stop INT TERM HUP
  use_tui && screen_enter
  local -a size
  while true; do
    if (( IN_TUI )); then
      size=($(term_size))
      draw_frame "$(render_yolo $(( EPOCHSECONDS - YOLO_START )) $size[1] $size[2] $lid)"
    else
      printf '\rAwake for %s  (Ctrl+C to stop)\e[K' "$(fmt_time $(( EPOCHSECONDS - YOLO_START )))"
    fi
    sleep $TICK
  done
}

# yolo_stop — leave YOLO mode; the root guard and caffeinate notice the exit and undo themselves.
yolo_stop() {
  screen_leave
  print -r -- $'\n'"YOLO off after $(fmt_time $(( EPOCHSECONDS - YOLO_START )))."
  if (( YOLO_PREV )); then
    print -r -- "Sleep was already turned off before YOLO, so it stays off. To turn it on: sleeptimer yolo off"
  else
    print -r -- "Your Mac can sleep again."
  fi
  exit 0
}

# yolo_off — turn system sleep back on (pmset disablesleep 0), e.g. after a crash or restart during YOLO.
yolo_off() {
  if (( ! $(sleep_disabled) )); then
    print "Sleep is already on. Nothing to do."
    return 0
  fi
  print -r -- "Turning sleep back on needs your admin password (runs: pmset -a disablesleep 0)."
  sudo pmset -a disablesleep 0 || { print -u2 "Couldn't turn sleep back on."; return 1 }
  print "Sleep is back on."
}
```

In `usage()`, replace the line `  sleeptimer -h              show this help` with:

```
  sleeptimer yolo            keep the Mac awake, even with the lid closed, until Ctrl+C
  sleeptimer yolo off        turn sleep back on if it got stuck off
  sleeptimer -h              show this help
```

In `main`, after the `themes) shift; themes_cmd "$@"; return ;;` line, add:

```zsh
    yolo) shift; yolo_cmd "$@"; return ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh | tail -1`
Expected: `All tests passed`
Then run: `pgrep -fl disablesleep || echo none` → `none` (no guard is left behind by the tests).

- [ ] **Step 5: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: sleeptimer yolo keeps the Mac awake with the lid closed until Ctrl+C"
```

- [ ] **Step 6: Manual check with the real sudo (the human runs it; it needs the admin password)**

This is the one path the fakes can't cover: real `sudo`'s `secure_path`, `nohup`, and root polling a user pid. Ask the human to run, in a Terminal on a Mac where `pmset -g | grep SleepDisabled` shows `0`:
1. `./sleeptimer yolo`, then enter the password. In a second window, `pmset -g | grep SleepDisabled` → `1`.
2. Close the first Terminal window. Within about 2 s, `pmset -g | grep SleepDisabled` → `0`, and `pgrep -fl disablesleep` → nothing.

On a Mac where it already shows `1` (like this one), YOLO must not ask for a password, and the value must still be `1` afterwards. Record the outcome in the ledger. If the human can't run it, record that as a ruling.

---

### Task 4: README and CLAUDE.md

**Files:**
- Modify: `README.md`
- Modify (and add to git, since it's currently untracked): `CLAUDE.md`

- [ ] **Step 1: README — add a section** after the "Change the look (themes)" section (before `## When you wake the Mac up`):

````markdown
## YOLO mode: keep the Mac awake instead

Want the opposite? **`sleeptimer yolo`** keeps your Mac awake with the screen
on until you press **Control + C**, even when you close the lid.

```
sleeptimer yolo
```

- It asks for your **Mac password** once. macOS needs it to stop the Mac from
  sleeping when the lid is closed. If you skip it, the Mac still stays awake
  while the lid is open.
- With the lid closed, the laptop's own screen turns off (that's how the
  hardware works), but the Mac keeps running and an external screen stays on.
- **Don't put the Mac in a bag while YOLO is on.** It won't sleep and can get
  very hot.
- Press **Control + C** (or close the Terminal window) and everything goes back
  to normal within a second or two.

If your Mac ever refuses to sleep afterwards (for example, it restarted while
YOLO was on), type **`sleeptimer yolo off`**.

---
````

- [ ] **Step 2: README — troubleshooting row.** Add to the "Something not working?" table:

```markdown
| `Heads up: sleep is turned off system-wide` | Something (YOLO, or another keep-awake app) switched sleep off, so the timer may not be able to put the Mac to sleep. Type `sleeptimer yolo off` to switch it back on. |
```

- [ ] **Step 3: CLAUDE.md — architecture note.** Under `## Architecture`, add this bullet after the "Display modes" bullet:

```markdown
- **YOLO mode** (`sleeptimer yolo`) is the opposite of the timer. `caffeinate -dims -w $$` blocks normal sleep. Lid-close sleep needs root: a `nohup sudo -n zsh -c "$(yolo_guard …)"` guard sets `pmset -a disablesleep 1` and polls the script's pid, then writes back the *previous* `SleepDisabled` value (`sleep_disabled`). Never replace the polling with a trap, because it must survive `kill -9` and closed windows. Tests use fake `sudo`/`pmset`/`caffeinate` in `$fake_bin` (log: `$FAKE_LOG`) and must never call the real ones.
```

In the "Test hooks" section, after the table, add:

```markdown
Fake-command env for YOLO tests: `STUB_SLEEP_DISABLED` (what `pmset -g` reports) and `STUB_SUDO_RC` (non-zero makes every fake `sudo` fail).
```

- [ ] **Step 4: Verify and commit**

Run: `zsh tests/test_sleeptimer.zsh | tail -1` → `All tests passed`.

```bash
git add README.md CLAUDE.md
git commit -m "docs: document YOLO mode; add CLAUDE.md"
```
