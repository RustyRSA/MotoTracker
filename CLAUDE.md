# MotoTracker

Free, private motorbike performance tracker (RaceChrono/Dragy-lite). SwiftUI, iOS 16.

## Hard constraints — do not break these

- **Target device:** iPhone 14 Pro on iOS **16.3.1**, jailbroken. Deployment target is iOS 16.0. Never use iOS 17+ APIs.
- **Install path is TrollStore, not the App Store.** The IPA must stay **unsigned**. Owner has no Mac and no paid developer account.
- **Build pipeline:** GitHub Actions (`.github/workflows/build.yml`, `runs-on: macos-15`) runs XcodeGen on `project.yml`, builds unsigned with xcodebuild, zips `Payload/` into `MotoTracker.ipa`, uploads as artifact. There is no checked-in `.xcodeproj` — edit `project.yml` instead.
- All ride data stays on-device (JSON in Documents). No servers, no analytics, no accounts.

## Architecture (all in `MotoTracker/`)

- `Models.swift` — `RidePoint` (lat/lon/speed/course/timestamp), `BrakingEvent`, `Ride`. Codable, persisted by `RideStore` to `Documents/rides.json`.
- `RideRecorder.swift` — CLLocationManager (1 Hz, `kCLLocationAccuracyBestForNavigation`). Manual start/stop plus auto-record: significant-location-change wake → 90 s GPS speed probe → auto-start at sustained ≥5 m/s → auto-stop+save after 180 s stationary. Hard braking = decel ≥ 3 m/s² (`brakingThreshold`).
- `Benchmarks.swift` — timed runs found anywhere in a ride, interpolated between 1 Hz fixes. Two sets, switched by the metric/imperial setting (`@AppStorage("useMetric")`): km/h set (0–100, 0–200, 60–120, 100–200, 400 m) and mph set (0–30, 0–60, 20–80, 60–130, 1/8 + 1/4 mile with trap speed).
- `Analysis.swift` — lean angle (split left/right by course-delta sign; clockwise = right) and longitudinal G derived **from GPS** (course rate × speed / speed delta), deliberately not from the accelerometer, so phone mounting doesn't matter.
- `RouteMatcher.swift` — groups rides on the same road: endpoints within 250 m, length within ±20–25%, mean deviation of 32-point resampled paths < 120 m. Route PB = lowest total duration.
- `RideMapView.swift` — MKMapView wrapper; `MKGradientPolylineRenderer` colored by speed relative to that ride's max (green→red), fixed `lineWidth = 5` screen points (road-scaled 0 ballooned when zoomed out), speeds smoothed with 3-point average. Orange markers = braking, blue marker = chart scrub position.
- `RideDetailView.swift` — map, numeric speed-color legend, stats, Swift Charts speed graph with drag-to-scrub linked to the map, benchmark results, GPX ShareLink.
- `RoutesView.swift`, `RecordsView.swift`, `RecordView.swift`, `RideListView.swift`, `SettingsView.swift` — the five tabs.
- `DemoRide.swift` — "Add demo rides" in Settings: fetches a real road path via MKDirections and plays a scripted speed profile along it (two attempts, one faster = PB). Needs network when tapped.
- `GPXExporter.swift` — GPX 1.1 export to a temp file.
- `ShareCards.swift` — local rider profile (name/bike in `@AppStorage("riderName"/"bikeName")`, edited in Settings) plus profile/route stat cards rendered to PNG with `ImageRenderer` and shared via ShareLink. Stage 1 of profiles: everything stays on-device.

## Gotchas learned the hard way

- Old macOS runner images fail with "future Xcode project file format" — keep `runs-on` current.
- `project.yml` and `.github/workflows/build.yml` look similar at a glance; they have been confused before. `project.yml` = XcodeGen app spec, `build.yml` = CI workflow.
- Location permission: "While Using" suffices for manual recording (background mode `location` is declared); auto-record needs "Always".
- GPS `speed` is invalid (< 0) on some fixes — always clamp with `max(0, speed)`; course invalid = -1, skip those pairs in lean math.
- Owner tests on-device only (no simulator). CI compiling green is the only automated check — be conservative with API availability.

## Conventions

- Internal units are SI (m/s, meters, seconds); convert only in the UI via `Units.swift`.
- Single-purpose files, no external dependencies, no SPM packages — keep it that way unless asked.
- Version bumps: `CFBundleShortVersionString`/`CFBundleVersion` in `project.yml`.
