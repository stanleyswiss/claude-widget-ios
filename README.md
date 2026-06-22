# Claude Usage Widget (iOS)

A native iOS home-screen and lock-screen widget showing your Claude Pro/Max
usage — the **5-hour** and **7-day** rolling windows — as a utilization
percentage plus a live countdown to each reset.

An "Apple version" of the Android
[utaysi/claude-usage-widget](https://github.com/utaysi/claude-usage-widget),
built for personal sideloading (not the App Store).

## How it works

- A SwiftUI **host app** keeps a `WKWebView` logged into `claude.ai` and fetches
  usage by running `fetch('/api/organizations/{org}/usage')` **inside the page**,
  so your httpOnly `sessionKey` + `cf_clearance` and Cloudflare are handled by
  the browser itself.
- The result is cached to a shared **App Group**; a **WidgetKit extension** reads
  the cache and renders it (small, medium, lock-screen rectangular + circular).
- Refresh happens on app open and via a best-effort `BGAppRefreshTask`; reset
  countdowns tick live on the widget.

## Appearance & refresh

- **Accent color:** pick your widget color in **Settings → Appearance** (presets
  + a custom color picker; default orange). Bars and percentages still turn
  **red at 90%+** as a near-limit warning, whatever color you choose.
  (Lock-screen accessory widgets are tinted by iOS, so color is limited there.)
- **Background refresh:** on a successful in-app fetch the app stores your
  claude.ai cookies in the **Keychain**, so a `BGAppRefreshTask` can refresh
  usage with a plain `URLSession` while the app is suspended. This is
  **best-effort** — iOS schedules it on its own cadence (typically a few times a
  day), and it only succeeds while Cloudflare's clearance cookie is still valid.
  Tapping the widget (which opens the app) remains the always-reliable refresh.

## Project layout

```
Core/        Swift package — pure logic (models, parsing, store, fetcher), 34 unit tests
App/         SwiftUI host app (login, WebView fetch, background refresh, settings)
Widget/      WidgetKit extension (timeline provider + views)
project.yml  XcodeGen spec (run `xcodegen generate` to (re)create the .xcodeproj)
docs/        Design spec and implementation plan
```

## Build & run

Requires macOS + Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
cd Core && swift test        # run the unit tests
cd .. && xcodegen generate   # generate ClaudeUsage.xcodeproj
open ClaudeUsage.xcodeproj
```

In Xcode: set your signing **Team** on both targets (`ClaudeUsage` and
`ClaudeUsageWidgetExtension`), confirm the App Group
`group.com.stanleyswiss.claudeusage` is enabled on both, run on your iPhone, log in to
Claude once, then add the widgets from the home-screen / lock-screen gallery.

To use a different bundle id, change `com.stanleyswiss.*` in `project.yml`, the two
`*.entitlements` files, and `Core/Sources/ClaudeUsageCore/Constants.swift`, then
re-run `xcodegen generate`.

## Login note

Claude sign-in happens in an embedded web view. Use **email** or **Continue with
Apple** — Google blocks OAuth inside embedded web views (`disallowed_useragent`),
so the "Continue with Google" button won't complete there.

## Status

v1 is complete and validated on device — the app and the home/lock-screen widgets
show live 5H/7D usage. See `docs/superpowers/` for the full spec and plan.
