# Sleeptimer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A zsh command `sleeptimer` that asks for a unit (s/m/h) and an amount, shows a brew-style progress bar counting down, then runs `osascript -e "set volume with output muted" && pmset sleepnow`.

**Architecture:** One zsh script (`sleeptimer`) made of small pure functions (`to_seconds`, `fmt_time`, `render_bar`) plus I/O functions (`ask_duration`, `countdown`, `go_to_sleep`, `main`). The script calls `main` only when executed, not when sourced, so a plain-zsh test file can source it and test each function. Env vars (`SLEEPTIMER_DRY_RUN`, `SLEEPTIMER_TICK`, `SLEEPTIMER_BAR_WIDTH`) let tests run without actually muting or sleeping the Mac.

**Tech Stack:** zsh (macOS default, 5.9+), `zsh/datetime` module (`$EPOCHSECONDS`), `osascript`, `pmset`. No test framework; a ~30-line zsh assert helper.

**Spec:** No separate spec doc. The source is the user's request plus their answers to the clarifying questions:
- Run `osascript -e "set volume with output muted" && pmset sleepnow` when the countdown finishes (replaces the hard-coded `sleep 5000`).
- Ask for the unit first (`s`, `m` or `h`), then the amount.
- The bar starts all dashes (`[------]`) and fills with `#` (`[###---]`), like brew. Show the percentage and the time left: `[##########----------]  50%  22:30 left`.
- Ctrl+C cancels cleanly: print a message and do not mute or sleep.
- Script lives in `~/Dev/sleep/sleeptimer`, symlinked into `~/.local/bin` (already on PATH; `~/bin` does not exist and isn't on PATH).

## Global Constraints

- Shell: zsh only (`#!/usr/bin/env zsh`). No bash-isms, no external deps beyond macOS built-ins.
- Final command must be exactly: `osascript -e "set volume with output muted" && pmset sleepnow` (no sudo; `pmset sleepnow` works as a normal user).
- Bar characters: `#` for filled, `-` for empty, wrapped in `[` `]`. Default width 30.
- Units accepted: `s`, `m`, `h` (case-insensitive; a full word like `minutes` is reduced to its first letter).
- Amount: whole number ≥ 1. Anything else re-prompts.
- Ctrl+C at any point → print `Cancelled — not sleeping.`, exit 130, never mute/sleep.
- Project dir is not a git repo yet; Task 1 runs `git init`.

## Review Focus

1. **Bad amount input** (`abc`, `0`, `-5`, `1.5`, empty): should re-prompt, never start a 0-second timer or crash. → tested in Task 1 (`to_seconds`).
2. **Clock drift over long timers** (e.g. 8h): elapsed must come from wall-clock `$EPOCHSECONDS`, not from counting `sleep 1` iterations, or the bar finishes late. → tested in Task 2 (countdown with a 0.3s tick still finishes in ~2s).
3. **Hour-long durations display**: time left ≥ 1h must show `H:MM:SS`, not `150:00`. → tested in Task 1 (`fmt_time 9000`).
4. **Bar reaches exactly 100% and full width** before sleeping, and never overflows if elapsed > total. → tested in Task 1 (`render_bar 99 60`).
5. **Uppercase / word units** (`M`, `Hours`): should be accepted. → tested in Task 2 (`ask_duration` fed `Minutes`).

---

## File Structure

| File | Responsibility |
|---|---|
| `sleeptimer` | The executable script: all functions + `main` guard |
| `tests/test_sleeptimer.zsh` | Sources `sleeptimer`, runs asserts, prints PASS/FAIL, exits non-zero on failure |
| `README.md` | Usage + install (symlink) |

---

### Task 1: Pure functions — `to_seconds`, `fmt_time`, `render_bar`

**Files:**
- Create: `sleeptimer`
- Create: `tests/test_sleeptimer.zsh`

**Interfaces:**
- Produces:
  - `to_seconds <unit> <amount>` → prints integer seconds on stdout; returns 1 (prints nothing) if unit not `s|m|h` (case-insensitive, first letter used) or amount not an integer ≥ 1.
  - `fmt_time <seconds>` → prints `MM:SS` when < 3600, else `H:MM:SS`.
  - `render_bar <elapsed> <total>` → prints `[<#…><-…>] NNN%  <fmt_time left> left` (no newline). Uses `$BAR_WIDTH`. Clamps elapsed to total.
  - Globals: `BAR_WIDTH=${SLEEPTIMER_BAR_WIDTH:-30}`, `TICK=${SLEEPTIMER_TICK:-1}`.
  - Main guard: `[[ $ZSH_EVAL_CONTEXT == toplevel ]] && main "$@"` (sourced context is `toplevel:file`/`cmdarg:file`, so sourcing doesn't run main).

- [ ] **Step 1: Init repo**

```bash
cd ~/Dev/sleep && git init && mkdir -p tests
```

- [ ] **Step 2: Write the failing tests**

`tests/test_sleeptimer.zsh`:
```zsh
#!/usr/bin/env zsh
# Plain-zsh tests for sleeptimer. Run: zsh tests/test_sleeptimer.zsh

SLEEPTIMER_BAR_WIDTH=10
source "${0:A:h}/../sleeptimer"

fails=0
assert_eq() {  # assert_eq <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    print "PASS $1"
  else
    print "FAIL $1\n  expected: [$2]\n  actual:   [$3]"
    (( fails++ ))
  fi
}
assert_fails() {  # assert_fails <name> <cmd...>
  if "${@:2}" >/dev/null 2>&1; then
    print "FAIL $1 (expected non-zero exit)"; (( fails++ ))
  else
    print "PASS $1"
  fi
}

# to_seconds
assert_eq "to_seconds s"        "45"    "$(to_seconds s 45)"
assert_eq "to_seconds m"        "2700"  "$(to_seconds m 45)"
assert_eq "to_seconds h"        "7200"  "$(to_seconds h 2)"
assert_eq "to_seconds upper M"  "60"    "$(to_seconds M 1)"
assert_eq "to_seconds word"     "180"   "$(to_seconds minutes 3)"
assert_fails "to_seconds zero"      to_seconds m 0
assert_fails "to_seconds negative"  to_seconds m -5
assert_fails "to_seconds decimal"   to_seconds m 1.5
assert_fails "to_seconds letters"   to_seconds m abc
assert_fails "to_seconds empty"     to_seconds m ""
assert_fails "to_seconds bad unit"  to_seconds x 5

# fmt_time
assert_eq "fmt_time secs"   "00:05"    "$(fmt_time 5)"
assert_eq "fmt_time mins"   "22:30"    "$(fmt_time 1350)"
assert_eq "fmt_time hours"  "2:30:00"  "$(fmt_time 9000)"
assert_eq "fmt_time zero"   "00:00"    "$(fmt_time 0)"

# render_bar (BAR_WIDTH=10)
assert_eq "bar empty"    "[----------]   0%  01:00 left"  "$(render_bar 0 60)"
assert_eq "bar half"     "[#####-----]  50%  00:30 left"  "$(render_bar 30 60)"
assert_eq "bar full"     "[##########] 100%  00:00 left"  "$(render_bar 60 60)"
assert_eq "bar overflow" "[##########] 100%  00:00 left"  "$(render_bar 99 60)"

print
(( fails == 0 )) && print "All tests passed" || print "$fails test(s) failed"
exit $(( fails > 0 ))
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh`
Expected: error that `sleeptimer` doesn't exist (no such file), then FAILs.

- [ ] **Step 4: Write minimal implementation**

`sleeptimer`:
```zsh
#!/usr/bin/env zsh
# sleeptimer — count down with a progress bar, then mute and put the Mac to sleep.

zmodload zsh/datetime  # provides $EPOCHSECONDS

BAR_WIDTH=${SLEEPTIMER_BAR_WIDTH:-30}
TICK=${SLEEPTIMER_TICK:-1}

# to_seconds <unit> <amount> — prints seconds; returns 1 on invalid input.
to_seconds() {
  local unit=${${(L)1}[1]} amount=$2
  [[ $amount == <1-> ]] || return 1
  case $unit in
    s) print $amount ;;
    m) print $(( amount * 60 )) ;;
    h) print $(( amount * 3600 )) ;;
    *) return 1 ;;
  esac
}

# fmt_time <seconds> — MM:SS, or H:MM:SS for an hour or more.
fmt_time() {
  local s=$1
  if (( s >= 3600 )); then
    printf '%d:%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
  else
    printf '%02d:%02d' $(( s / 60 )) $(( s % 60 ))
  fi
}

# render_bar <elapsed> <total> — e.g. "[#####-----]  50%  00:30 left"
render_bar() {
  local elapsed=$1 total=$2
  (( elapsed > total )) && elapsed=$total
  local pct=$(( elapsed * 100 / total ))
  local filled=$(( elapsed * BAR_WIDTH / total ))
  local bar="${(l:filled::#:)}${(l:$(( BAR_WIDTH - filled ))::-:)}"
  printf '[%s] %3d%%  %s left' "$bar" $pct "$(fmt_time $(( total - elapsed )))"
}

main() {
  :
}

[[ $ZSH_EVAL_CONTEXT == toplevel ]] && main "$@"
```

Then: `chmod +x sleeptimer`

- [ ] **Step 5: Run tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh`
Expected: every line `PASS …`, then `All tests passed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh docs/
git commit -m "feat: add duration parsing, time formatting and progress bar rendering"
```

---

### Task 2: Interactive flow — `ask_duration`, `countdown`, `go_to_sleep`, `main`

**Files:**
- Modify: `sleeptimer` (replace the stub `main() { : }` block; add functions above it)
- Modify: `tests/test_sleeptimer.zsh` (append tests before the final summary block)

**Interfaces:**
- Consumes: `to_seconds`, `fmt_time`, `render_bar`, `TICK` from Task 1.
- Produces:
  - `ask_duration` → prompts on stderr (`Unit? [s/m/h]: `, then `How many minutes? `), reads stdin, re-prompts on bad input, prints total seconds to stdout. Returns 1 on EOF.
  - `countdown <total_seconds>` → redraws `\r<render_bar>\e[K` every `$TICK` seconds using `$EPOCHSECONDS` for elapsed; ends by printing the 100% bar plus a newline.
  - `go_to_sleep` → runs `osascript -e "set volume with output muted" && pmset sleepnow`; if `SLEEPTIMER_DRY_RUN` is non-empty, prints `DRY RUN: mute + sleep` instead.
  - `main` → sets the INT trap, calls `ask_duration`, prints `Sleeping in <fmt_time>. Ctrl+C to cancel.`, then `countdown`, then `go_to_sleep`.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test_sleeptimer.zsh` right before the final `print` / summary lines:
```zsh
# ask_duration: re-prompts on bad unit and bad amount; accepts word units
assert_eq "ask_duration retries" "180" \
  "$(print -l x Minutes abc 0 3 | ask_duration 2>/dev/null)"
assert_eq "ask_duration hours"   "7200" \
  "$(print -l h 2 | ask_duration 2>/dev/null)"
assert_fails "ask_duration EOF" ask_duration </dev/null

# countdown: wall-clock based, so a 0.3s tick still finishes ~on time and ends at 100%
TICK=0.3
t0=$EPOCHSECONDS
out=$(countdown 2)
took=$(( EPOCHSECONDS - t0 ))
assert_eq "countdown ends at 100%" "yes" "$([[ $out == *'100%  00:00 left'* ]] && print yes)"
assert_eq "countdown starts at 0%" "yes" "$([[ $out == *'[----------]   0%'* ]] && print yes)"
assert_eq "countdown duration ok"  "yes" "$( (( took >= 1 && took <= 4 )) && print yes )"
TICK=1

# go_to_sleep dry run never touches the system
assert_eq "go_to_sleep dry run" "DRY RUN: mute + sleep" "$(SLEEPTIMER_DRY_RUN=1 go_to_sleep)"

# end-to-end: executed script with piped input, dry run
e2e=$(print -l s 1 | SLEEPTIMER_DRY_RUN=1 zsh "${0:A:h}/../sleeptimer" 2>/dev/null)
assert_eq "e2e announces" "yes" "$([[ $e2e == *'Sleeping in 00:01'* ]] && print yes)"
assert_eq "e2e dry-runs"  "yes" "$([[ $e2e == *'DRY RUN: mute + sleep'* ]] && print yes)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh`
Expected: Task 1 tests PASS; new ones FAIL with `command not found: ask_duration` / `countdown` / `go_to_sleep`; exit 1.

- [ ] **Step 3: Implement**

In `sleeptimer`, replace:
```zsh
main() {
  :
}
```
with:
```zsh
# ask_duration — prompt for unit then amount; prints total seconds.
ask_duration() {
  local unit amount secs label
  while true; do
    read "unit?Unit? [s/m/h]: " || return 1
    unit=${${(L)unit}[1]}
    case $unit in
      s) label=seconds ;;
      m) label=minutes ;;
      h) label=hours ;;
      *) print -u2 "Please enter s, m or h."; continue ;;
    esac
    break
  done
  while true; do
    read "amount?How many $label? " || return 1
    secs=$(to_seconds $unit $amount) && break
    print -u2 "Please enter a whole number greater than 0."
  done
  print $secs
}

# countdown <total> — redraw the bar until total seconds of wall-clock time pass.
countdown() {
  local total=$1 start=$EPOCHSECONDS elapsed=0
  while (( elapsed < total )); do
    printf '\r%s\e[K' "$(render_bar $elapsed $total)"
    sleep $TICK
    elapsed=$(( EPOCHSECONDS - start ))
  done
  printf '\r%s\e[K\n' "$(render_bar $total $total)"
}

go_to_sleep() {
  if [[ -n $SLEEPTIMER_DRY_RUN ]]; then
    print "DRY RUN: mute + sleep"
    return
  fi
  osascript -e "set volume with output muted" && pmset sleepnow
}

main() {
  trap 'print "\nCancelled — not sleeping."; exit 130' INT
  local secs
  secs=$(ask_duration) || exit 1
  print "Sleeping in $(fmt_time $secs). Ctrl+C to cancel."
  countdown $secs
  go_to_sleep
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh`
Expected: all PASS, `All tests passed`, exit 0 (takes ~3s because of the real countdowns).

- [ ] **Step 5: Manual check of Ctrl+C (cannot be automated reliably)**

Run: `SLEEPTIMER_DRY_RUN=1 ./sleeptimer`, enter `m`, `1`, wait for a few ticks, press Ctrl+C.
Expected: bar shows `[----…]   0%  01:00 left` and fills; Ctrl+C prints `Cancelled — not sleeping.` and returns to the prompt; `echo $?` → `130`; no `DRY RUN` line.

- [ ] **Step 6: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: interactive prompt, live countdown, cancel trap and mute+sleep"
```

---

### Task 3: Install + README

**Files:**
- Create: `README.md`
- Create (symlink): `~/.local/bin/sleeptimer` → `~/Dev/sleep/sleeptimer`

**Interfaces:**
- Consumes: executable `sleeptimer` from Task 2.

- [ ] **Step 1: Write README.md**

```markdown
# sleeptimer

Counts down with a progress bar, then mutes the Mac and puts it to sleep.

    $ sleeptimer
    Unit? [s/m/h]: m
    How many minutes? 45
    Sleeping in 45:00. Ctrl+C to cancel.
    [###############---------------]  50%  22:30 left

Ctrl+C cancels without muting or sleeping.

## Install

    ln -sf ~/Dev/sleep/sleeptimer ~/.local/bin/sleeptimer

## Test

    zsh tests/test_sleeptimer.zsh

Env vars: `SLEEPTIMER_DRY_RUN=1` (print instead of mute/sleep),
`SLEEPTIMER_TICK` (redraw interval, default 1s), `SLEEPTIMER_BAR_WIDTH` (default 30).
```

- [ ] **Step 2: Create symlink**

```bash
mkdir -p ~/.local/bin && ln -sf ~/Dev/sleep/sleeptimer ~/.local/bin/sleeptimer
```

- [ ] **Step 3: Verify it runs from anywhere**

Run: `cd ~ && print -l s 2 | SLEEPTIMER_DRY_RUN=1 sleeptimer`
Expected: `Sleeping in 00:02. Ctrl+C to cancel.`, a bar ending `[##############################] 100%  00:00 left`, then `DRY RUN: mute + sleep`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage and install"
```
