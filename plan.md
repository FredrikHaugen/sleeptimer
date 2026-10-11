# 🚀 Release & Launch Plan: macOS Sleep Timer

This document outlines the step-by-step roadmap to transition your project from a **CLI Shell Script** into a **Swift Menubar App**, using a **Custom Homebrew Tap** for beta testing, and finally launching to the **Official Homebrew Cask** repository at `v1.0.0`.

---

## 🗺️ Project Roadmap Overview

# 🚀 Release & Launch Plan: macOS Sleep Timer

This document outlines the step-by-step roadmap to transition your project from a **CLI Shell Script** into a **Swift Menubar App**, using a **Custom Homebrew Tap** for beta testing, and finally launching to the **Official Homebrew Cask** repository at `v1.0.0`.

---

## 🗺️ Project Roadmap Overview

Vær forsiktig når du bruker koden
Phase 1: CLI Stabilization (Current) ➡️ Phase 2: Swift Menubar App ➡️ Phase 3: Custom Tap Beta ➡️ Phase 4: Official Release

---

## 📝 Milestone Task List

### 🛠️ Phase 1: Polish current CLI Script (v0.1.0)

_Before writing Swift code, ensure the core logic is perfectly bulletproof._

- [ ] **Lock down core features:**
  - [ ] Media pause command (`osascript -e "tell application \"System Events\" to keystroke (key code 103)"` or target specific apps like Spotify/Music).
  - [ ] Safe Mac sleep logic (`pmset displaysleepnow` or `osascript -e 'tell application "System Events" to sleep'`).
  - [ ] Implement the `--yolo` flag (utilize `caffeinate -d` or `caffeinate -i` under the hood to prevent sleep).
- [ ] **Handle edge cases:**
  - [ ] Gracefully handle users closing the terminal midway through a countdown.
  - [ ] Add explicit logic ensuring the `--yolo` flag cleanly terminates when toggled off.

### 🍏 Phase 2: Build the Swift Menubar App (v0.5.0)

_Transition the shell logic into a native, compiled macOS Menubar (Status Bar) application._

- [ ] **Set up SwiftUI / AppKit project:**
  - [ ] Configure the app as an **Agent (UIElement)** so it only lives in the menu bar and has no Dock icon (`LSUIElement = YES` in `Info.plist`).
  - [ ] Design a simple, readable menu drop-down (Time input fields, Start/Stop buttons, and a checkbox for the `--yolo` mode).
- [ ] **Connect UI to Logic:**
  - [ ] Bridge the menu bar actions to execute your timer and sleep functions natively in Swift (using `Process()` to trigger terminal utilities if needed, or native `IOPMAssertion` APIs for the caffeinate behavior).
- [ ] **Build & Signing Setup:**
  - [ ] Archive the app as a standalone `.app` bundle.
  - [ ] Compress it into a `.dmg` or a `.zip` artifact for distribution.
  - [ ] _Crucial for Homebrew:_ Configure an ad-hoc or Apple Developer code-signing certificate so macOS doesn't block users with a "Damaged App" warning.

### 🧪 Phase 3: Launch Custom Homebrew Tap (v0.9.0 - Beta)

_Distribute the app safely to early testers and verify that the installation process works seamlessly._

- [ ] **Create the GitHub Repository:**
  - [ ] Create a public repository named `homebrew-sleep-timer` (or similar).
- [ ] **Draft the Homebrew Cask file:**
  - [ ] Create a local ruby file named `sleep-timer.rb` inside a `Casks/` directory.
  - [ ] Fill in the Cask template (see template block below).
- [ ] **Verify locally:**
  - [ ] Run `brew install --cask ./Casks/sleep-timer.rb` to ensure it downloads, unpacks, and moves the app into `/Applications` correctly.
- [ ] **Automate updates (Optional but recommended):**
  - [ ] Set up a GitHub Action or a GoReleaser config to automatically calculate the SHA256 hash and update the Cask file whenever you push a new Git Release Tag.

### 🏆 Phase 4: Official Homebrew Cask Submission (v1.0.0)

_Submit the stable app to the global Homebrew registry for public discovery._

- [ ] **Check Official Prerequisites:**
  - [ ] Ensure the app meets Homebrew's popularity metrics (collecting a handful of GitHub stars/users during Phase 3 usually achieves this).
  - [ ] Confirm the download URL is a stable, permanent public link (GitHub Releases are perfect).
- [ ] **Submit the Pull Request:**
  - [ ] Run `brew bump-cask-pr --version 1.0.0 --url <url> sleep-timer` from your local terminal.
  - [ ] Alternatively, manually fork `homebrew/homebrew-cask`, add your file, and open a PR.
- [ ] **Monitor & Merge:**
  - [ ] Fix any styling errors caught by the Homebrew CI bots.
  - [ ] Wait for maintainer approval. Once merged, users can install your app simply via `brew install --cask sleep-timer`.

---

## 📋 Custom Cask Template Reference

When you get to **Phase 3**, create a file named `Casks/sleep-timer.rb` in your repository. Use this structural layout as your starting template:

```ruby
cask "sleep-timer" do
  version "0.9.0"
  sha256 "PASTE_YOUR_RELEASE_ZIP_SHA256_HASH_HERE"

  # Replace with your actual GitHub username and repo name
  url "https://github.com{version}/sleep-timer.zip"
  name "Mac Sleep Timer"
  desc "Menubar app to pause media and sleep your Mac, featuring a YOLO anti-sleep toggle"
  homepage "https://github.com"

  # Assumes your build step outputs a zipped standalone .app bundle
  app "Sleep Timer.app"

  zap trash: [
    "~/Library/Application Support/Sleep Timer",
    "~/Library/Preferences/com.yourusername.sleeptimer.plist",
  ]
end
```

---

## 💡 Quick Tips for Success

- **The "Yolo" Flag Privilege:** Standard user accounts can run `caffeinate`. However, forcing a Mac to sleep (`pmset`) can sometimes require admin privileges depending on the user's macOS security configuration. Test your Swift app execution carefully on a standard non-admin account to make sure it doesn't quietly fail.
- **Media Controls:** macOS heavily sandboxes apps. Your Swift app will need `Accessibility` or `Automation` permissions granted in System Settings if it uses AppleScript (`osascript`) to talk to system events or other media applications. Include a small setup wizard or warning in your UI to guide users through enabling this.
