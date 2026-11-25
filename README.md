# FocusFeed

An iPhone app that opens Instagram's website full screen and keeps it focused:

- Home feed and DMs (send and receive) work as normal.
- The Reels tab and the reels in your feed are hidden.
- A reel someone sends you plays, but you can't swipe to the next one.
- No "Open in app" prompts, and no Safari address bar.

Filters live in `Sources/FilterScript.swift` (settings at the top of the script).

## Install with SideStore (automatic updates)

Every push to `main` builds the app on GitHub and publishes it as a release.
In SideStore, go to **Sources → +** and add:

```
https://github.com/YaqoubYousef/FocusFeed/releases/latest/download/source.json
```

Then install FocusFeed from that source. New pushes show up as updates in SideStore.

## 1. Build the app (free, on GitHub)

iOS apps can only be compiled on a Mac, so GitHub's Mac machines build it for you.

1. Create a GitHub repository and push this folder to its `main` branch.
2. Open the repository's **Actions** tab. The **Build IPA** run starts on every push
   (or press **Run workflow**).
3. When it finishes (about 5 minutes), download **FocusFeed-ipa** from the run's page and unzip it
   to get `FocusFeed.ipa`.

A public repository has unlimited free Actions minutes. A private one has a free monthly allowance,
which is enough for occasional builds.

## 2. Install it on your iPhone (free Apple ID, works from Linux)

1. Install **Sideloader** (https://github.com/Dadoum/Sideloader), which runs on Linux, plus
   `usbmuxd` from your distro's packages.
2. Connect the iPhone by USB and tap **Trust** on the phone.
3. In Sideloader, sign in with your Apple ID and install `FocusFeed.ipa`.
4. On the iPhone:
   - **Settings → Privacy & Security → Developer Mode → On** (the phone restarts).
   - **Settings → General → VPN & Device Management** → your Apple ID → **Trust**.

With a free Apple ID the app **stops opening after 7 days**. Re-install it with Sideloader
(your Instagram login is kept). A paid Apple Developer account ($99/year) extends this to one year.

## DM notifications

FocusFeed checks your inbox in the background and notifies you about new messages
(tap one to open that conversation). To make it work:

- Allow notifications when the app asks.
- **Settings → Apps → FocusFeed → Background App Refresh → On**.
- Don't swipe FocusFeed away in the app switcher; iOS won't wake an app you've closed that way.

iOS decides when checks run, usually every 15 minutes to a few hours, more often if you
open the app regularly. Low Power Mode pauses them.
