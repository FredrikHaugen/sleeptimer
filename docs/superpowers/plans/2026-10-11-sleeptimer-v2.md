# Sleeptimer v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `sleeptimer` faster and nicer to use. It drops the s/m/h question and remembers your unit. It accepts decimals and inline units, shows the time in seconds, minutes and hours plus the time the Mac will sleep, and draws a full-screen countdown. It also adds `sleeptimer -h` and switchable themes (`sleeptimer themes`).

**Architecture:** Still one zsh script (`sleeptimer`). It's installed by copying a single file, so it must stay one file. It's built from small pure functions (parsing, formatting, frame rendering) that the plain-zsh test file sources and tests directly, plus thin I/O functions (prompt, config file, countdown loop, `main`). Settings (last unit, last duration, theme) live in a tiny `key=value` file. Full-screen mode uses the terminal's alternate screen and redraws a frame every tick. When stdout isn't a terminal it falls back to the old single-line bar, which keeps tests and pipes simple.

**Tech Stack:** zsh 5.9 (macOS default), `zsh/datetime` (`$EPOCHSECONDS`, `strftime`), ANSI escape codes (256-color, alternate screen), `stty size`, `osascript`, `pmset`, optional `media-control`. No test framework: the existing ~20-line assert helper in `tests/test_sleeptimer.zsh`.

**Spec:** There's no separate spec doc. The source is the user's request (quoted) plus the interpretation decisions below. The executor treats this section as the spec.

> "change so that you dont have to select s,m,h to begin with, remember your previous choice, also write out into seconds, minutes, hours, and add some sort of display, say, 3600s is an hour, 60 min, an hour etc, and decimal is okay, say you want 1,25 hours it willset the timer auto to 75 minutes, also add the time it will go to sleep at the end, and fill all available space in the terminal with the progress bar and information, and if you want you can write sleeptimer -h for help, add in a "sleeptimer themes" for different themes of the timer"

Decisions:
1. **No unit question.** There's one prompt: `How long? (minutes): `. A bare number uses the **remembered unit**, which is minutes on first run. An inline unit wins and becomes the new remembered unit: `90s`, `45m`, `1,5h`, `2 hours`, `30 min`, `90 sec`.
2. **Remember previous choice.** The unit *and* the last duration are saved. Pressing Enter at the prompt repeats the last timer: `How long? (minutes; Enter = 45 minutes): `.
3. **Duration as an argument** skips the prompt: `sleeptimer 45`, `sleeptimer 1,25h`, `sleeptimer 2 hours`.
4. **Decimals:** comma or dot, up to 3 decimals, and a leading dot is OK (`.5h`). The result is rounded to the nearest whole second. `1,25h` gives 4500 s, which is 75 minutes.
5. **Unit display:** `4500 seconds = 75 minutes = 1.25 hours`. Values are rounded to 2 decimals with trailing zeros dropped and singular/plural handled. Units that round to 0 are left out (`10 seconds = 0.17 minutes`). It's shown in the start message and on the countdown screen.
6. **Limits:** from 1 second up to **24 hours**. The cap catches "45" meaning 45 *hours* when the remembered unit is h.
7. **Sleep time:** `Goes to sleep at 23:45` uses a 24-hour clock. It says `01:15 tomorrow` when the time falls tomorrow, and a weekday (`Sat 14:00`) when it's further off. It's shown in the start message and on the screen.
8. **Full screen:** uses the terminal's alternate screen with the cursor hidden. The time left is drawn in big block digits, as big as fit, up to 3× scale. The progress bar is full width and takes **all remaining rows**. Below it are three info lines (`50%  ·  22:30 left  ·  sleeps at 23:45`, the unit line, and `Ctrl+C to cancel`). It redraws every tick and re-reads the terminal size each tick, so resizing works. Below 30×8 it shows one short line. When stdout isn't a terminal, it uses the old one-line `[####----]` bar.
9. **Help:** `sleeptimer -h`, `--help` or `help`. An unknown `-x` prints a hint and exits 2.
10. **Themes:** `sleeptimer themes` lists themes with a coloured preview bar, marks the current one with `*`, and asks which to use (number or name; Enter keeps it). `sleeptimer themes <name>` switches directly. There are 5 themes: `night` (default), `classic` (the original `#`/`-`, no colour), `ocean`, `forest`, `sunset`. `NO_COLOR` turns colours off.
11. **Settings file:** `${XDG_CONFIG_HOME:-~/.config}/sleeptimer/config` holds `unit=`, `theme=` and `last=` lines. `SLEEPTIMER_CONFIG` overrides the path (tests use this).
12. Ctrl+C, closing the window (HUP) or TERM restores the terminal, prints `Cancelled — not sleeping.`, exits 130, and never pauses, mutes or sleeps.

## Global Constraints

- Shell: zsh only (`#!/usr/bin/env zsh`), macOS built-ins only. `media-control` stays optional.
- Single file `sleeptimer`. Install is `cp` of that one file (README Step 3), so no extra files may be required at runtime.
- The end-of-timer command must stay exactly `osascript -e "set volume with output muted" && pmset sleepnow`, preceded by `pause_media`.
- Tests must never touch the real `~/.config`, never mute and never sleep. Use `SLEEPTIMER_CONFIG` (temp dir) and `SLEEPTIMER_DRY_RUN=1`.
- Default unit `m`; default theme `night`; max duration `86400` seconds; decimals ≤ 3 places; whole part ≤ 6 digits.
- No full-screen line may be wider than the terminal (a wrapped line scrolls the screen and garbles the redraw).
- Run all tests with: `zsh tests/test_sleeptimer.zsh` (last line `All tests passed`, exit 0).

## Review Focus

1. **Remembered unit surprise.** The user last used hours, then types `45` meaning minutes. Expected: never a 45-hour timer silently. Anything over 24 h is rejected and re-prompted, and the start message spells out `= … hours`. Pinned by `parse over 24h` (Task 1) and `e2e announces` (Task 4).
2. **Malformed decimals** (`1,`, `1.2.3`, `0,0001h`, `0.4s`, `-5`, empty). Expected: a re-prompt, never a 0-second timer or a crash. Pinned in Task 1 (`parse …` fails) and Task 4 (`ask retries`).
3. **Cancel during full-screen mode** (Ctrl+C / closing the window / TERM). Expected: cursor back, alternate screen left, no pause/mute/sleep, exit 130. Pinned by the `cancel …` tests in Task 6.
4. **Small or resized terminal.** Expected: no line wider than the terminal, the frame exactly fills the height, and a tiny terminal gets a one-line fallback. Pinned by the `screen … size` and `screen tiny …` tests in Task 5. The size is re-read every tick in Task 6.
5. **Corrupt or unwritable settings file.** Expected: defaults are used and the timer still runs. Pinned by `config ignores bad values` / `config unwritable ok` (Task 3).

---

## File Structure

| File | Responsibility |
|---|---|
| `sleeptimer` | The executable: all functions plus the `main` guard. Sections in order: globals/tables, duration parsing & formatting, themes & bar, big digits & screen frame, config, prompt, terminal/countdown, sleep actions, CLI (`usage`, `themes_cmd`, `cancel`, `main`) |
| `tests/test_sleeptimer.zsh` | Sources `sleeptimer`, runs asserts, prints PASS/FAIL, exits non-zero on failure |
| `README.md` | Beginner guide; updated for the new prompt, arguments, themes and help |

zsh notes for the implementer (they apply to every task):
- `${(pl:N::$VAR:)}` left-pads with the *value* of `$VAR`. The `p` flag is required when the pad string is a variable.
- `"${(@s:|:)str}"` splits on `|` and **keeps empty fields** (needed for the `classic` theme's empty colour fields).
- `${ARRAY[(Ie)$x]}` returns the index of the exact match, or 0. Use it rather than `$+ASSOC[$x]`, which treats `*` as a wildcard.
- `$(…)` strips trailing newlines. This is why `render_screen` has no blank last line.
- `read "var?prompt"` prints the prompt only when stdin is a terminal, so tests check the prompt text via `duration_prompt` instead.

---

### Task 1: Duration parsing and unit display

**Files:**
- Modify: `sleeptimer` (add tables after `TICK=…` at line 7; add functions after `to_seconds`, which ends at line 19; add `fmt_clock` after `fmt_time`; change line 4's comment)
- Test: `tests/test_sleeptimer.zsh` (insert after the `to_seconds` tests, before `# fmt_time`)

**Interfaces:**
- Produces:
  - Globals `MAX_SECS=86400`, `typeset -A UNIT_SECS=(s 1 m 60 h 3600)`, `typeset -A UNIT_NAME=(s second m minute h hour)`.
  - `parse_duration <text> <default-unit>`: prints `"<seconds> <unit>"` (unit is `s|m|h`), or returns 1 with no output.
  - `fmt_dec <num> <den>`: prints num/den rounded to 2 decimals with trailing zeros dropped (`4500 3600` → `1.25`).
  - `plural <value> <word>`: `1 hour` / `1.25 hours`.
  - `describe_duration <seconds>`: `4500 seconds = 75 minutes = 1.25 hours`.
  - `fmt_clock <epoch> [now-epoch]`: `HH:MM`, `HH:MM tomorrow`, or `Sat HH:MM`.
- `to_seconds` stays for now (Task 4 removes it).

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test_sleeptimer.zsh` directly before the `# fmt_time` line:

```zsh
# parse_duration: bare number uses the default unit; inline unit overrides it
assert_eq "parse bare uses default" "2700 m" "$(parse_duration 45 m)"
assert_eq "parse bare seconds"      "45 s"   "$(parse_duration 45 s)"
assert_eq "parse inline m"          "2700 m" "$(parse_duration 45m s)"
assert_eq "parse inline s"          "90 s"   "$(parse_duration 90s h)"
assert_eq "parse comma decimal"     "4500 h" "$(parse_duration 1,25h m)"
assert_eq "parse dot decimal"       "5400 h" "$(parse_duration 1.5h m)"
assert_eq "parse decimal bare"      "75 m"   "$(parse_duration 1,25 m)"
assert_eq "parse leading dot"       "1800 h" "$(parse_duration .5h m)"
assert_eq "parse word + space"      "7200 h" "$(parse_duration '2 Hours' m)"
assert_eq "parse min word"          "1800 m" "$(parse_duration '30 min' s)"
assert_eq "parse sec word"          "90 s"   "$(parse_duration '90 sec' m)"
assert_eq "parse rounds .5s up"     "1 s"    "$(parse_duration 0.5s m)"
assert_eq "parse 24h ok"            "86400 h" "$(parse_duration 24h m)"
assert_fails "parse zero"           parse_duration 0 m
assert_fails "parse rounds to 0"    parse_duration 0.4s m
assert_fails "parse negative"       parse_duration -5 m
assert_fails "parse letters"        parse_duration abc m
assert_fails "parse empty"          parse_duration "" m
assert_fails "parse trailing comma" parse_duration 1, m
assert_fails "parse two dots"       parse_duration 1.2.3 m
assert_fails "parse 4 decimals"     parse_duration 0,0001h m
assert_fails "parse bad unit word"  parse_duration 5x m
assert_fails "parse over 24h"       parse_duration 25h m
assert_fails "parse 7 digits"       parse_duration 1000000 s

# fmt_dec / describe_duration
assert_eq "fmt_dec whole"     "75"   "$(fmt_dec 4500 60)"
assert_eq "fmt_dec quarter"   "1.25" "$(fmt_dec 4500 3600)"
assert_eq "fmt_dec one zero"  "1.5"  "$(fmt_dec 5400 3600)"
assert_eq "fmt_dec rounds"    "1.67" "$(fmt_dec 100 60)"
assert_eq "describe hour"     "3600 seconds = 60 minutes = 1 hour"      "$(describe_duration 3600)"
assert_eq "describe 1,25h"    "4500 seconds = 75 minutes = 1.25 hours"  "$(describe_duration 4500)"
assert_eq "describe 1 minute" "60 seconds = 1 minute = 0.02 hours"      "$(describe_duration 60)"
assert_eq "describe drops 0"  "10 seconds = 0.17 minutes"               "$(describe_duration 10)"
assert_eq "describe 1 second" "1 second = 0.02 minutes"                 "$(describe_duration 1)"
```

Insert directly after the four `fmt_time` asserts:

```zsh
# fmt_clock (UTC so results don't depend on where the tests run)
assert_eq "clock today"     "01:00"           "$(TZ=UTC fmt_clock 3600 0)"
assert_eq "clock tomorrow"  "01:00 tomorrow"  "$(TZ=UTC fmt_clock 90000 82800)"
assert_eq "clock later"     "Sun 11:20"       "$(TZ=UTC fmt_clock 300000 0)"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh | grep -E '^FAIL (parse|fmt_dec|describe|clock)' | head`
Expected: FAIL lines such as `FAIL parse bare uses default` (the functions don't exist yet; zsh prints `command not found` on stderr).

- [ ] **Step 3: Implement**

In `sleeptimer`, change line 4 to:

```zsh
zmodload zsh/datetime  # provides $EPOCHSECONDS and strftime
```

After `TICK=${SLEEPTIMER_TICK:-1}`, add:

```zsh
MAX_SECS=86400  # 24 hours: guards against "45" meaning 45 hours when the remembered unit is h

typeset -A UNIT_SECS=(s 1 m 60 h 3600)
typeset -A UNIT_NAME=(s second m minute h hour)
```

After the closing `}` of `to_seconds`, add:

```zsh
# parse_duration <text> <default-unit> — prints "<seconds> <unit>"; returns 1 on invalid input.
# Accepts "45", "45m", "1,25h", "1.5 hours", ".5h", "90 sec". Comma or dot, up to 3 decimals.
parse_duration() {
  local text=${(L)1//[[:space:]]/} unit=$2
  [[ $text =~ '^([0-9]{0,6})([.,]([0-9]{1,3}))?([a-z]*)$' ]] || return 1
  local whole=$match[1] frac=$match[3] word=$match[4]
  [[ -n $whole$frac ]] || return 1
  case $word in
    '') ;;
    s|sec|secs|second|seconds) unit=s ;;
    m|min|mins|minute|minutes) unit=m ;;
    h|hr|hrs|hour|hours) unit=h ;;
    *) return 1 ;;
  esac
  [[ $unit == [smh] ]] || return 1
  local milli=$(( 10#${whole:-0} * 1000 + 10#${(r:3::0:)frac} ))
  local secs=$(( (milli * UNIT_SECS[$unit] + 500) / 1000 ))
  (( secs >= 1 && secs <= MAX_SECS )) || return 1
  print "$secs $unit"
}

# fmt_dec <num> <den> — num/den rounded to 2 decimals, trailing zeros dropped: 4500 3600 → 1.25
fmt_dec() {
  local v=$(( ($1 * 200 + $2) / ($2 * 2) )) out
  out=$(( v / 100 )).${(l:2::0:)$(( v % 100 ))}
  out=${out%0}; out=${out%0}; out=${out%.}
  print -r -- $out
}

# plural <value> <word> — "1 hour", "1.25 hours"
plural() {
  [[ $1 == 1 ]] && print -r -- "$1 $2" || print -r -- "$1 ${2}s"
}

# describe_duration <seconds> — "3600 seconds = 60 minutes = 1 hour"; units that round to 0 are left out.
describe_duration() {
  local u v
  local -a parts
  for u in s m h; do
    v=$(fmt_dec $1 $UNIT_SECS[$u])
    [[ $v == 0 ]] || parts+=("$(plural $v $UNIT_NAME[$u])")
  done
  print -r -- ${(j: = :)parts}
}
```

After the closing `}` of `fmt_time`, add:

```zsh
# fmt_clock <epoch> [now] — "23:45" if today, "01:15 tomorrow", otherwise "Sat 14:00".
fmt_clock() {
  local t=$1 now=${2:-$EPOCHSECONDS} day today tomorrow hm
  strftime -s day '%F' $t
  strftime -s today '%F' $now
  strftime -s tomorrow '%F' $(( now + 86400 ))
  strftime -s hm '%H:%M' $t
  if [[ $day == $today ]]; then
    print -r -- $hm
  elif [[ $day == $tomorrow ]]; then
    print -r -- "$hm tomorrow"
  else
    strftime '%a %H:%M' $t
  fi
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh | tail -1`
Expected: `All tests passed`

- [ ] **Step 5: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: parse decimal durations with inline units and describe them in s/min/h"
```

---

### Task 2: Themes and the themed bar

**Files:**
- Modify: `sleeptimer` (locale guard after `zmodload`; theme tables after the `UNIT_NAME` line; `is_theme`, `apply_theme`, `bar_cells` before `render_bar`; replace `render_bar`)
- Test: `tests/test_sleeptimer.zsh`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - Globals `THEME_NAMES=(night classic ocean forest sunset)` (display/number order), `typeset -A THEMES` (name → `fill|empty|fill-color|empty-color|accent-color|description`), `DEFAULT_THEME=night`.
  - `is_theme <name>`: exit 0 if known.
  - `apply_theme <name>`: sets `THEME FILL EMPTY C_FILL C_EMPTY C_ACCENT C_DIM C_RESET`; returns 1 if unknown. All `C_*` are empty for `classic` or when `NO_COLOR` is set.
  - `bar_cells <filled> <empty>`: prints the coloured run, no newline.
  - `render_bar <elapsed> <total> [width]`: as before, but uses theme characters and an optional width (default `$BAR_WIDTH`).

- [ ] **Step 1: Write the failing tests**

In `tests/test_sleeptimer.zsh`, replace the source line `source "${0:A:h}/../sleeptimer"` with:

```zsh
SCRIPT="${0:A:h}/../sleeptimer"
source $SCRIPT
apply_theme classic  # plain "#"/"-" and no color codes, so expected strings stay readable
```

Insert before `# render_bar (BAR_WIDTH=10)`:

```zsh
# themes
assert_eq "theme default is first"  "night" "$DEFAULT_THEME"
assert_fails "apply unknown theme"  apply_theme nope
assert_fails "apply glob theme"     apply_theme '*'
assert_eq "night colors bar" "yes" \
  "$( apply_theme night; [[ $(bar_cells 2 2) == $'\e[38;5;63m██\e[38;5;236m░░\e[0m' ]] && print yes )"
assert_eq "NO_COLOR strips colors" "██░░" "$( NO_COLOR=1 apply_theme night; bar_cells 2 2 )"
assert_eq "every theme applies" "yes" \
  "$( for t in $THEME_NAMES; do apply_theme $t || exit 1; [[ -n $FILL && -n $EMPTY ]] || exit 1; done; print yes )"
assert_eq "C locale counts chars" "5" \
  "$(LC_ALL=C zsh -c "source ${(q)SCRIPT}; NO_COLOR=1 apply_theme night; x=\$(bar_cells 3 2); print \${#x}")"
```

Change the render_bar header comment to `# render_bar (classic theme, BAR_WIDTH=10)` and add after `bar overflow`:

```zsh
assert_eq "bar width arg" "[##--]  50%  00:30 left"       "$(render_bar 30 60 4)"
```

Also change the e2e line `e2e=$(print -l s 1 | SLEEPTIMER_DRY_RUN=1 zsh "${0:A:h}/../sleeptimer" 2>/dev/null)` to use `zsh $SCRIPT` (same behavior, new variable).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh 2>&1 | grep -E '^FAIL|not found' | head`
Expected: `apply_theme: command not found` and FAIL lines for the theme tests and `bar width arg`.

- [ ] **Step 3: Implement**

After the `zmodload` line, add:

```zsh

# Bar and digit characters are multibyte; count widths in characters, not bytes.
[[ ${LC_ALL:-${LC_CTYPE:-$LANG}} == *[Uu][Tt][Ff](-|)8* ]] || LC_ALL=en_US.UTF-8
```

After the `typeset -A UNIT_NAME…` line, add:

```zsh

# Themes: name → "fill|empty|fill color|empty color|accent color|description" (256-color codes).
THEME_NAMES=(night classic ocean forest sunset)
typeset -A THEMES=(
  night   '█|░|63|236|147|Deep blue and lavender'
  classic '#|-||||Plain ASCII, no colors'
  ocean   '█|░|39|24|117|Bright blue on navy'
  forest  '▓|░|34|22|120|Greens'
  sunset  '█|▒|208|52|214|Orange and red'
)
DEFAULT_THEME=night
```

Replace the whole `render_bar` function (comment included) with:

```zsh
# is_theme <name> — true if <name> is a known theme.
is_theme() {
  (( ${THEME_NAMES[(Ie)$1]} ))
}

# apply_theme <name> — sets THEME, FILL, EMPTY and the C_* color escapes; returns 1 for an unknown theme.
apply_theme() {
  is_theme $1 || return 1
  local -a t=("${(@s:|:)THEMES[$1]}")
  THEME=$1 FILL=$t[1] EMPTY=$t[2]
  if [[ -n $NO_COLOR || -z $t[3] ]]; then
    C_FILL= C_EMPTY= C_ACCENT= C_DIM= C_RESET=
  else
    C_FILL=$'\e[38;5;'$t[3]m C_EMPTY=$'\e[38;5;'$t[4]m C_ACCENT=$'\e[38;5;'$t[5]m
    C_DIM=$'\e[2m' C_RESET=$'\e[0m'
  fi
}

# bar_cells <filled> <empty> — a colored run of FILL then EMPTY characters.
bar_cells() {
  print -rn -- "$C_FILL${(pl:$1::$FILL:)}$C_EMPTY${(pl:$2::$EMPTY:)}$C_RESET"
}

# render_bar <elapsed> <total> [width] — e.g. "[#####-----]  50%  00:30 left"
render_bar() {
  local elapsed=$1 total=$2 width=${3:-$BAR_WIDTH}
  (( elapsed > total )) && elapsed=$total
  local pct=$(( elapsed * 100 / total ))
  local filled=$(( elapsed * width / total ))
  printf '[%s] %3d%%  %s left' "$(bar_cells $filled $(( width - filled )))" $pct "$(fmt_time $(( total - elapsed )))"
}
```

In `main`, add `apply_theme $DEFAULT_THEME` as its first line, so the executed script has `FILL`/`EMPTY` set. Task 4 replaces this with the remembered theme.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh | tail -1`
Expected: `All tests passed`

- [ ] **Step 5: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: add color themes for the progress bar"
```

---

### Task 3: Remembered settings (config file)

**Files:**
- Modify: `sleeptimer` (add `CONFIG=` after `MAX_SECS`; add `load_config`/`save_config` after `render_bar`)
- Test: `tests/test_sleeptimer.zsh`

**Interfaces:**
- Consumes: `is_theme`, `DEFAULT_THEME` (Task 2).
- Produces:
  - Global `CONFIG=${SLEEPTIMER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/sleeptimer/config}`.
  - `load_config`: sets `CFG_UNIT` (`s|m|h`, default `m`), `CFG_THEME` (default `$DEFAULT_THEME`), `CFG_LAST` (seconds, default `0`). Always returns 0.
  - `save_config`: writes those three as `unit=…`, `theme=…`, `last=…` lines and creates the directory. Always returns 0.

- [ ] **Step 1: Write the failing tests**

In `tests/test_sleeptimer.zsh`, directly after `SLEEPTIMER_BAR_WIDTH=10`, add:

```zsh
export SLEEPTIMER_CONFIG=$(mktemp -d)/sleeptimer/config  # never touch the real ~/.config
```

Insert before the `ask_duration` tests:

```zsh
# config: defaults, round trip, corrupt values, unwritable path
rm -f $SLEEPTIMER_CONFIG
load_config
assert_eq "config defaults" "m night 0" "$CFG_UNIT $CFG_THEME $CFG_LAST"
CFG_UNIT=h CFG_THEME=ocean CFG_LAST=4500 save_config
load_config
assert_eq "config round trip" "h ocean 4500" "$CFG_UNIT $CFG_THEME $CFG_LAST"
print -l 'unit=zz' 'theme=*' 'last=abc' 'junk line' > $SLEEPTIMER_CONFIG
load_config
assert_eq "config ignores bad values" "m night 0" "$CFG_UNIT $CFG_THEME $CFG_LAST"
assert_eq "config unwritable ok" "0" "$( CONFIG=/nonexistent/dir/config; save_config; print $? )"
rm -f $SLEEPTIMER_CONFIG; load_config
```

Directly before the final `print` (above the `All tests passed` line), add:

```zsh
rm -rf ${SLEEPTIMER_CONFIG:h:h}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh 2>&1 | grep -E '^FAIL config' `
Expected: `FAIL config defaults`, `FAIL config round trip`, `FAIL config ignores bad values`.

- [ ] **Step 3: Implement**

After the `MAX_SECS=…` line, add:

```zsh
CONFIG=${SLEEPTIMER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/sleeptimer/config}
```

After `render_bar`, add:

```zsh
# load_config — read unit/theme/last from $CONFIG into CFG_*; missing or bad values keep the defaults.
load_config() {
  CFG_UNIT=m CFG_THEME=$DEFAULT_THEME CFG_LAST=0
  [[ -r $CONFIG ]] || return 0
  local key value
  while IFS='=' read -r key value; do
    case $key in
      unit)  [[ $value == [smh] ]] && CFG_UNIT=$value ;;
      theme) is_theme $value && CFG_THEME=$value ;;
      last)  [[ $value == <1-> ]] && (( ${#value} <= 10 )) && CFG_LAST=$value ;;
    esac
  done < $CONFIG
  return 0
}

# save_config — write CFG_* to $CONFIG. Never fails: an unwritable config must not stop the timer.
save_config() {
  { mkdir -p ${CONFIG:h} && print -l "unit=$CFG_UNIT" "theme=$CFG_THEME" "last=$CFG_LAST" > $CONFIG } 2>/dev/null
  return 0
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh | tail -1`
Expected: `All tests passed`. Also check that `ls ~/.config/sleeptimer` didn't appear because of the tests: if it didn't exist before, it must still not exist.

- [ ] **Step 5: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: remember unit, last duration and theme in a config file"
```

---

### Task 4: New prompt, arguments, help and `sleeptimer themes`

**Files:**
- Modify: `sleeptimer` (delete `to_seconds`; replace `ask_duration`; add `duration_prompt`, `cancel`, `usage`, `themes_cmd`; replace `main`)
- Test: `tests/test_sleeptimer.zsh` (delete the `to_seconds` and old `ask_duration` tests; replace the old e2e block)

**Interfaces:**
- Consumes: `parse_duration`, `fmt_dec`, `plural`, `describe_duration`, `fmt_clock`, `UNIT_SECS`, `UNIT_NAME` (Task 1); `apply_theme`, `is_theme`, `bar_cells`, `THEMES`, `THEME_NAMES` (Task 2); `load_config`, `save_config`, `CFG_*`, `CONFIG` (Task 3).
- Produces:
  - `duration_prompt`: prints the prompt text without a newline, e.g. `How long? (minutes; Enter = 45 minutes): `.
  - `ask_duration`: reads lines until valid and prints `"<seconds> <unit>"`; returns 1 on EOF.
  - `cancel`: prints `\nCancelled — not sleeping.` and exits 130 (Task 6 adds the terminal restore).
  - `usage`: help text on stdout.
  - `themes_cmd [name]`: returns 0 or 1.
  - `main "$@"`: dispatches `-h|--help|help`, `themes`, unknown `-*` (exit 2), a duration argument, or the prompt.

- [ ] **Step 1: Write the failing tests**

In `tests/test_sleeptimer.zsh`, **delete** the whole `# to_seconds` block (14 asserts) and the whole old `# ask_duration: re-prompts…` block (3 asserts). In place of the old `ask_duration` block, after the config tests, add:

```zsh
# ask_duration: bare number uses remembered unit, inline unit wins, Enter repeats last
CFG_UNIT=m CFG_LAST=0
assert_eq "prompt first run" "How long? (minutes): " "$(duration_prompt)"
assert_eq "ask bare number"     "2700 m" "$(print 45 | ask_duration 2>/dev/null)"
assert_eq "ask inline unit"     "4500 h" "$(print 1,25h | ask_duration 2>/dev/null)"
assert_eq "ask retries"         "90 s"   "$(print -l abc 0 '' 90s | ask_duration 2>/dev/null)"
CFG_UNIT=h CFG_LAST=4500
assert_eq "ask Enter repeats"   "4500 h" "$(print '' | ask_duration 2>/dev/null)"
assert_eq "prompt with last" "How long? (hours; Enter = 1.25 hours): " "$(duration_prompt)"
assert_fails "ask EOF" ask_duration </dev/null
CFG_UNIT=m CFG_LAST=0
```

Replace the old `# end-to-end: executed script with piped input, dry run` block (3 lines) with:

```zsh
# end-to-end: executed script, dry run, compact mode
run() { SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_TUI=0 zsh $SCRIPT "$@" }
rm -f $SLEEPTIMER_CONFIG
e2e=$(print 1s | run 2>/dev/null)
assert_eq "e2e announces"      "yes" "$([[ $e2e == *'Sleeping in 00:01 (1 second = 0.02 minutes).'* ]] && print yes)"
assert_eq "e2e shows sleep at" "yes" "$([[ $e2e == *'Goes to sleep at '[0-9][0-9]:[0-9][0-9]* ]] && print yes)"
assert_eq "e2e dry-runs"       "yes" "$([[ $e2e == *'DRY RUN: pause + mute + sleep'* ]] && print yes)"
assert_eq "e2e remembers unit" "yes" "$( grep -qx 'unit=s' $SLEEPTIMER_CONFIG && grep -qx 'last=1' $SLEEPTIMER_CONFIG && print yes )"
e2e=$(print 1 | run 2>/dev/null)
assert_eq "e2e bare number uses remembered unit" "yes" "$([[ $e2e == *'Sleeping in 00:01'* ]] && print yes)"
e2e=$(run 1s 2>/dev/null </dev/null)
assert_eq "e2e argument skips prompt" "yes" "$([[ $e2e == *'DRY RUN'* ]] && print yes)"
assert_eq "e2e bad argument exit" "1" "$(run banana >/dev/null 2>&1; print $?)"
assert_eq "e2e bad argument hint" "yes" "$([[ $(run banana 2>&1) == *'sleeptimer -h'* ]] && print yes)"

# end-to-end: help and options
assert_eq "help -h"      "yes" "$([[ $(run -h) == *'Usage:'*'sleeptimer themes'* ]] && print yes)"
assert_eq "help --help"  "yes" "$([[ $(run --help) == *'Usage:'* ]] && print yes)"
assert_eq "help exit 0"  "0"   "$(run -h >/dev/null; print $?)"
assert_eq "bad option exit 2" "2" "$(run -x >/dev/null 2>&1; print $?)"

# end-to-end: themes command
assert_eq "themes set"      "yes" "$([[ $(run themes ocean) == 'Theme set to ocean'* ]] && print yes)"
assert_eq "themes saved"    "yes" "$( grep -qx 'theme=ocean' $SLEEPTIMER_CONFIG && print yes )"
listing=$(print '' | run themes)
assert_eq "themes lists all" "yes" \
  "$( for t in $THEME_NAMES; do [[ $listing == *") $t "* ]] || exit; done; print yes )"
assert_eq "themes marks current" "yes" "$([[ $listing == *'* 3) ocean'* ]] && print yes)"
print 2 | run themes >/dev/null
assert_eq "themes pick by number" "yes" "$( grep -qx 'theme=classic' $SLEEPTIMER_CONFIG && print yes )"
assert_eq "themes unknown exit 1" "1" "$(run themes nope >/dev/null 2>&1; print $?)"
assert_eq "themes keeps unit" "yes" "$( grep -qx 'unit=s' $SLEEPTIMER_CONFIG && print yes )"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh 2>&1 | grep -E '^FAIL' | head -20`
Expected: FAIL for `prompt first run`, the `ask …` tests, `e2e announces`, `help -h`, `themes …` and others. (`e2e …` may take a few seconds, because the old script reads `1s` as an invalid unit and then hits EOF.)

- [ ] **Step 3: Implement**

Delete the `to_seconds` function and its comment.

Replace the whole old `ask_duration` function (comment included) with:

```zsh
# duration_prompt — e.g. "How long? (minutes; Enter = 45 minutes): "
duration_prompt() {
  local hint=
  (( CFG_LAST )) && hint="; Enter = $(plural $(fmt_dec $CFG_LAST $UNIT_SECS[$CFG_UNIT]) $UNIT_NAME[$CFG_UNIT])"
  print -rn -- "How long? (${UNIT_NAME[$CFG_UNIT]}s$hint): "
}

# ask_duration — prompt until a valid duration is entered; prints "<seconds> <unit>".
# A bare number uses the remembered unit; Enter alone repeats the last timer.
ask_duration() {
  local input parsed
  while true; do
    read "input?$(duration_prompt)" || return 1
    if [[ -z ${input//[[:space:]]/} ]] && (( CFG_LAST )); then
      print "$CFG_LAST $CFG_UNIT"
      return 0
    fi
    parsed=$(parse_duration "$input" $CFG_UNIT) && { print -r -- $parsed; return 0 }
    print -u2 "Type a number like 45, or add a unit: 90s, 45m, 1,5h."
  done
}
```

Replace the whole old `main` function with the following. Keep the final `[[ $ZSH_EVAL_CONTEXT == toplevel ]] && main "$@"` line as it is.

```zsh
cancel() {
  print "\nCancelled — not sleeping."
  exit 130
}

usage() {
  print -r -- "sleeptimer — count down, then pause media, mute and put the Mac to sleep.

Usage:
  sleeptimer                 ask how long
  sleeptimer <time>          start right away: 45, 90s, 30m, 1,5h, 2 hours
  sleeptimer themes          list the themes and pick one
  sleeptimer themes <name>   switch theme: ${(j:, :)THEME_NAMES}
  sleeptimer -h              show this help

Times:
  A number without a unit uses the unit you used last time (minutes at first).
  Decimals work with a comma or a dot: 1,25h is 75 minutes.
  At the prompt, press Enter to repeat your last timer.

Ctrl+C cancels: nothing is paused, muted or put to sleep.
Settings are saved in ${CONFIG/#$HOME/~}."
}

# themes_cmd [name] — switch to <name>, or list the themes with a preview and ask which one.
themes_cmd() {
  local name=$1 n i mark choice
  if [[ -n $name ]]; then
    is_theme $name || { print -u2 "Unknown theme: $name (choose from: ${(j:, :)THEME_NAMES})"; return 1 }
    CFG_THEME=$name
    save_config
    apply_theme $name
    print -r -- "Theme set to $name  $(bar_cells 10 10)"
    return 0
  fi
  for i in {1..$#THEME_NAMES}; do
    n=$THEME_NAMES[i]
    [[ $n == $CFG_THEME ]] && mark='*' || mark=' '
    printf '%s %d) %-8s %s  %s\n' $mark $i $n \
      "$(apply_theme $n; bar_cells 12 12)" "${THEMES[$n]##*|}"
  done
  read "choice?Pick a theme (number or name; Enter = keep $CFG_THEME): " || return 0
  [[ -z $choice ]] && return 0
  [[ $choice == <1-> ]] && (( choice <= $#THEME_NAMES )) && choice=$THEME_NAMES[choice]
  themes_cmd $choice
}

main() {
  load_config
  apply_theme $CFG_THEME
  case $1 in
    -h|--help|help) usage; return 0 ;;
    themes) shift; themes_cmd "$@"; return ;;
    -*) print -u2 "Unknown option: $1 (try: sleeptimer -h)"; return 2 ;;
  esac
  trap cancel INT TERM HUP
  local parsed secs
  if (( $# )); then
    parsed=$(parse_duration "$*" $CFG_UNIT) || {
      print -u2 "Can't read \"$*\" as a time. Try 45, 90s, 30m or 1,5h (sleeptimer -h for help)."
      return 1
    }
  else
    parsed=$(ask_duration) || { print; return 1 }
  fi
  secs=${parsed% *} CFG_UNIT=${parsed#* } CFG_LAST=${parsed% *}
  save_config
  print -r -- "Sleeping in $(fmt_time $secs) ($(describe_duration $secs))."
  print -r -- "Goes to sleep at $(fmt_clock $(( EPOCHSECONDS + secs ))). Ctrl+C to cancel."
  countdown $secs
  go_to_sleep
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh | tail -1`
Expected: `All tests passed`

Manual smoke test (real terminal, nothing sleeps): `SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_CONFIG=/tmp/st-smoke ./sleeptimer`. Type `1,25`. It should say `Sleeping in 1:15:00 … (4500 seconds = 75 minutes = 1.25 hours)`. Press Ctrl+C to get `Cancelled — not sleeping.`, then `rm /tmp/st-smoke`.

- [ ] **Step 5: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: single prompt with remembered unit, duration arguments, -h and themes command"
```

---

### Task 5: Full-screen frame renderer (pure)

**Files:**
- Modify: `sleeptimer` (add the `GLYPHS` table after `DEFAULT_THEME`; add `big_width`, `render_big`, `render_screen` after `render_bar`)
- Test: `tests/test_sleeptimer.zsh` (insert before the `# countdown` block)

**Interfaces:**
- Consumes: `fmt_time`, `fmt_clock`, `describe_duration` (Task 1); `bar_cells`, `FILL`, `C_ACCENT`, `C_DIM`, `C_RESET` (Task 2).
- Produces:
  - `typeset -A GLYPHS` with keys `0`–`9` and `:`. Each is 5 rows separated by `|`, `#` = lit cell; digits are 3 cells wide, the colon 1.
  - `big_width <text>`: width in cells (glyphs plus one blank cell between them).
  - `render_big <text> <scale>`: `5*scale` lines; each cell is `2*scale` columns of `$FILL` or spaces; no colour.
  - `render_screen <elapsed> <total> <cols> <rows> <end-epoch> <now-epoch>`: prints exactly `<rows>` lines joined by `\n` (no trailing newline), none wider than `<cols>` visible characters. If `cols < 30 || rows < 8`, it prints one line, `"<pct>%  <time> left"`, cut to `cols`.

Layout (rows top to bottom): 1 blank row, then the big clock (`5*scale` rows, centred, accent colour) and 1 blank row if a clock fits. Next come the bar rows (2-space margin, width `cols-4`, as many rows as are left), 1 blank row, and 3 centred info lines. The scale is the largest of 3, 2, 1 where `big_width*2*scale <= cols-4` and at least 2 bar rows remain (`rows - 5*scale - 6 >= 2`). Otherwise there's no big clock.

- [ ] **Step 1: Write the failing tests**

Insert before `# countdown: wall-clock based…`:

```zsh
# render_big / big_width
assert_eq "big_width 22:30"   "17" "$(big_width 22:30)"
assert_eq "big_width 1:15:00" "23" "$(big_width 1:15:00)"
assert_eq "render_big 1:0" \
  "    ##      ######
    ##  ##  ##  ##
    ##      ##  ##
    ##  ##  ##  ##
    ##      ######" \
  "$(render_big 1:0 1 | sed 's/ *$//')"
assert_eq "render_big scale 2 rows" "10" "$(render_big 7 2 | wc -l | tr -d ' ')"

# render_screen: fills the terminal exactly, never wider than it
frame_ok() {  # frame_ok <cols> <rows> — prints "<lines> <widest>"
  local out=$(TZ=UTC render_screen 30 60 $1 $2 3600 0) l w=0
  for l in "${(@f)out}"; do (( $#l > w )) && w=$#l; done
  print "${#${(@f)out}} $w"
}
assert_eq "screen 60x20 size"   "20 58"  "$(frame_ok 60 20)"
assert_eq "screen 200x50 size"  "50 198" "$(frame_ok 200 50)"
assert_eq "screen 30x8 size"    "8 30"   "$(frame_ok 30 8)"
screen=$(TZ=UTC render_screen 30 60 60 20 3600 0)
assert_eq "screen bar spans width" "yes" \
  "$( [[ $screen == *'  '${(l:28::#:)}${(l:28::-:)}* ]] && print yes )"
assert_eq "screen shows sleep time" "yes" "$( [[ $screen == *'sleeps at 01:00'* ]] && print yes )"
assert_eq "screen shows units" "yes" \
  "$( [[ $screen == *'60 seconds = 1 minute = 0.02 hours'* ]] && print yes )"
assert_eq "screen has big clock" "yes" "$( [[ $screen == *'######  ######'* ]] && print yes )"
assert_eq "screen no clock when short" "no" \
  "$( [[ $(TZ=UTC render_screen 30 60 60 10 3600 0) == *'######  ######'* ]] && print yes || print no )"
assert_eq "screen tiny fallback" "50%  00:30 left" "$(render_screen 30 60 20 5 3600 0)"
assert_eq "screen tiny truncates" "50%  00:" "$(render_screen 30 60 8 5 3600 0)"
```

(These run with the `classic` theme, so `#`/`-` and no escape codes. That makes `$#l` the visible width.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh 2>&1 | grep -E '^FAIL (big|render_big|screen)'`
Expected: FAIL for every `big_width`, `render_big` and `screen …` test.

- [ ] **Step 3: Implement**

After `DEFAULT_THEME=night`, add:

```zsh

# Big-digit font: 5 rows per glyph, "#" = lit cell.
typeset -A GLYPHS=(
  0 '###|# #|# #|# #|###'  1 '  #|  #|  #|  #|  #'  2 '###|  #|###|#  |###'
  3 '###|  #|###|  #|###'  4 '# #|# #|###|  #|  #'  5 '###|#  |###|  #|###'
  6 '###|#  |###|# #|###'  7 '###|  #|  #|  #|  #'  8 '###|# #|###|# #|###'
  9 '###|# #|###|  #|###'  : ' |#| |#| '
)
```

After `render_bar`, add:

```zsh
# big_width <text> — width in cells of <text> drawn with GLYPHS (one blank cell between glyphs).
big_width() {
  local c w=-1
  for c in ${(s::)1}; do (( w += ${#${GLYPHS[$c]%%|*}} + 1 )); done
  print $w
}

# render_big <text> <scale> — <text> in big digits: 5*scale lines, each cell 2*scale columns wide.
render_big() {
  local text=$1 scale=$2 r c line
  local on=${(pl:$(( 2 * scale ))::$FILL:)} off=${(l:$(( 2 * scale )):: :)}
  local -a glyph
  for r in {1..5}; do
    line=
    for c in ${(s::)text}; do
      glyph=("${(@s:|:)GLYPHS[$c]}")
      line+="$glyph[r] "
    done
    line=${${line% }// /$off}
    line=${line//\#/$on}
    repeat $scale print -r -- "$line"
  done
}

# render_screen <elapsed> <total> <cols> <rows> <end-epoch> <now> — one full-screen frame.
# Exactly <rows> lines, none wider than <cols>. Below 30x8 it falls back to one short line.
render_screen() {
  local elapsed=$1 total=$2 cols=$3 rows=$4 end=$5 now=$6
  (( elapsed > total )) && elapsed=$total
  local left=$(( total - elapsed )) pct=$(( elapsed * 100 / total ))
  local clock=$(fmt_time $left)
  if (( cols < 30 || rows < 8 )); then
    local short="$pct%  $clock left"
    print -rn -- ${short[1,cols]}
    return
  fi
  local inner=$(( cols - 4 )) bw=$(big_width $clock) scale=0 s line i
  local -a info=(
    "$pct%  ·  $clock left  ·  sleeps at $(fmt_clock $end $now)"
    "$(describe_duration $total)"
    "Ctrl+C to cancel"
  ) tint=("$C_ACCENT" "" "$C_DIM") lines=("")
  # Biggest clock that fits across and leaves at least 2 bar rows: 1 top + 5s + 1 gap + bar + 1 gap + 3 info.
  for s in 3 2 1; do
    (( bw * 2 * s <= inner && rows - 5 * s - 6 >= 2 )) && { scale=$s; break }
  done
  if (( scale )); then
    local pad=${(l:$(( (cols - bw * 2 * scale) / 2 )):: :)}
    for line in "${(@f)$(render_big $clock $scale)}"; do lines+=("$pad$C_ACCENT$line$C_RESET"); done
    lines+=("")
  fi
  local filled=$(( elapsed * inner / total ))
  local bar="  $(bar_cells $filled $(( inner - filled )))"
  repeat $(( rows - $#lines - 4 )) lines+=("$bar")
  lines+=("")
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

Visual check: `zsh -c 'source ./sleeptimer; apply_theme night; render_screen 900 3600 $COLUMNS $LINES $((EPOCHSECONDS+2700)) $EPOCHSECONDS'`. The terminal should fill with a big `45:00`, a coloured bar about 25% full, and the info lines.

- [ ] **Step 5: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: render a full-screen countdown frame with big digits and a full-width bar"
```

---

### Task 6: Full-screen countdown loop and safe cancel

**Files:**
- Modify: `sleeptimer` (add `use_tui`, `term_size`, `screen_enter`, `screen_leave`, `draw_screen` before `countdown`; replace `countdown`; add `screen_leave` to `cancel`)
- Test: `tests/test_sleeptimer.zsh` (update the `# countdown` block; add the TUI, `term_size` and cancel tests)

**Interfaces:**
- Consumes: `render_screen` (Task 5), `render_bar` (Task 2), `cancel`/`main` (Task 4).
- Produces:
  - `use_tui`: exit 0 for full-screen mode. `SLEEPTIMER_TUI=1` or `0` forces it; otherwise it checks `[[ -t 1 ]]`.
  - `term_size`: prints `"<cols> <rows>"`. `SLEEPTIMER_COLS`/`SLEEPTIMER_ROWS` override it; it falls back to `80 24`.
  - `screen_enter` / `screen_leave`: enter/leave the alternate screen and hide/show the cursor. `IN_TUI` tracks the state, so `screen_leave` is a no-op when the screen isn't active.
  - `draw_screen <elapsed> <total> <end-epoch>`.
  - `countdown <total>`: same contract as before, but full-screen when `use_tui`.

- [ ] **Step 1: Write the failing tests**

Replace the existing `# countdown: wall-clock based…` block (from `TICK=0.3` through `TICK=1`) with:

```zsh
# countdown (compact mode): wall-clock based, so a 0.3s tick still finishes ~on time and ends at 100%
TICK=0.3
t0=$EPOCHSECONDS
out=$(SLEEPTIMER_TUI=0 countdown 2)
took=$(( EPOCHSECONDS - t0 ))
assert_eq "countdown ends at 100%" "yes" "$([[ $out == *'100%  00:00 left'* ]] && print yes)"
assert_eq "countdown starts at 0%" "yes" "$([[ $out == *'[----------]   0%'* ]] && print yes)"
assert_eq "countdown duration ok"  "yes" "$( (( took >= 1 && took <= 4 )) && print yes )"

# countdown (full-screen mode): enters and leaves the alternate screen, last frame is 100%
out=$(SLEEPTIMER_TUI=1 SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20 countdown 1)
assert_eq "tui enters alt screen" "yes" "$([[ $out == $'\e[?1049h\e[?25l'* ]] && print yes)"
assert_eq "tui restores terminal" "yes" "$([[ $out == *$'\e[?25h\e[?1049l' ]] && print yes)"
assert_eq "tui final frame 100%"  "yes" "$([[ $out == *'100%  ·  00:00 left'* ]] && print yes)"
TICK=1

# term_size: env override
assert_eq "term_size override" "100 40" "$(SLEEPTIMER_COLS=100 SLEEPTIMER_ROWS=40 term_size)"
```

Directly before the final `rm -rf ${SLEEPTIMER_CONFIG:h:h}` line, add:

```zsh
# end-to-end: cancelling restores the terminal and never sleeps
log=$(mktemp)
SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_TUI=1 SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20 zsh $SCRIPT 30s >$log 2>&1 &
pid=$!
sleep 1.5
kill -TERM $pid
wait $pid
assert_eq "cancel exit 130"         "130" "$?"
out=$(<$log)
assert_eq "cancel restores screen"  "yes" "$([[ $out == *$'\e[?25h\e[?1049l'* ]] && print yes)"
assert_eq "cancel message"          "yes" "$([[ $out == *'Cancelled — not sleeping.'* ]] && print yes)"
assert_eq "cancel never sleeps"     "no"  "$([[ $out == *'DRY RUN'* ]] && print yes || print no)"
rm -f $log
```

(TERM is used rather than INT because a background job in a non-interactive shell starts with SIGINT ignored. `cancel` is trapped on INT, TERM and HUP alike.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zsh tests/test_sleeptimer.zsh 2>&1 | grep -E '^FAIL (tui|term_size|cancel)'`
Expected: FAIL for `tui enters alt screen`, `tui restores terminal`, `tui final frame 100%`, `term_size override` and `cancel restores screen`.

- [ ] **Step 3: Implement**

Replace the whole old `countdown` function (comment included) with:

```zsh
# use_tui — full-screen mode when stdout is a terminal; SLEEPTIMER_TUI=1 or 0 forces it on or off.
use_tui() {
  [[ -n $SLEEPTIMER_TUI ]] && { [[ $SLEEPTIMER_TUI == 1 ]]; return }
  [[ -t 1 ]]
}

# term_size — prints "<cols> <rows>"; SLEEPTIMER_COLS/SLEEPTIMER_ROWS override, 80x24 if unknown.
term_size() {
  local rows cols
  { read rows cols < <(stty size </dev/tty) } 2>/dev/null
  (( cols > 0 )) || cols=80
  (( rows > 0 )) || rows=24
  print "${SLEEPTIMER_COLS:-$cols} ${SLEEPTIMER_ROWS:-$rows}"
}

screen_enter() { IN_TUI=1; printf '\e[?1049h\e[?25l' }
screen_leave() { (( IN_TUI )) && printf '\e[?25h\e[?1049l'; IN_TUI=0 }

# draw_screen <elapsed> <total> <end-epoch> — redraw the full-screen frame in place.
draw_screen() {
  local -a size=($(term_size))
  local frame=$(render_screen $1 $2 $size[1] $size[2] $3 $EPOCHSECONDS)
  printf '\e[H%s\e[J' "${frame//$'\n'/$'\e[K\n'}"
}

# countdown <total> — redraw until total seconds of wall-clock time pass.
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
}
```

Change `cancel` to:

```zsh
cancel() {
  screen_leave
  print "\nCancelled — not sleeping."
  exit 130
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zsh tests/test_sleeptimer.zsh | tail -1`
Expected: `All tests passed`

Manual check in a real terminal: `SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_CONFIG=/tmp/st-smoke ./sleeptimer 20s`.
- The screen fills with big digits counting down, a bar filling to the right edge, and the info lines.
- Drag the window smaller and bigger: the next tick redraws to fit with no wrapped lines.
- Run it again and press Ctrl+C: the normal screen comes back with a visible cursor and `Cancelled — not sleeping.`
- Let one run finish: it ends with `DRY RUN: pause + mute + sleep` on the normal screen.
- Run `rm /tmp/st-smoke` afterwards.

- [ ] **Step 5: Commit**

```bash
git add sleeptimer tests/test_sleeptimer.zsh
git commit -m "feat: full-screen countdown that fills the terminal; restore it on cancel"
```

---

### Task 7: README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the user-visible behavior from Tasks 1–6 (prompt text, arguments, `-h`, `themes`, config path, env vars).

- [ ] **Step 1: Update the intro**

Replace the intro bar example and its sentence ("While it waits, it shows a bar…" through the code block) with:

````markdown
While it waits, it fills the Terminal window with a big countdown, a progress
bar and the time your Mac will go to sleep:

```
                ######  ######      ######  ######
                    ##      ##  ##  ##  ##  ##  ##
                ######  ######      ##  ##  ##  ##
                ##          ##  ##  ##  ##  ##  ##
                ######  ######      ######  ######

  ##################################------------------------------------

             50%  ·  23:00 left  ·  sleeps at 23:45
           2760 seconds = 46 minutes = 0.77 hours
                         Ctrl+C to cancel
```
````

- [ ] **Step 2: Rewrite "Part 2: Using it"**

Replace steps 3–4 and the example with:

````markdown
3. It asks **How long?** Type a number and press **Return**. The first time,
   numbers mean **minutes**.
   - Want another unit? Add it after the number: **`90s`**, **`45m`**, **`2h`**.
     sleeptimer remembers it, so next time a plain number uses that unit.
   - Decimals are fine, with a comma or a dot: **`1,25h`** is 75 minutes.
   - Just press **Return** to use the same time as last time.

**Example: put the Mac to sleep in 45 minutes**

```
sleeptimer
How long? (minutes): 45
Sleeping in 45:00 (2700 seconds = 45 minutes = 0.75 hours).
Goes to sleep at 23:45. Ctrl+C to cancel.
```

**Shortcut:** put the time right after the command to skip the question:
`sleeptimer 45`, `sleeptimer 1,5h`, `sleeptimer 90s`.

**Help:** `sleeptimer -h` lists everything it can do.
````

- [ ] **Step 3: Add a "Change the look" section** after "Changed your mind? Cancel it":

````markdown
## Change the look (themes)

Type **`sleeptimer themes`** and press **Return**. You'll see each theme with a
preview. Type its number (or name) and press **Return**. Your choice is
remembered.

| Theme | Looks like |
|---|---|
| `night` (default) | Deep blue and lavender |
| `classic` | Plain `#` and `-`, no colors |
| `ocean` | Bright blue on navy |
| `forest` | Greens |
| `sunset` | Orange and red |

You can also switch directly: `sleeptimer themes ocean`.
````

- [ ] **Step 4: Update the troubleshooting table and the developer section**

In "Something not working?", replace the "It keeps asking the same question again" row with:

```markdown
| It keeps asking **How long?** again | It didn't understand your answer. Type a number like `45`, or a number with a unit like `90s`, `45m` or `1,5h`. The longest timer is 24 hours. |
| The timer is in the wrong unit | A plain number uses the unit you used last time. Press **Control + C**, then add the unit, like `45m`. |
| Colors look strange | Try `sleeptimer themes classic`. |
```

In "For developers", add these rows to the environment-variables table:

```markdown
| `SLEEPTIMER_CONFIG` | Where settings (last unit, last time, theme) are saved | `~/.config/sleeptimer/config` |
| `SLEEPTIMER_TUI` | `1` forces the full-screen view, `0` forces the one-line bar | full screen when output is a terminal |
| `SLEEPTIMER_COLS` / `SLEEPTIMER_ROWS` | Pretend the terminal is this size | real size |
| `NO_COLOR` | Any non-empty value turns colors off | off |
```

Change the `SLEEPTIMER_BAR_WIDTH` description to `Width of the one-line bar (used when output isn't a terminal)`.

- [ ] **Step 5: Verify and commit**

Run: `zsh tests/test_sleeptimer.zsh | tail -1` → `All tests passed`.
Run: `grep -n 'Unit? \[s/m/h\]' README.md` → no output (the old prompt is gone).

```bash
git add README.md
git commit -m "docs: document new prompt, shortcuts, full-screen view and themes"
```
