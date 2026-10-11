#!/usr/bin/env zsh
# Plain-zsh tests for sleeptimer. Run: zsh tests/test_sleeptimer.zsh

SLEEPTIMER_BAR_WIDTH=10
export SLEEPTIMER_CONFIG=$(mktemp -d)/sleeptimer/config  # never touch the real ~/.config
SCRIPT="${0:A:h}/../sleeptimer"
source $SCRIPT
apply_theme classic  # plain "#"/"-" and no color codes, so expected strings stay readable

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

# Fake sudo / pmset / caffeinate / osascript / pgrep, so no test ever changes real power settings or pauses real apps.
# The fake pmset remembers "disablesleep N" in $FAKE_STATE; until then "pmset -g" reports $STUB_SLEEP_DISABLED.
# STUB_SUDO_RC != 0 makes every sudo call fail; STUB_SUDO_N_RC != 0 fails only "sudo -n" (background guard).
# The fake sudo points the guard's fixed PATH at the fakes. Every call is appended to $FAKE_LOG.
# STUB_OSASCRIPT_RC sets osascript's exit code, STUB_OSASCRIPT_HANG=1 makes it hang (2: and ignore TERM; the mute line never hangs); STUB_SLEEPNOW_RC sets
# "pmset sleepnow"'s; STUB_RUNNING lists the apps the fake pgrep reports as running.
# STUB_PMSET_STUCK=1 makes the fake pmset ignore "disablesleep 0" (a guard that never restores).
# STUB_WAKETIME is the epoch second the fake "sysctl -n kern.waketime" reports as the last wake (default 0).
fake_bin=$(mktemp -d)
export FAKE_BIN=$fake_bin FAKE_LOG=$fake_bin/calls.log FAKE_STATE=$fake_bin/state FAKE_UID=$UID
export STUB_SLEEP_DISABLED=0 STUB_SUDO_RC=0 STUB_SUDO_N_RC=0
export STUB_OSASCRIPT_RC=0 STUB_OSASCRIPT_HANG=0 STUB_SLEEPNOW_RC=0 STUB_RUNNING= STUB_PMSET_STUCK=0
print -l '#!/bin/sh' \
  'if [ "$1" = "-g" ]; then v=$(cat "$FAKE_STATE" 2>/dev/null || echo "$STUB_SLEEP_DISABLED")' \
  '  printf "System-wide power settings:\n SleepDisabled\t\t%s\nCurrently in use:\n sleep 1\n" "$v"; exit 0; fi' \
  'echo "pmset $*" >> "$FAKE_LOG"' \
  '[ "$1" = "sleepnow" ] && exit "$STUB_SLEEPNOW_RC"' \
  'if [ "$2" = "disablesleep" ] && ! { [ "$3" = 0 ] && [ "$STUB_PMSET_STUCK" = 1 ]; }; then echo "$3" > "$FAKE_STATE"; fi' \
  'exit 0' > $fake_bin/pmset
print -l '#!/bin/sh' \
  'echo "sudo $*" >> "$FAKE_LOG"' \
  '[ "$STUB_SUDO_RC" = 0 ] || exit "$STUB_SUDO_RC"' \
  '[ "$1" = "-v" ] && exit 0' \
  'if [ "$1" = "-n" ]; then [ "$STUB_SUDO_N_RC" = 0 ] || exit "$STUB_SUDO_N_RC"; shift; fi' \
  'if [ "$1" = "/bin/zsh" ]; then exec zsh "$2" "$3" "$(printf %s "$4" | sed "s#PATH=/usr/bin#PATH=$FAKE_BIN:/usr/bin#")"; fi' \
  'exec "$@"' > $fake_bin/sudo
print -l '#!/bin/sh' \
  'echo "caffeinate $*" >> "$FAKE_LOG"; echo "caffeinate pid $$" >> "$FAKE_LOG"' \
  "trap 'echo \"caffeinate stopped\" >> \"\$FAKE_LOG\"; exit 0' TERM" \
  'while kill -0 "$3" 2>/dev/null; do sleep 0.2; done' > $fake_bin/caffeinate
print -l '#!/bin/sh' \
  'echo "osascript $*" >> "$FAKE_LOG"' \
  'case "$2" in *"set volume"*) ;; *) [ "$STUB_OSASCRIPT_HANG" = 1 ] && exec sleep 30;; esac' \
  'if [ "$STUB_OSASCRIPT_HANG" = 2 ]; then trap "" TERM; sleep 30; fi' \
  'exit "$STUB_OSASCRIPT_RC"' > $fake_bin/osascript
print -l '#!/bin/sh' \
  '[ "$1" = "-xqU" ] && [ "$2" = "$FAKE_UID" ] || exit 1  # only this user s apps count' \
  'for app in $STUB_RUNNING; do [ "$app" = "$3" ] && exit 0; done' \
  'exit 1' > $fake_bin/pgrep
print -l '#!/bin/sh' \
  '[ "$2" = "kern.waketime" ] && echo "{ sec = ${STUB_WAKETIME:-0}, usec = 0 } Thu Jan  1 00:00:00 1970"' \
  'exit 0' > $fake_bin/sysctl
chmod +x $fake_bin/*

# Tests that run the real pause/mute/sleep code use path=($fake_bin /bin). That is only safe while /bin
# holds none of the real tools, so stop everything if it ever does.
[[ -z $(path=(/bin); whence -p pmset osascript pgrep caffeinate sudo media-control sysctl) ]] ||
  { print "ABORT: /bin has a real pmset/osascript/pgrep/caffeinate/sudo/media-control; tests would touch the system"; exit 1 }

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
assert_eq "parse too long exit 2" "2" "$(parse_duration 25h m; print $?)"
assert_eq "parse invalid exit 1"  "1" "$(parse_duration abc m; print $?)"
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

# fmt_time
assert_eq "fmt_time secs"   "00:05"    "$(fmt_time 5)"
assert_eq "fmt_time mins"   "22:30"    "$(fmt_time 1350)"
assert_eq "fmt_time hours"  "2:30:00"  "$(fmt_time 9000)"
assert_eq "fmt_time zero"   "00:00"    "$(fmt_time 0)"

# fmt_clock (UTC so results don't depend on where the tests run)
assert_eq "clock today"     "01:00"           "$(TZ=UTC fmt_clock 3600 0)"
assert_eq "clock tomorrow"  "01:00 tomorrow"  "$(TZ=UTC fmt_clock 90000 82800)"
assert_eq "clock later"     "Sun 11:20"       "$(TZ=UTC fmt_clock 300000 0)"

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

# render_bar (classic theme, BAR_WIDTH=10)
assert_eq "bar empty"    "[----------]   0%  01:00 left"  "$(render_bar 0 60)"
assert_eq "bar half"     "[#####-----]  50%  00:30 left"  "$(render_bar 30 60)"
assert_eq "bar full"     "[##########] 100%  00:00 left"  "$(render_bar 60 60)"
assert_eq "bar overflow" "[##########] 100%  00:00 left"  "$(render_bar 99 60)"
assert_eq "bar width arg" "[##--]  50%  00:30 left"       "$(render_bar 30 60 4)"

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
print -l 'last=9999999999' > $SLEEPTIMER_CONFIG
load_config
assert_eq "config ignores last over 24h" "0" "$CFG_LAST"
assert_eq "config unwritable ok" "0" "$( CONFIG=/nonexistent/dir/config; save_config; print $? )"
rm -f $SLEEPTIMER_CONFIG; load_config

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
assert_eq "ask too long explains" "yes" \
  "$( [[ $(print -l 45 30m | ask_duration 2>&1 >/dev/null) == *'longer than 24 hours'*'in hours'* ]] && print yes )"
CFG_UNIT=m CFG_LAST=0

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

# countdown (compact mode): wall-clock based, so a 0.3s tick still finishes ~on time and ends at 100%
TICK=0.3
t0=$EPOCHSECONDS
out=$(SLEEPTIMER_TUI=0 countdown 2)
took=$(( EPOCHSECONDS - t0 ))
assert_eq "countdown ends at 100%" "yes" "$([[ $out == *'100%  00:00 left'* ]] && print yes)"
assert_eq "countdown starts at 0%" "yes" "$([[ $out == *'[----------]   0%'* ]] && print yes)"
assert_eq "countdown duration ok"  "yes" "$( (( took >= 1 && took <= 4 )) && print yes )"
assert_eq "countdown on time ok" "0" "$( path=($fake_bin /bin); SLEEPTIMER_TUI=0 countdown 1 >/dev/null; print $? )"
assert_eq "countdown woke after the deadline" "1" \
  "$( path=($fake_bin /bin); export STUB_WAKETIME=$(( EPOCHSECONDS + 100 )); SLEEPTIMER_TUI=0 countdown 1 >/dev/null; print $? )"
assert_eq "countdown a little late still fires" "0" \
  "$( path=($fake_bin /bin); TICK=2.5 SLEEPTIMER_TUI=0 countdown 1 >/dev/null; print $? )"
assert_eq "countdown far too late (Ctrl+Z, clock change) gives up" "2" \
  "$( path=($fake_bin /bin); GRACE=0 TICK=2.5 SLEEPTIMER_TUI=0 countdown 1 >/dev/null; print $? )"
# woke_after: reads the last wake from the kernel; unknown means "no"
assert_eq "woke_after later wake"   "yes" "$( path=($fake_bin /bin); export STUB_WAKETIME=200; woke_after 100 && print yes )"
assert_eq "woke_after earlier wake" "no"  "$( path=($fake_bin /bin); export STUB_WAKETIME=50; woke_after 100 && print yes || print no )"
assert_eq "woke_after no sysctl"    "no"  "$( path=(/nonexistent); woke_after 100 && print yes || print no )"

# countdown (full-screen mode): enters and leaves the alternate screen, last frame is 100%
out=$(SLEEPTIMER_TUI=1 SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20 countdown 1)
assert_eq "tui enters alt screen" "yes" "$([[ $out == $'\e[?1049h\e[?25l'* ]] && print yes)"
assert_eq "tui restores terminal" "yes" "$([[ $out == *$'\e[?25h\e[?1049l' ]] && print yes)"
assert_eq "tui final frame 100%"  "yes" "$([[ $out == *'100%  ·  00:00 left'* ]] && print yes)"
TICK=1

# draw_screen: real erase-line + newline between rows, no literal escape text
frame=$(SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20 draw_screen 10 600 600)
assert_eq "draw_screen real newlines" "20" "${#${(@f)frame}}"
assert_eq "draw_screen erases lines" "yes" "$([[ $frame == *$'\e[K\n'* ]] && print yes)"
assert_eq "draw_screen no literal escapes" "no" "$([[ $frame == *"\$'"* ]] && print yes || print no)"

# term_size: env override
assert_eq "term_size override" "100 40" "$(SLEEPTIMER_COLS=100 SLEEPTIMER_ROWS=40 term_size)"

# go_to_sleep dry run never touches the system
assert_eq "go_to_sleep dry run" "DRY RUN: pause + mute + sleep" "$(SLEEPTIMER_DRY_RUN=1 go_to_sleep)"

# finish_within: waits for background jobs, kills the ones still running after the limit (TERM, then KILL)
assert_eq "finish_within keeps exit statuses" "0 1 7" \
  "$(true & a=$!; false & b=$!; sh -c 'exit 7' & c=$!; finish_within 2 $a $b $c; wait $a; x=$?; wait $b; y=$?; wait $c; print "$x $y $?")"
t0=$EPOCHSECONDS
assert_eq "finish_within kills hung jobs together" "143 143" \
  "$(sleep 10 & a=$!; sleep 10 & b=$!; finish_within 1 $a $b; wait $a; x=$?; wait $b; print "$x $?")"
assert_eq "finish_within shares one limit" "yes" "$( (( EPOCHSECONDS - t0 <= 3 )) && print yes )"
t0=$EPOCHSECONDS
assert_eq "finish_within kills a job that ignores TERM" "137" \
  "$(sh -c 'trap "" TERM; sleep 8' >/dev/null & a=$!; finish_within 1 $a; wait $a; print $?)"
assert_eq "finish_within ignoring TERM is still quick" "yes" "$( (( EPOCHSECONDS - t0 <= 4 )) && print yes )"

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
  'osascript -e if application "Music" is running then tell application "Music" to pause
osascript -e if application "Spotify" is running then tell application "Spotify" to pause' "$(sort $FAKE_LOG)"
: > $FAKE_LOG
( path=($fake_bin /bin); export STUB_RUNNING=; pause_media 2>/dev/null )
assert_eq "pause_media never opens apps" "" "$(<$FAKE_LOG)"
: > $FAKE_LOG; rm -f $STUB_LOG
( path=($stub_dir $fake_bin /bin); export STUB_RUNNING=Music; pause_media )
assert_eq "pause_media both ways" "yes" \
  "$([[ $(<$STUB_LOG) == pause && $(<$FAKE_LOG) == *'"Music" to pause'* ]] && print yes)"
t0=$EPOCHSECONDS
( path=($stub_dir $fake_bin /bin); export STUB_RUNNING='Music Spotify' STUB_OSASCRIPT_HANG=2; pause_media 2>/dev/null )
assert_eq "pause_media gives up on hung apps within ~4 s total" "yes" "$( (( EPOCHSECONDS - t0 <= 5 )) && print yes )"
pm_hung=$( path=($fake_bin /bin); export STUB_RUNNING=Music STUB_OSASCRIPT_HANG=2; pause_media 2>&1 >/dev/null )
assert_eq "pause_media says when an app hung" "yes" \
  "$([[ $pm_hung == *"Music didn't answer in time"* && $pm_hung != *Automation* ]] && print yes)"
pm_err=$( path=($stub_dir $fake_bin /bin); export STUB_RUNNING=Music STUB_OSASCRIPT_RC=1; pause_media 2>&1 >/dev/null )
assert_eq "pause_media says when an app didn't pause" "yes" \
  "$([[ $pm_err == *"Couldn't pause Music"*'Privacy & Security → Automation'* ]] && print yes)"
assert_eq "pause_media quiet when all is well" "" "$( path=($stub_dir $fake_bin /bin); export STUB_RUNNING=Music; pause_media 2>&1 )"
: > $FAKE_LOG
rm -rf $stub_dir

# ask_media_permission: a harmless query to open apps at the START, so macOS's one-time
# "Terminal wants to control Music" question shows up while the user is awake, not at sleep time
( path=($fake_bin /bin); export STUB_RUNNING='Music Spotify'; ask_media_permission ); sleep 0.5
assert_eq "permission asked at start" \
  'osascript -e if application "Music" is running then tell application "Music" to get player state
osascript -e if application "Spotify" is running then tell application "Spotify" to get player state' "$(sort $FAKE_LOG)"
: > $FAKE_LOG
( path=($fake_bin /bin); export STUB_RUNNING=; ask_media_permission ); sleep 0.5
assert_eq "permission never opens apps" "" "$(<$FAKE_LOG)"
( path=($fake_bin /bin); export STUB_RUNNING=Music SLEEPTIMER_DRY_RUN=1; ask_media_permission ); sleep 0.5
assert_eq "permission skipped in dry run" "" "$(<$FAKE_LOG)"
t0=$EPOCHSECONDS
( path=($fake_bin /bin); export STUB_RUNNING=Music STUB_OSASCRIPT_HANG=1; ask_media_permission )
assert_eq "permission doesn't wait for an answer" "yes" "$( (( EPOCHSECONDS - t0 <= 1 )) && print yes )"
sleep 0.5  # let that background fake log its call before the log is cleared below
assert_eq "kill_jobs ends a pending permission query" "" \
  "$( path=($fake_bin /bin); export STUB_RUNNING=Music STUB_OSASCRIPT_HANG=2; ask_media_permission; sleep 0.3; kill_jobs; sleep 0.3
      pgrep -f "$fake_bin/osascript" )"
: > $FAKE_LOG

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

# end-to-end: executed script, dry run, compact mode
run() { PATH=$fake_bin:$PATH SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_TUI=0 zsh $SCRIPT "$@" }
rm -f $SLEEPTIMER_CONFIG
e2e=$(print 1s | run 2>/dev/null)
assert_eq "e2e announces"      "yes" "$([[ $e2e == *'Sleeping in 00:01 (1 second = 0.02 minutes).'* ]] && print yes)"
assert_eq "e2e shows sleep at" "yes" "$([[ $e2e == *'Goes to sleep at '[0-9][0-9]:[0-9][0-9]* ]] && print yes)"
assert_eq "e2e dry-runs"       "yes" "$([[ $e2e == *'DRY RUN: pause + mute + sleep'* ]] && print yes)"
assert_eq "e2e says time's up" "yes" \
  "$([[ $e2e == *"Time's up: pausing, muting and putting your Mac to sleep."*'DRY RUN'* ]] && print yes)"
assert_eq "e2e remembers unit" "yes" "$( grep -qx 'unit=s' $SLEEPTIMER_CONFIG && grep -qx 'last=1' $SLEEPTIMER_CONFIG && print yes )"
e2e=$(print 1 | run 2>/dev/null)
assert_eq "e2e bare number uses remembered unit" "yes" "$([[ $e2e == *'Sleeping in 00:01'* ]] && print yes)"
e2e=$(run 1s 2>/dev/null </dev/null)
assert_eq "e2e argument skips prompt" "yes" "$([[ $e2e == *'DRY RUN'* ]] && print yes)"
assert_eq "e2e dry run asks no permission" "" \
  "$(: > $FAKE_LOG; STUB_RUNNING=Music run 1s >/dev/null 2>&1; cat $FAKE_LOG)"
assert_eq "e2e bad argument exit" "1" "$(run banana >/dev/null 2>&1; print $?)"
assert_eq "e2e bad argument hint" "yes" "$([[ $(run banana 2>&1) == *'sleeptimer -h'* ]] && print yes)"
assert_eq "e2e too long explains" "yes" "$([[ $(run 25h 2>&1) == *'longer than 24 hours'* ]] && print yes)"
assert_eq "e2e too long exit 1" "1" "$(run 25h >/dev/null 2>&1; print $?)"
e2e=$(STUB_WAKETIME=$(( EPOCHSECONDS + 100 )) run 1s 2>/dev/null); e2e_rc=$?
assert_eq "e2e late: explains"     "yes" "$([[ $e2e == *'Time ran out while your Mac was asleep'* ]] && print yes)"
assert_eq "e2e late: never sleeps" "no"  "$([[ $e2e == *'DRY RUN'* ]] && print yes || print no)"
assert_eq "e2e late: exit 3"       "3"   "$e2e_rc"
e2e=$(SLEEPTIMER_TICK=2.5 SLEEPTIMER_GRACE=0 run 1s 2>/dev/null); e2e_rc=$?
assert_eq "e2e ended late: explains"     "yes" "$([[ $e2e == *'The timer ended late, so it won'"'"'t put your Mac to sleep now.'* ]] && print yes)"
assert_eq "e2e ended late: never sleeps" "no"  "$([[ $e2e == *'DRY RUN'* ]] && print yes || print no)"
assert_eq "e2e ended late: exit 3"       "3"   "$e2e_rc"

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

# end-to-end: cancelling restores the terminal and never sleeps
log=$(mktemp)
rm -f $FAKE_STATE
PATH=$fake_bin:$PATH SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_TUI=1 SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20 zsh $SCRIPT 30s >$log 2>&1 &
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

# end-to-end, not a dry run, but PATH holds only the fakes and /bin (see the tripwire), and it is
# stopped long before the timer ends: Ctrl+C or a closed window must also end the permission query
for sig in TERM HUP QUIT KILL; do
  env PATH=$fake_bin:/bin STUB_RUNNING=Music STUB_OSASCRIPT_HANG=2 SLEEPTIMER_TUI=0 /bin/zsh $SCRIPT 30s >/dev/null 2>&1 &
  pid=$!
  sleep 1.5
  kill -$sig $pid; wait $pid; rc=$?
  sleep 1.5
  assert_eq "$sig ends the permission query" "" "$(pgrep -f "$fake_bin/osascript")"
  [[ $sig == QUIT ]] && assert_eq "QUIT cancels like Ctrl+C" "130" "$rc"
done

# once the timer has run out it finishes pause + mute + sleep even if the window closes or Ctrl+C
# comes in the middle (the pause step is made slow by a hung app); fakes only, as above
for sig in HUP INT; do
  : > $FAKE_LOG; rm -f $FAKE_STATE
  env PATH=$fake_bin:/bin STUB_RUNNING=Music STUB_OSASCRIPT_HANG=1 SLEEPTIMER_TUI=0 /bin/zsh $SCRIPT 1s >/dev/null 2>&1 &
  pid=$!
  sleep 2.5
  kill -$sig $pid; wait $pid; rc=$?
  assert_eq "$sig during the final step still sleeps" "yes" "$(grep -qx 'pmset sleepnow' $FAKE_LOG && print yes)"
  assert_eq "$sig during the final step exit 0" "0" "$rc"
done
# Ctrl+Z in the final step must not freeze it half done (an fg hours later would sleep the Mac by surprise)
: > $FAKE_LOG
env PATH=$fake_bin:/bin STUB_RUNNING=Music STUB_OSASCRIPT_HANG=1 SLEEPTIMER_TUI=0 /bin/zsh $SCRIPT 1s >/dev/null 2>&1 &
pid=$!
sleep 2.5
kill -TSTP $pid
sleep 4
assert_eq "TSTP during the final step still sleeps" "yes" "$(grep -qx 'pmset sleepnow' $FAKE_LOG && print yes)"
kill -CONT $pid 2>/dev/null; wait $pid
: > $FAKE_LOG

# sleep_disabled reads pmset -g
assert_eq "sleep_disabled 0" "0" "$( path=($fake_bin $path); STUB_SLEEP_DISABLED=0; sleep_disabled )"
assert_eq "sleep_disabled 1" "1" "$( path=($fake_bin $path); export STUB_SLEEP_DISABLED=1; sleep_disabled )"
assert_eq "sleep_disabled no pmset" "0" "$( path=(/nonexistent); sleep_disabled )"

# yolo_guard: restores the previous value once the pid is gone
assert_eq "yolo_guard command" \
  "PATH=/usr/bin:/bin:/usr/sbin:/sbin; exec >/dev/null 2>&1 </dev/null; trap '' INT HUP TERM PIPE; pmset -a disablesleep 1; while kill -0 42 2>/dev/null; do sleep 1; done; pmset -a disablesleep 0" \
  "$(yolo_guard 42 0)"

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
assert_eq "yolo frame heat warning" "yes" "$([[ $yframe == *"Don't put it in a bag"* ]] && print yes)"

# end-to-end: yolo turns sleep off, keeps the Mac awake, and puts everything back however it ends
ywait=1.5
yolo_run() {  # yolo_run <signal> [env...] — run "sleeptimer yolo" $ywait s, stop it, let the guard settle; sets yrc, yout, ylog
  local out=$(mktemp)
  : > $FAKE_LOG; rm -f $FAKE_STATE
  env PATH=$fake_bin:$PATH SLEEPTIMER_TUI=0 SLEEPTIMER_TICK=0.2 "${@:2}" zsh $SCRIPT yolo >$out 2>&1 &
  local pid=$!
  sleep $ywait
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
assert_eq "yolo final state on"    "0"   "$(<$FAKE_STATE)"
assert_eq "yolo root shell clean"  "yes" "$([[ $ylog == *'sudo -n /bin/zsh -f -c PATH=/usr/bin:/bin:/usr/sbin:/sbin;'* ]] && print yes)"
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

ywait=4
yolo_run TERM STUB_SUDO_N_RC=1
ywait=1.5
assert_eq "yolo guard failed: lid warning" "yes" "$([[ $yout == *"Couldn't block lid-close sleep"* ]] && print yes)"
assert_eq "yolo guard failed: no pmset"    "no"  "$(grep -q '^pmset -a disablesleep' <<< $ylog && print yes || print no)"

yolo_run TERM SLEEPTIMER_DRY_RUN=1
assert_eq "yolo dry run: no sudo"        "no"  "$([[ $ylog == *sudo* ]] && print yes || print no)"
assert_eq "yolo dry run: no caffeinate"  "no"  "$([[ $ylog == *caffeinate* ]] && print yes || print no)"
assert_eq "yolo dry run: says so"        "yes" "$([[ $yout == *'DRY RUN'* ]] && print yes)"

yolo_run TERM SLEEPTIMER_TUI=1 SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20
assert_eq "yolo tui enters alt screen"    "yes" "$([[ $yout == *$'\e[?1049h'*'awake for'* ]] && print yes)"
assert_eq "yolo tui restores terminal"    "yes" "$([[ $yout == *$'\e[?25h\e[?1049l'*'YOLO off'* ]] && print yes)"

assert_eq "yolo bad arg exit 2" "2" "$(run yolo nope >/dev/null 2>&1; print $?)"

# stop handlers inherited by a $(...) helper must exit quietly and leave the work to the main shell
assert_eq "yolo_stop in subshell silent" "" "$(YOLO_START=$EPOCHSECONDS; yolo_stop 2>&1)"
assert_eq "cancel in subshell silent"    "" "$(cancel 2>&1)"

# yolo off: turns sleep back on only when it is off
yrun() { PATH=$fake_bin:$PATH SLEEPTIMER_TUI=0 zsh $SCRIPT "$@" }
: > $FAKE_LOG; rm -f $FAKE_STATE
assert_eq "yolo off when on"  "yes" "$([[ $(yrun yolo off) == *'already on'* ]] && print yes)"
assert_eq "yolo off no sudo"  ""    "$(<$FAKE_LOG)"
assert_eq "yolo off when off" "yes" "$([[ $(STUB_SLEEP_DISABLED=1 yrun yolo off) == *'Sleep is back on.'* ]] && print yes)"
assert_eq "yolo off runs pmset" "yes" "$( grep -qx 'sudo pmset -a disablesleep 0' $FAKE_LOG && print yes )"
rm -f $FAKE_STATE
assert_eq "yolo off sudo fails" "1" "$(STUB_SLEEP_DISABLED=1 STUB_SUDO_RC=1 yrun yolo off >/dev/null 2>&1; print $?)"
: > $FAKE_LOG
assert_eq "yolo off dry run" "yes" "$([[ $(STUB_SLEEP_DISABLED=1 run yolo off) == *'DRY RUN'* ]] && print yes)"
assert_eq "yolo off dry run no sudo" "" "$(<$FAKE_LOG)"
assert_eq "help mentions yolo"  "yes" "$([[ $(run -h) == *'sleeptimer yolo off'* ]] && print yes)"

# normal timer warns when sleep is turned off system-wide (and pauses so full screen doesn't hide it)
rm -f $FAKE_STATE
t0=$EPOCHSECONDS
tui_warn=$(STUB_SLEEP_DISABLED=1 PATH=$fake_bin:$PATH SLEEPTIMER_DRY_RUN=1 SLEEPTIMER_TUI=1 SLEEPTIMER_COLS=60 SLEEPTIMER_ROWS=20 zsh $SCRIPT 1s 2>&1)
assert_eq "timer warning before full screen" "yes" "$([[ $tui_warn == *'Heads up'*$'\e[?1049h'* ]] && print yes)"
assert_eq "timer warning pauses in full screen" "yes" "$( (( EPOCHSECONDS - t0 >= 4 )) && print yes )"
assert_eq "timer warns if sleep off" "yes" "$([[ $(STUB_SLEEP_DISABLED=1 run 1s 2>&1) == *'Heads up: sleep is turned off'*'sleeptimer yolo off'* ]] && print yes)"
assert_eq "timer quiet if sleep on"  "no"  "$([[ $(run 1s 2>&1) == *'Heads up'* ]] && print yes || print no)"

rm -rf $fake_bin
rm -rf ${SLEEPTIMER_CONFIG:h:h}
print
(( fails == 0 )) && print "All tests passed" || print "$fails test(s) failed"
exit $(( fails > 0 ))
