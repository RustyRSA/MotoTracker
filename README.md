# MotoTracker

A free, private motorbike performance tracker for iOS 16. Think RaceChrono/Dragy-lite: it records your route via GPS, your speed at every moment, timed acceleration runs, lean angle, G-force, and hard braking. All data stays on your phone.

Built for iPhone 14 Pro on iOS 16.3.1, installed permanently via **TrollStore** — no Mac, no paid developer account.

## Features

- **Live dashboard** — big speedometer, distance, timer, top speed, live lean angle and G readout, live map.
- **Timed runs** — detected automatically anywhere in a ride. km/h mode: 0–100, 0–200, 60–120, 100–200 km/h, 400 m. mph mode: 0–30, 0–60, 20–80, 60–130 mph, 1/8 + 1/4 mile (with trap speed). Set follows the units setting.
- **Routes with personal bests** — rides that follow the same road (same start, end, and path) are grouped automatically. Each route shows your PB time, best top speed, and every attempt with its delta to the PB.
- **Speed-gradient route line** — green = slow, red = fast; orange pins where you braked hard (> 3 m/s²).
- **Speed graph** — per ride, drag across it and a marker shows where on the map you were.
- **Lean angle & G-force** — estimated from GPS (turn rate + speed change), so phone mounting doesn't matter. Max lean / max accel g / max brake g per ride.
- **Records screen** — all-time best for every timed run, top speed ever, max lean, max G, longest ride, totals.
- **GPX export** — share button on any ride exports a GPX file for other apps.
- **Auto-record (optional)** — Life360-style: enable it in Settings and the app wakes on cell-tower movement, starts recording when it sees sustained riding speed, and saves the ride after 3 minutes stationary. Near-zero battery while parked because GPS is off until you actually move. Needs location set to "Always"; it can't tell bike from car, so delete trips you don't want.

## How to build the IPA (no Mac needed)

GitHub's free build servers compile the app for you.

1. **Create a repo.** On github.com, click **New repository**. Name it anything (e.g. `MotoTracker`). Public repos get unlimited free build minutes; private repos get 2000/month (one build uses ~10).
2. **Upload these files.** On the repo page: **Add file → Upload files**, then drag the *contents* of this folder in (the `MotoTracker` source folder, `project.yml`, this README). Folder structure must be preserved.
3. **Add the workflow file.** GitHub's drag-and-drop sometimes skips hidden `.github` folders, so do this one manually: **Add file → Create new file**, type the filename as `.github/workflows/build.yml`, and paste in the contents of that file from this project. Commit.
4. **Wait for the build.** Go to the **Actions** tab. A "Build MotoTracker IPA" run starts automatically (if Actions asks for permission first, enable it and re-run). Takes ~5 minutes.
5. **Download the IPA.** Open the finished run and download the **MotoTracker-IPA** artifact. It downloads as a zip containing `MotoTracker.ipa`.

## How to install with TrollStore

Your device (iPhone 14 Pro, iOS 16.3.1, jailbroken) is fully supported — TrollStore works on iOS 15.0–16.6.1.

1. **Install TrollStore** (skip if you have it): since you're jailbroken, open your package manager (Sileo/Zebra), add the repo `https://repo.opa334.dev`, and install **TrollStore Helper**. Open the helper app and tap **Install TrollStore**. Full guide: https://ios.cfw.guide/installing-trollstore/
2. **Get the IPA onto your phone.** Easiest: log in to github.com in Safari on your phone and download the artifact there. Unzip it in the Files app (tap the zip) to get `MotoTracker.ipa`.
3. **Install.** Long-press `MotoTracker.ipa` → Share → **TrollStore**. TrollStore installs it permanently — it never expires.
4. **First launch:** allow location access. "While Using" is enough for manual recording; choose "Always" if you turn on auto-record in Settings.

## Accuracy notes

- The iPhone GPS updates ~1×/second; run times are interpolated between fixes, giving roughly ±0.2 s accuracy — same class as other phone-based timers. A dedicated 10 Hz GPS box would be needed to do better.
- Lean angle is estimated from cornering physics (speed × turn rate), not the phone's tilt — it reflects the ideal lean for the corner, and works from your pocket.
- Route PB uses total ride time from start to stop, so stop the recording at the same place for fair comparisons.

## Tweaking

- Hard-braking sensitivity: `brakingThreshold` in `RideRecorder.swift` (m/s², default 3).
- Route matching tolerance: endpoint radius (250 m) and path deviation (120 m) in `RouteMatcher.swift`.
- Push any change to GitHub and it rebuilds the IPA automatically.

Timed runs and top-speed features are meant for closed roads and track days. Ride safe.
