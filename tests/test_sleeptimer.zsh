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
CFG_UNIT=m CFG_LAST=0

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
assert_eq "go_to_sleep dry run" "DRY RUN: pause + mute + sleep" "$(SLEEPTIMER_DRY_RUN=1 go_to_sleep)"

# pause_media: calls `media-control pause` via a stub on PATH; never fails
stub_dir=$(mktemp -d)
print -l '#!/bin/sh' 'echo "$@" > "$STUB_LOG"; exit 1' > $stub_dir/media-control
chmod +x $stub_dir/media-control
export STUB_LOG=$stub_dir/log
( path=($stub_dir $path); pause_media )
assert_eq "pause_media sends pause" "pause" "$(<$STUB_LOG)"
assert_eq "pause_media ignores tool failure" "0" "$( path=($stub_dir $path); pause_media; print $? )"
assert_eq "pause_media missing tool ok" "0" "$( path=(/nonexistent); pause_media 2>/dev/null; print $? )"
assert_eq "pause_media missing tool tip" "yes" \
  "$( path=(/nonexistent); [[ $(pause_media 2>&1) == *'brew install media-control'* ]] && print yes )"
rm -rf $stub_dir

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

rm -rf ${SLEEPTIMER_CONFIG:h:h}
print
(( fails == 0 )) && print "All tests passed" || print "$fails test(s) failed"
exit $(( fails > 0 ))
