# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`sleeptimer` is a single zsh script for macOS. It counts down, then pauses Now Playing media (via the optional `media-control` from Homebrew), mutes the sound and puts the Mac to sleep. Users install it by copying that one file into `~/.local/bin` (see README Step 3), so **it must stay a single self-contained file** with no runtime dependencies beyond macOS built-ins.

## Commands

```zsh
zsh tests/test_sleeptimer.zsh                      # full suite; last line "All tests passed", exit 0
zsh tests/test_sleeptimer.zsh | grep -v '^PASS'    # show only failures
zsh tests/test_sleeptimer.zsh | grep 'parse'       # no single-test runner: filter by assert name
SLEEPTIMER_DRY_RUN=1 ./sleeptimer 20s              # try it without muting or sleeping the Mac
```

**Never run `./sleeptimer` without `SLEEPTIMER_DRY_RUN=1`.** When the timer ends it really runs `osascript -e "set volume with output muted" && pmset sleepnow`, and that exact command must stay unchanged. When experimenting, also set `SLEEPTIMER_CONFIG` to a temp file so the user's real `~/.config/sleeptimer/config` isn't overwritten.

There is no build, lint or test framework. Tests are plain zsh using `assert_eq <name> <expected> <actual>` and `assert_fails <name> <cmd...>`.

## Architecture

- **Sourceable script.** The last line, `[[ $ZSH_EVAL_CONTEXT == toplevel ]] && main "$@"`, runs `main` only when the script is executed. The test file `source`s the script and calls functions directly. It also runs the script as a subprocess (`zsh $SCRIPT …`) for end-to-end checks.
- **Pure functions vs I/O.** Parsing and formatting are pure and print to stdout: `parse_duration`, `fmt_dec`, `describe_duration`, `fmt_time`, `fmt_clock`, `render_bar`, `render_big` and `render_screen`. I/O is kept to thin wrappers: `ask_duration`, `load_config`/`save_config`, `tethered`, `finish_within`, `kill_jobs`, `pause_media`, `ask_media_permission`, `draw_screen`, `countdown`, `go_to_sleep` and `main`. Put new logic in a pure function so it can be tested.
- **Durations** travel as the string `"<seconds> <unit>"`, where the unit is `s|m|h`. `parse_duration` returns 1 for invalid input and 2 for over `MAX_SECS` (24 h). A bare number uses the remembered unit `CFG_UNIT`.
- **Settings** live in a `key=value` file (`unit`, `theme`, `last`), read into the `CFG_*` globals. Bad values fall back to defaults, and `save_config` never fails.
- **Themes** are `THEMES[name]="fill|empty|fill-color|empty-color|accent|description"`, with order and numbering from `THEME_NAMES`. `apply_theme` sets the `FILL`/`EMPTY`/`C_*` globals that all the rendering functions read. `NO_COLOR` disables colour.
- **Display modes:**
  - **Full screen** is used when stdout is a TTY. It uses the alternate screen, big digits, and a bar filling all remaining rows. `render_screen` must return exactly `rows` lines, none wider than `cols`; a wrapped line scrolls and garbles the redraw.
  - **One-line `render_bar`** is used otherwise.
  - `cancel` (trapped on INT/TERM/QUIT) must call `kill_jobs` and `screen_leave` before exiting 130. `hangup` (HUP, i.e. the window was closed) calls `kill_jobs`, restores the screen with errors ignored, prints nothing and exits 129. In a `$(…)` helper it exits 129 too, and `main` turns that into `hangup` (HUP at the `How long?` prompt).
  - After `countdown` returns, `main` ignores INT/TERM/QUIT/HUP: pause + mute + sleep always finishes as one step.
  - Background helpers (pauses, the permission query) start through `tethered`, which kills them within ~0.2 s once the script is gone, even after `kill -9`, like `caffeinate -w`. `kill_jobs` ends them on every trapped exit and when the countdown ends.
- **YOLO mode** (`sleeptimer yolo`) is the opposite of the timer. `caffeinate -dims -w $$` blocks normal sleep. Lid-close sleep needs root: a `nohup sudo -n /bin/zsh -f -c "$(yolo_guard …)"` guard sets `pmset -a disablesleep 1` and polls the script's pid, then writes back the *previous* `SleepDisabled` value (`sleep_disabled`).
  - Never replace the polling with a trap: it must survive `kill -9` and closed windows.
  - The root shell runs with `-f` (no user startup files), a fixed `PATH` and detached stdio. Keep it that way, because macOS sudo keeps the user's `HOME` and `PATH`.
  - `wait_sleep_disabled` checks that the guard really took effect before the screen claims the lid is protected.
  - `SLEEPTIMER_DRY_RUN` also skips `sudo`/`caffeinate` in `yolo` and `yolo off`.
  - Tests use fake `sudo`/`pmset`/`caffeinate` in `$fake_bin` (log: `$FAKE_LOG`; the fake `pmset` remembers its state in `$FAKE_STATE`) and must never call the real ones. Any test that runs the script must put `$fake_bin` first on `PATH`, because the timer reads `pmset -g` too.

## Test hooks (environment variables)

| Variable | Effect |
|---|---|
| `SLEEPTIMER_DRY_RUN` | Prints a message instead of pausing, muting and sleeping |
| `SLEEPTIMER_CONFIG` | Settings file path (tests use a temp dir) |
| `SLEEPTIMER_TUI` | `1`/`0` forces full-screen or one-line mode |
| `SLEEPTIMER_COLS` / `SLEEPTIMER_ROWS` | Fake terminal size |
| `SLEEPTIMER_TICK` | Seconds between redraws |
| `SLEEPTIMER_GRACE` | Seconds late before `countdown` returns 2 (ended late without sleeping: Ctrl+Z, clock change) |
| `SLEEPTIMER_BAR_WIDTH` | One-line bar width |

Tests call `apply_theme classic` so expected strings are plain `#`/`-` with no escape codes.

Fake-command env for YOLO tests:
- `STUB_SLEEP_DISABLED`: what `pmset -g` reports until a `disablesleep` call is recorded.
- `STUB_SUDO_RC`: non-zero makes every fake `sudo` fail.
- `STUB_SUDO_N_RC`: non-zero fails only the background `sudo -n` guard.
- `STUB_OSASCRIPT_RC` / `STUB_OSASCRIPT_HANG=1` (`=2`: hang and ignore TERM): the fake `osascript`'s exit code, or make it hang.
- `STUB_SLEEPNOW_RC`: the fake `pmset sleepnow`'s exit code.
- `STUB_WAKETIME`: the epoch second the fake `sysctl -n kern.waketime` reports as the last wake. `countdown` returns 1 when the Mac woke after the deadline, or 2 when it ended more than `GRACE` seconds late; `main` then exits 3 without sleeping.
- `STUB_RUNNING`: space-separated app names the fake `pgrep` reports as running. It only answers `pgrep -xqU $FAKE_UID <app>` (this user's apps, via `app_running`).

Tests that call the real `pause_media`/`go_to_sleep`/`ask_media_permission` code run it with `path=($fake_bin /bin)`. A tripwire at the top of the test file aborts the suite if `/bin` ever contains a real `pmset`/`osascript`/`pgrep`/`caffeinate`/`sudo`/`media-control`.

## zsh gotchas that have bitten this code

- Signal traps are inherited by `$(…)` subshells, and a rare race lets both the main shell and a helper subshell run the handler, which deadlocks. `cancel` and `yolo_stop` therefore start with `(( ZSH_SUBSHELL )) && exit 1`. Keep that in any new trap handler.

- In `"${var//pat/$'…'}"`, a `$'…'` *replacement* stays literal inside double quotes. Put the replacement in a variable first; `draw_screen` does this.
- Pad with a variable string using the `p` flag: `${(pl:N::$FILL:)}`.
- Use `"${(@s:|:)str}"` to keep empty fields when splitting.
- `$(…)` strips trailing newlines.
- `h[key]=$!` stores the literal text `$!` in an associative array. Copy the pid to a plain variable first (`pid=$!; h[key]=$pid`).
- `read "var?prompt"` only shows the prompt on a TTY, so tests check `duration_prompt` instead.
- Check theme names with `${THEME_NAMES[(Ie)$x]}`, not `$+THEMES[$x]`, which treats `*` as a wildcard.
- A background job in a non-interactive shell ignores SIGINT, so tests cancel with TERM.
- The bar characters are multibyte. The script forces a UTF-8 locale so `${#x}` counts characters rather than bytes.

## Conventions

- `main` handles `-h`/`--help`/`help`, `themes [name]`, unknown `-*` options (exit 2), a duration argument, or falls back to the prompt. The help text is in `usage()`.
- User-facing strings (the prompt, the "Sleeping in …" and "Goes to sleep at …" lines, error hints, `Cancelled — not sleeping.`) are asserted as substrings in the tests and quoted in the README. When you change one, update all three places: the script, the tests and the README.
- The README is a step-by-step guide for non-technical users. Keep its wording simple, and update it whenever prompts, messages or commands change.
- Implementation plans live in `docs/superpowers/plans/`. Work happens on `feat/*` branches and lands via a PR to `master`.
