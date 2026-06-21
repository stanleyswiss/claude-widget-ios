# Claude Usage Widget for iPhone — Design Spec

- **Date:** 2026-06-21
- **Status:** Approved (ready for implementation planning)
- **Author:** Stanley + Claude
- **Inspiration:** [utaysi/claude-usage-widget](https://github.com/utaysi/claude-usage-widget) (Android / Kotlin / Glance)

## 1. Goal

A native iOS home-screen and lock-screen widget that shows my Claude Pro/Max
subscription usage — the **5-hour** and **7-day** rolling windows — as a
utilization percentage plus a live countdown to each reset. Sideloaded to my own
iPhone, signed with my paid Apple Developer account. **Not** published to the App
Store.

It is an "Apple version" of the referenced Android widget: same data source, same
two windows, reimagined natively with WidgetKit + SwiftUI.

## 2. Non-goals

- No App Store / TestFlight distribution (personal sideload only).
- No multi-account or multi-org switching UI (auto-pick the primary org; v1).
- No historical charts or analytics — point-in-time usage only.
- No Apple Watch / macOS / iPad-specific layouts in v1 (iPhone only).

## 3. Key decisions (settled during brainstorming)

| Topic | Decision |
|---|---|
| Runtime | **Native WidgetKit (Swift/SwiftUI)** — host app + widget extension |
| Data / auth | **In-WebView `fetch`** from a logged-in `WKWebView` (most robust vs Cloudflare) |
| Signing | Paid **Apple Developer** account, sideload signed build from Xcode |
| Min iOS | **iOS 16** (`callAsyncJavaScript`, lock-screen accessories, modern WidgetKit) |
| Widget sizes (v1) | `systemSmall`, `systemMedium`, **and** lock-screen `accessoryRectangular` + `accessoryCircular` |
| `URLSession` background fallback | **Deferred to Phase 2** (keep v1 lean) |

## 4. Background — the data source

Reverse-engineered from the original repo. Both calls are to `https://claude.ai`.

### Endpoints
- `GET /api/organizations` → JSON array of orgs. Pick the org whose
  `capabilities` array contains `chat` or `claude_ai`; use its `uuid` (fallback
  `id`). Single-org accounts: take `[0]`.
- `GET /api/organizations/{orgId}/usage` → usage JSON.

### Usage response shape (fields we consume)
```jsonc
{
  "five_hour": { "utilization": 62.0, "resets_at": "2026-06-21T18:00:00Z" },
  "seven_day": { "utilization": 38.0, "resets_at": "2026-06-25T09:00:00Z" }
}
```
- `utilization`: number, 0–100 (treat as Double; default 0).
- `resets_at`: ISO-8601 timestamp (parse to `Date`).

### Auth
- Cookies that matter: `sessionKey` (httpOnly), `cf_clearance`. Correct
  `User-Agent` also matters for Cloudflare.
- **In-WebView approach means we never harvest or send these manually.** A
  `fetch()` executed inside the logged-in claude.ai page is a genuine first-party
  request: the browser attaches `sessionKey` + `cf_clearance` + the real UA
  automatically, and Cloudflare is satisfied because the caller *is* the browser.

## 5. Architecture

One Xcode project, two targets, one shared App Group
(`group.<bundle>.usage`).

```
┌─────────────────────────────┐         ┌──────────────────────────────┐
│  ClaudeUsage (host app)      │         │  ClaudeUsageWidget (extension)│
│  - WKWebView login           │  App    │  - TimelineProvider (reads    │
│  - UsageService (JS fetch)   │  Group  │    cache only, no network)    │
│  - BackgroundRefresh (BGTask)│ ──────▶ │  - SwiftUI widget views       │
│  - Settings                  │ snapshot│  - live countdown text        │
└─────────────────────────────┘         └──────────────────────────────┘
            │  writes UsageSnapshot + orgId to App Group
            └──────────────────────────────────────────────▶
```

The widget extension **never** runs a `WKWebView` or network call (unreliable /
disallowed in extensions). All fetching is in the app; the widget renders the
last cached snapshot and reloads its timeline when the app signals new data.

## 6. Data layer

### Models (Shared, Codable)
```swift
struct UsageWindow {        // one of 5H / 1W
    var utilization: Double   // 0...100
    var resetsAt: Date
}
struct UsageSnapshot {
    var fiveHour: UsageWindow
    var sevenDay: UsageWindow
    var fetchedAt: Date
}
```

### UsageService (host app)
- Owns a single persistent `WKWebView` backed by `WKWebsiteDataStore.default()`
  (cookies persist across launches).
- `refresh()` runs, via `callAsyncJavaScript` inside the claude.ai page:
  1. If org id unknown: `fetch('/api/organizations', {credentials:'include'})`
     → status + body string; parse, choose org, cache id.
  2. `fetch('/api/organizations/{org}/usage', {credentials:'include'})`
     → status + body string; parse into `UsageSnapshot`.
- The JS returns an object `{status, body}` so Swift can branch on HTTP status
  without following redirects.

### Result state machine (mirrors original `FetchResult`)
| Condition | Result | App behavior |
|---|---|---|
| `status == 200`, parses | **Success** | save snapshot, reload widget |
| `status == 401`, redirect to `/login`, or body is login HTML | **NeedsLogin** | mark state, widget shows "Tap to log in" |
| `status == 403/503` or body contains `"Just a moment"` | **Transient (cloudflare)** | keep last snapshot; WebView is already the solver, so just retry next cycle |
| network / JS error / parse fail | **Transient** | keep last snapshot |

Last-good snapshot is **always** retained on any non-success.

### SharedStore (App Group)
- Reads/writes `UsageSnapshot` (JSON) + cached `orgId` + `authState` to the App
  Group container (file or shared `UserDefaults(suiteName:)`).
- The only data we persist ourselves. No secrets — the session lives in
  `WKWebsiteDataStore`.

## 7. Login flow

1. First launch (or `NeedsLogin`): app shows `LoginWebView` at
   `https://claude.ai/login`.
2. User logs in normally (handles Cloudflare in-page).
3. App detects logged-in state (successful `/api/organizations` call), dismisses
   the login view, performs first usage fetch, writes snapshot, reloads widget.
4. Session persists for weeks. On expiry, the next fetch returns NeedsLogin and
   the app re-presents the login WebView.

## 8. Refresh strategy

- **Foreground:** refresh on app launch + a manual "Refresh now" button →
  `UsageService.refresh()` → write App Group → `WidgetCenter.shared.reloadAllTimelines()`.
- **Background:** `BGAppRefreshTask` (id in `BGTaskSchedulerPermittedIdentifiers`)
  scheduled ~15 min out, rescheduled on each run; runs `refresh()` and reloads.
- **Widget timeline:** `TimelineProvider` reads cache, emits a "now" entry and
  requests reload ~15 min later (`.after`). Live countdowns fill the gap.
- **Honest limitation:** iOS throttles background tasks and widget reloads
  (~40–70 reloads/day), so 15 min is best-effort. The widget always shows
  last-good data + a ticking countdown and refreshes instantly when the app
  opens. Phase 2 may add a harvested-cookie `URLSession` background path for
  lighter-weight background fetches if needed.

## 9. Widget UI

Two windows — **5H** and **1W** — each: label, utilization %, progress bar/ring,
and a **live countdown** to `resets_at` via `Text(timerInterval:)` / relative
style (ticks without consuming reload budget).

```
 systemSmall                systemMedium
┌────────────────┐        ┌──────────────────────────────┐
│ ✳ CLAUDE       │        │ ✳ CLAUDE USAGE      23m ago  │
│ 5H ▓▓▓▓▓░ 62%  │        │ 5H ▓▓▓▓▓▓░░░ 62%  resets 2h14m│
│ 1W ▓▓▓░░░ 38%  │        │ 1W ▓▓▓░░░░░ 38%  resets 4d 6h │
└────────────────┘        └──────────────────────────────┘

 accessoryRectangular (lock)      accessoryCircular (lock)
┌──────────────────────┐          ╭──────╮
│ 5H 62% · 1W 38%      │          │ 5H   │   ring = 5H utilization
│ resets 2h14m         │          │ 62%  │
└──────────────────────┘          ╰──────╯
```

- **Sizes (v1):** `systemSmall`, `systemMedium`, `accessoryRectangular`,
  `accessoryCircular`.
- **Colors:** utilization-driven (calm → amber → red near 100%), Claude coral
  accent, full light/dark; lock-screen accessories respect the system vibrant
  rendering mode.
- **States:** normal · stale (dim + "updated Nm ago") · "Tap to log in"
  (NeedsLogin) · placeholder (before first fetch).
- **Tap:** deep-links into the host app and triggers a fresh fetch.

## 10. Project structure

```
ClaudeUsage.xcodeproj
  ClaudeUsage/         (app target)
    ClaudeUsageApp.swift
    RootView.swift
    LoginWebView.swift          (WKWebView wrapper)
    SettingsView.swift
    UsageService.swift          (WKWebView + callAsyncJavaScript fetch)
    BackgroundRefresh.swift     (BGTaskScheduler)
  ClaudeUsageWidget/   (widget extension target)
    ClaudeUsageWidget.swift     (Widget + TimelineProvider + entry)
    WidgetViews.swift           (small / medium / lock-screen SwiftUI)
  Shared/              (member of BOTH targets)
    UsageSnapshot.swift         (Codable models + parsing)
    SharedStore.swift           (App Group read/write)
    Formatting.swift            (%, countdown, color ramp)
  ClaudeUsage.entitlements
  ClaudeUsageWidget.entitlements   (same App Group)
  Info.plist                       (BGTaskSchedulerPermittedIdentifiers)
```

## 11. Build & sideload

1. Open `ClaudeUsage.xcodeproj` in Xcode.
2. Set **Team** to the paid Apple Developer account on both targets.
3. Bundle ids: `com.<you>.claudeusage` (app) and
   `com.<you>.claudeusage.widget` (extension).
4. Enable the **App Group** `group.com.<you>.claudeusage.usage` on both targets.
5. Run on the connected iPhone; trust the developer profile if prompted.
6. Open the app, log in to claude.ai once.
7. Add the widget (home screen and/or lock screen) from the gallery.

## 12. Risks & open questions

- **Background WebView reliability:** iOS may suspend WebView JS in the
  background, making `BGAppRefreshTask` fetches flaky. Mitigation: live countdown
  + instant foreground refresh; Phase 2 `URLSession` fallback if needed.
- **Endpoint drift:** the `/usage` schema is undocumented and may change.
  Parsing is defensive (default 0 / keep last-good) and isolated to
  `UsageSnapshot.parse` for a single point of repair.
- **Multi-org accounts:** v1 auto-picks the chat-capable org; a picker is a
  future enhancement if needed.

## 13. Success criteria

- After one in-app login, the home-screen widget shows correct 5H and 1W
  utilization % matching `claude.ai/settings/usage`.
- Countdown to each reset ticks live on the widget.
- Lock-screen rectangular + circular accessories render correctly in light/dark.
- Reopening the app refreshes the data and the widget updates.
- Session survives app relaunch without re-login (until real expiry).

## 14. Phase 2 (future, not in v1)

- Harvested-cookie `URLSession` background fetch path (Android-app approach) for
  more reliable background refresh.
- Multi-org picker.
- Configurable refresh interval / thresholds via widget configuration intent.
- Optional lock-screen-only minimal install.
