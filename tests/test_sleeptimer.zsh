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

print
(( fails == 0 )) && print "All tests passed" || print "$fails test(s) failed"
exit $(( fails > 0 ))
