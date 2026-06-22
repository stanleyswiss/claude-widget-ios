# Design: Accent color + best-effort background refresh

Date: 2026-06-22
Project: claude-widget-ios (native iOS SwiftUI + WidgetKit port of utaysi/claude-usage-widget)
Status: approved, ready for implementation

## Context

v1 is shipped and validated on device. Architecture: the app signs into
claude.ai in a `WKWebView` and fetches `/api/organizations/{org}/usage` by
running `fetch()` inside the page; the parsed `UsageSnapshot` is written to a
shared App Group (`group.com.stanleyswiss.claudeusage`); the widget extension
only *reads* that snapshot. Core logic (parsing, classification, formatting,
shared store) lives in the Foundation-only `ClaudeUsageCore` Swift package with
25 unit tests.

After a day of real use, two improvements were requested:

1. The bars/percent are a green→orange→red traffic-light keyed on utilization
   (`UsageLevel`). The user wants a chosen accent color (default orange, to
   match the Android version), configurable in-app.
2. The widget only refreshes when tapped (which opens the app and triggers the
   visible-webview fetch). The user wants automatic refresh if iOS allows it.

This work is a clean checkpoint **before** opening the upstream `ios/` PR for
the maintainer (utaysi), who has accepted option 1 (monorepo, MIT at root,
credited).

## Feature A — Accent color (picker, default orange, red near-limit)

### Behavior
- A single user-chosen accent color drives the **bar fill** and **percent text**
  across home-screen widgets (small/medium) and the in-app rows.
- Default accent: orange (`#FF9500`); the user can fine-tune to the Android
  shade via the picker.
- **Red safety override is retained:** at utilization **≥ 90%** the bar/text
  render **red** regardless of the chosen accent. So `0–89% → accent`,
  `≥ 90% → red`. This preserves the at-a-glance "almost out" signal.
- Lock-screen accessory widgets (`accessoryRectangular`/`accessoryCircular`)
  are tinted monochrome by iOS; custom color is limited there by the OS. This
  is a platform constraint, documented, not worked around.

### Storage
- Add `accentColorHex: String?` to `SharedStore` (key `usage.accentColorHex`),
  stored in the App Group `UserDefaults`. It is not sensitive. `nil` ⇒ default
  orange.

### Color plumbing
- New SwiftUI file `Shared/UsageTint.swift`, compiled into **both** the App and
  Widget targets (added to both target source lists in `project.yml`). Contains:
  - `extension Color { init?(usageHex:) ; func toHex() -> String? }`
    (hex ⇄ Color via `UIColor`).
  - `UsageTint.defaultAccentHex = "#FF9500"`.
  - `UsageTint.presets`: ~6 named swatch hexes (orange default + a few others).
  - `UsageTint.resolve(utilization:hex:) -> Color`: returns `.red` when
    `utilization >= 90`, otherwise `Color(usageHex: hex ?? default) ?? .orange`.
- This single helper replaces the duplicated `levelColor()`
  (`Widget/UsageWidgetView.swift:5`) and `WindowRow.color`
  (`App/RootView.swift:71`).

### UI
- New "Appearance" section in `SettingsView`: a row of preset swatches plus a
  native `ColorPicker` for a custom color. Changing it writes the hex to the
  store and calls `WidgetCenter.shared.reloadAllTimelines()`.
- `AppModel` gains `@Published var accentColorHex` mirrored to the store, with a
  setter that persists and reloads widgets.
- The widget reads the hex in `UsageProvider.currentEntry()` and carries it on
  `UsageEntry` (`accentHex: String?`); the views call `UsageTint.resolve(...)`.

## Feature B — Best-effort background refresh (URLSession + harvested cookies)

### Why the current background task fails
`BackgroundRefresh.handle` drives `UsageService.refresh()`, which uses the
`WKWebView`. WebKit is suspended in the background, so the headless fetch does
not run. The fix is to do a pure-network call that needs no live WebKit.

### Approach
1. **Harvest on foreground success.** After a successful `UsageService.refresh()`
   (visible webview, Cloudflare already cleared), copy the claude.ai cookies
   from `WKWebsiteDataStore.default().httpCookieStore` and capture the page
   `navigator.userAgent`. Persist both to the **Keychain**
   (`kSecAttrAccessibleAfterFirstUnlock`, so a background task can read them
   while the device is locked). Cookies are sensitive: Keychain only, never
   `UserDefaults`, never logged.
2. **Background fetch.** `BGAppRefreshTask` runs in the *app* process. Read
   `orgId` from `SharedStore` and cookies/UA from the Keychain, build a
   `URLSession` request to `https://claude.ai/api/organizations/{org}/usage`
   with the same `Cookie` header and `User-Agent` (Cloudflare binds clearance to
   the UA), plus `Accept: application/json` and `Referer: https://claude.ai/`.
3. **Classify outcomes** by reusing the existing
   `UsageHTTP.classify` + `UsageParser.parse`:
   - `success` → save snapshot, `authState = .ok`, reload widgets,
     `setTaskCompleted(success: true)`.
   - `.transient` (Cloudflare challenge / clearance lapsed / IO) → **keep the
     last snapshot**, do **not** change `authState` (avoids a false
     "tap to log in"), `setTaskCompleted(success: false)`. The user re-clears
     Cloudflare automatically next time they open the app.
   - `.needsLogin` (genuine redirect to `/login`) → `authState = .needsLogin`,
     reload widgets (so the widget shows the login prompt), complete `false`.
4. **Scheduling** unchanged: `schedule()` chains the next request
   (`earliestBeginDate` +15 min) and is also submitted on app-background.

### New testable Core code
- `Core/Sources/ClaudeUsageCore/UsageRemoteFetcher.swift` (Foundation only):
  - `buildUsageRequest(orgId:cookieHeader:userAgent:) -> URLRequest` — pure,
    unit-tested for URL, `Cookie`, `User-Agent`, `Accept` headers.
  - `fetchUsage(session:orgId:cookieHeader:userAgent:now:) async -> Result`
    using an injectable `URLSession`, returning the same classified/parsed
    outcome enum shape used elsewhere. Unit-tested with a mocked `URLProtocol`
    (success + 401/needsLogin + Cloudflare-403/transient paths).
- The BGTask wiring and Keychain access live in `App/` and stay thin.
- New `App/Keychain.swift`: a minimal generic-password wrapper
  (save/load/delete `Data` for a service+account).

### Expectations (honest, unchanged platform reality)
iOS schedules `BGAppRefreshTask` opportunistically — typically a few times a
day, on its own cadence keyed to app usage and battery, not a fixed interval —
and the network call only succeeds while the Cloudflare clearance cookie is
still valid. This is a best-effort bonus layered on top of tap-to-refresh, not a
guaranteed periodic refresh (which iOS does not offer for an app like this).

## Scope guardrails
- No new entitlements: the BG task identifier is already in `Info.plist`;
  in-app Keychain use needs none.
- Re-run `xcodegen generate` after adding the three new files
  (`Shared/UsageTint.swift`, `Core/.../UsageRemoteFetcher.swift`,
  `App/Keychain.swift`).
- All 25 existing tests stay green; add ~3–4 new Core tests for the fetcher.
- Build/test on this Mac requires
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Out of scope (deferred)
- Server-push refresh (would need a backend).
- Multi-org picker, configurable thresholds (already deferred in v1).
