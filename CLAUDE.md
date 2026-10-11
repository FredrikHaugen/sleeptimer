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
- **Pure functions vs I/O.** Parsing and formatting are pure and print to stdout: `parse_duration`, `fmt_dec`, `describe_duration`, `fmt_time`, `fmt_clock`, `render_bar`, `render_big` and `render_screen`. I/O is kept to thin wrappers: `ask_duration`, `load_config`/`save_config`, `draw_screen`, `countdown`, `go_to_sleep` and `main`. Put new logic in a pure function so it can be tested.
- **Durations** travel as the string `"<seconds> <unit>"`, where the unit is `s|m|h`. `parse_duration` returns 1 for invalid input and 2 for over `MAX_SECS` (24 h). A bare number uses the remembered unit `CFG_UNIT`.
- **Settings** live in a `key=value` file (`unit`, `theme`, `last`), read into the `CFG_*` globals. Bad values fall back to defaults, and `save_config` never fails.
- **Themes** are `THEMES[name]="fill|empty|fill-color|empty-color|accent|description"`, with order and numbering from `THEME_NAMES`. `apply_theme` sets the `FILL`/`EMPTY`/`C_*` globals that all the rendering functions read. `NO_COLOR` disables colour.
- **Display modes:**
  - **Full screen** is used when stdout is a TTY. It uses the alternate screen, big digits, and a bar filling all remaining rows. `render_screen` must return exactly `rows` lines, none wider than `cols`; a wrapped line scrolls and garbles the redraw.
  - **One-line `render_bar`** is used otherwise.
  - `cancel` (trapped on INT/TERM/HUP) must call `screen_leave` before exiting 130.

## Test hooks (environment variables)

| Variable | Effect |
|---|---|
| `SLEEPTIMER_DRY_RUN` | Prints a message instead of pausing, muting and sleeping |
| `SLEEPTIMER_CONFIG` | Settings file path (tests use a temp dir) |
| `SLEEPTIMER_TUI` | `1`/`0` forces full-screen or one-line mode |
| `SLEEPTIMER_COLS` / `SLEEPTIMER_ROWS` | Fake terminal size |
| `SLEEPTIMER_TICK` | Seconds between redraws |
| `SLEEPTIMER_BAR_WIDTH` | One-line bar width |

Tests call `apply_theme classic` so expected strings are plain `#`/`-` with no escape codes.

## zsh gotchas that have bitten this code

- In `"${var//pat/$'…'}"`, a `$'…'` *replacement* stays literal inside double quotes. Put the replacement in a variable first; `draw_screen` does this.
- Pad with a variable string using the `p` flag: `${(pl:N::$FILL:)}`.
- Use `"${(@s:|:)str}"` to keep empty fields when splitting.
- `$(…)` strips trailing newlines.
- `read "var?prompt"` only shows the prompt on a TTY, so tests check `duration_prompt` instead.
- Check theme names with `${THEME_NAMES[(Ie)$x]}`, not `$+THEMES[$x]`, which treats `*` as a wildcard.
- A background job in a non-interactive shell ignores SIGINT, so tests cancel with TERM.
- The bar characters are multibyte. The script forces a UTF-8 locale so `${#x}` counts characters rather than bytes.

## Conventions

- `main` handles `-h`/`--help`/`help`, `themes [name]`, unknown `-*` options (exit 2), a duration argument, or falls back to the prompt. The help text is in `usage()`.
- User-facing strings (the prompt, the "Sleeping in …" and "Goes to sleep at …" lines, error hints, `Cancelled — not sleeping.`) are asserted as substrings in the tests and quoted in the README. When you change one, update all three places: the script, the tests and the README.
- The README is a step-by-step guide for non-technical users. Keep its wording simple, and update it whenever prompts, messages or commands change.
- Implementation plans live in `docs/superpowers/plans/`. Work happens on `feat/*` branches and lands via a PR to `master`.
