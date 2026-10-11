# sleeptimer

**A sleep timer for your Mac.** Tell it how long to wait, and when the time is
up it **pauses whatever is playing**, **turns the sound off** and **puts your
Mac to sleep**. It's handy when
you fall asleep to a video, music or a stream.

While it waits, it fills the Terminal window with a big countdown, a progress
bar and the time your Mac will go to sleep:

```
                  ######  ######      ######  ######
                      ##      ##  ##  ##  ##  ##  ##
                  ######  ######      ##  ##  ##  ##
                  ##          ##  ##  ##  ##  ##  ##
                  ######  ######      ######  ######

  #################################---------------------------------
  #################################---------------------------------
  #################################---------------------------------
  #################################---------------------------------

                50%  ·  23:00 left  ·  sleeps at 22:45
                2760 seconds = 46 minutes = 0.77 hours
                           Ctrl+C to cancel
```

You only have to set it up once. After that, using it takes about 5 seconds.

---

## Part 1: Setup (one time only, about 3 minutes)

### Step 1: Download it

1. On this GitHub page, click the green **`<> Code`** button near the top.
2. Click **Download ZIP**.
3. Open your **Downloads** folder and **double-click** the ZIP file.
   You now have a folder called **`sleeptimer-master`** in Downloads.

### Step 2: Open Terminal

Terminal is an app that comes with every Mac. You type commands into it.

1. Press **⌘ Command + Space** to open Spotlight search.
2. Type **`Terminal`** and press **Return**.

A window with some text and a blinking cursor opens. That's Terminal.

### Step 3: Install it

Copy **all** of the lines in the grey box below. You can select them with your
mouse or use the copy button in the corner of the box. Then click inside the
Terminal window, paste with **⌘ Command + V**, and press **Return**.

```
mkdir -p ~/.local/bin
cp ~/Downloads/sleeptimer-master/sleeptimer ~/.local/bin/
chmod +x ~/.local/bin/sleeptimer
grep -q '.local/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
echo "✅ Installed! Now close this Terminal window and open a new one."
```

When you see **✅ Installed!**, quit Terminal with **⌘ Command + Q** and open it
again as in Step 2. Terminal only picks up the new command in a fresh window.

### Step 4: Let it pause music and videos (recommended)

This step lets sleeptimer **pause** Spotify, Apple Music, YouTube and other
players before the Mac sleeps, so nothing starts playing again when you wake it.
It needs [Homebrew](https://brew.sh). If you don't have Homebrew, install it
first using the instructions on that page.

Paste this into Terminal and press **Return**:

```
brew install media-control
```

If you skip this step, sleeptimer still mutes the sound and puts the Mac to
sleep, but it doesn't pause anything.

You're done with setup. You can delete the ZIP and the `sleeptimer-master`
folder from Downloads if you like.

---

## Part 2: Using it

1. Open **Terminal**: press **⌘ Command + Space**, type `Terminal`, press **Return**.
2. Type **`sleeptimer`** and press **Return**.
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

**Leave the Terminal window open.** You can minimize it with the yellow button,
but don't close it, or the timer stops.

When the bar reaches 100%, whatever is playing gets paused, the sound turns off
and the Mac goes to sleep.

---

## Changed your mind? Cancel it

Click the Terminal window and press **Control + C**. That's the **control**
key, not Command.

You'll see `Cancelled — not sleeping.`, and nothing gets paused, muted or put to sleep.

---

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

---

## When you wake the Mac up

**Your music or video is paused.** Press play when you want it again.

**The sound is still off.** That's on purpose. To turn it back on, press the
**mute key** or **volume-up key** on your keyboard (F10–F12 on most Macs), or
click the speaker icon at the top of the screen.

---

## Something not working?

| What you see | What to do |
|---|---|
| `command not found: sleeptimer` | Quit Terminal (⌘ Command + Q) and open it again. If that doesn't help, redo **Step 3**. |
| `cp: ... No such file or directory` during setup | The ZIP wasn't unzipped, or it's not in Downloads. Go back to **Step 1** and double-click the ZIP in your Downloads folder. |
| It keeps asking **How long?** again | It didn't understand your answer. Type a number like `45`, or a number with a unit like `90s`, `45m` or `1,5h`. The longest timer is 24 hours. |
| The timer is in the wrong unit | A plain number uses the unit you used last time. Press **Control + C**, then add the unit, like `45m`. |
| Colors look strange | Try `sleeptimer themes classic`. |
| The timer stopped by itself | The Terminal window was probably closed. Start it again and leave the window open. |
| `Tip: brew install media-control ...` when the timer ends | Nothing was paused because Step 4 was skipped. Do **Step 4** if you want pausing. |
| Music or video didn't pause | Only players that show in the Mac's **Now Playing** control (in Control Center) can be paused. |
| I want a different time | Press **Control + C** to cancel, then run `sleeptimer` again. |

---

## For developers

<details>
<summary>Tests, test mode and settings</summary>

Run the tests from the project folder. They never really pause, mute or sleep the Mac:

```
zsh tests/test_sleeptimer.zsh
```

Environment variables:

| Variable | What it does | Default |
|---|---|---|
| `SLEEPTIMER_DRY_RUN` | Any non-empty value prints a message instead of pausing, muting and sleeping | off |
| `SLEEPTIMER_TICK` | Seconds between progress-bar redraws | `1` |
| `SLEEPTIMER_BAR_WIDTH` | Width of the one-line bar (used when output isn't a terminal) | `30` |
| `SLEEPTIMER_CONFIG` | Where settings (last unit, last time, theme) are saved | `~/.config/sleeptimer/config` |
| `SLEEPTIMER_TUI` | `1` forces the full-screen view, `0` forces the one-line bar | full screen when output is a terminal |
| `SLEEPTIMER_COLS` / `SLEEPTIMER_ROWS` | Pretend the terminal is this size | real size |
| `NO_COLOR` | Any non-empty value turns colors off | off |

Example: `SLEEPTIMER_DRY_RUN=1 sleeptimer`

When the timer ends, it runs exactly:

```
media-control pause   # skipped (with a tip) if media-control isn't installed; errors ignored
osascript -e "set volume with output muted" && pmset sleepnow
```

</details>
