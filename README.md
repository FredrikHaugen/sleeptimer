# sleeptimer

**A sleep timer for your Mac.** Tell it how long to wait, and when the time is
up it **turns the sound off** and **puts your Mac to sleep**. It's handy when
you fall asleep to a video, music or a stream.

While it waits, it shows a bar that fills up so you can see how long is left:

```
[###############---------------]  50%  22:30 left
```

You only have to set it up once. After that, using it takes about 5 seconds.

---

## Part 1: Setup (one time only, about 2 minutes)

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

You're done with setup. You can delete the ZIP and the `sleeptimer-master`
folder from Downloads if you like.

---

## Part 2: Using it

1. Open **Terminal**: press **⌘ Command + Space**, type `Terminal`, press **Return**.
2. Type **`sleeptimer`** and press **Return**.
3. It asks which unit you want. Type one letter and press **Return**:
   - **`s`** for seconds
   - **`m`** for minutes
   - **`h`** for hours
4. It asks how many. Type a number and press **Return**.

**Example: put the Mac to sleep in 45 minutes**

```
sleeptimer
Unit? [s/m/h]: m
How many minutes? 45
Sleeping in 45:00. Ctrl+C to cancel.
[##############----------------]  47%  23:50 left
```

**Leave the Terminal window open.** You can minimize it with the yellow button,
but don't close it, or the timer stops.

When the bar reaches 100%, the sound turns off and the Mac goes to sleep.

---

## Changed your mind? Cancel it

Click the Terminal window and press **Control + C**. That's the **control**
key, not Command.

You'll see `Cancelled — not sleeping.`, and nothing gets muted or put to sleep.

---

## When you wake the Mac up

**The sound is still off.** That's on purpose. To turn it back on, press the
**mute key** or **volume-up key** on your keyboard (F10–F12 on most Macs), or
click the speaker icon at the top of the screen.

---

## Something not working?

| What you see | What to do |
|---|---|
| `command not found: sleeptimer` | Quit Terminal (⌘ Command + Q) and open it again. If that doesn't help, redo **Step 3**. |
| `cp: ... No such file or directory` during setup | The ZIP wasn't unzipped, or it's not in Downloads. Go back to **Step 1** and double-click the ZIP in your Downloads folder. |
| It keeps asking the same question again | It didn't understand your answer. For the unit, type only `s`, `m` or `h`. For the amount, type a whole number like `30`, not `30.5`, `half` or `0`. |
| The timer stopped by itself | The Terminal window was probably closed. Start it again and leave the window open. |
| I want a different time | Press **Control + C** to cancel, then run `sleeptimer` again. |

---

## For developers

<details>
<summary>Tests, test mode and settings</summary>

Run the tests from the project folder. They never really mute or sleep the Mac:

```
zsh tests/test_sleeptimer.zsh
```

Environment variables:

| Variable | What it does | Default |
|---|---|---|
| `SLEEPTIMER_DRY_RUN` | Any non-empty value prints a message instead of muting and sleeping | off |
| `SLEEPTIMER_TICK` | Seconds between progress-bar redraws | `1` |
| `SLEEPTIMER_BAR_WIDTH` | Number of characters in the bar | `30` |

Example: `SLEEPTIMER_DRY_RUN=1 sleeptimer`

When the timer ends, it runs exactly:

```
osascript -e "set volume with output muted" && pmset sleepnow
```

</details>
