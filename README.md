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
