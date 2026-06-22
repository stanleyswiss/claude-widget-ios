# Accent Color + Best-Effort Background Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app accent-color picker (default orange, red ≥90% override) and a best-effort background refresh that updates usage via `URLSession` with harvested cookies (no WebKit in the background).

**Architecture:** Pure logic lands in the Foundation-only `ClaudeUsageCore` package (testable). SwiftUI color resolution lives in one `Shared/` file compiled into both the App and Widget targets. The background path reads cookies/UA harvested into the Keychain on a successful foreground fetch, then calls `URLSession` directly — avoiding the suspended WebKit problem.

**Tech Stack:** Swift 5, SwiftUI, WidgetKit, BackgroundTasks, WebKit (foreground only), Keychain Services, XcodeGen, XCTest.

## Global Constraints

- iOS deployment target: **16.0** (no API newer than iOS 16 without `if #available`).
- `SWIFT_VERSION` 5.0; package `swift-tools-version:5.9`.
- Build/test on this Mac REQUIRE the env prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the active `xcode-select` is CommandLineTools, which lacks XCTest/simulators).
- App Group: `group.com.stanleyswiss.claudeusage`. Bundle ids `com.stanleyswiss.claudeusage` / `.widget`.
- Targets (XcodeGen): app `ClaudeUsage` (sources `[App]`), extension `ClaudeUsageWidgetExtension` (sources `[Widget]`). Re-run `xcodegen generate` after adding/removing files; the `.xcodeproj` is git-ignored.
- Core stays Foundation-only (no SwiftUI/UIKit imports) so its tests run on the macOS host.
- Never log cookies/tokens. Cookies live in Keychain only, never `UserDefaults`.
- Default accent hex: `#FF9500`. Red override threshold: utilization `>= 90`.
- Commit after each task with `[type] subject` and the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

Core test command (whole suite):
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core`

App build check (no device needed):
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -destination 'generic/platform=iOS Simulator' build`

---

### Task 1: SharedStore — `accentColorHex`

**Files:**
- Modify: `Core/Sources/ClaudeUsageCore/SharedStore.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/SharedStoreTests.swift`

**Interfaces:**
- Consumes: existing `SharedStore(defaults:)`.
- Produces: `var SharedStore.accentColorHex: String?` (get/nonmutating set), key `"usage.accentColorHex"`.

- [ ] **Step 1: Write the failing test** — append to `SharedStoreTests.swift`:

```swift
    func testAccentColorHexRoundTrip() {
        let store = SharedStore(defaults: makeDefaults())
        XCTAssertNil(store.accentColorHex)
        store.accentColorHex = "#FF9500"
        XCTAssertEqual(store.accentColorHex, "#FF9500")
    }
```

- [ ] **Step 2: Run test, verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core --filter SharedStoreTests`
Expected: FAIL — `value of type 'SharedStore' has no member 'accentColorHex'`.

- [ ] **Step 3: Implement** — in `SharedStore.swift` add the key beside the others and the property after `authState`:

```swift
    public static let accentColorHexKey = "usage.accentColorHex"
```

```swift
    public var accentColorHex: String? {
        get { defaults.string(forKey: Self.accentColorHexKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.accentColorHexKey) }
    }
```

- [ ] **Step 4: Run test, verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core --filter SharedStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/ClaudeUsageCore/SharedStore.swift Core/Tests/ClaudeUsageCoreTests/SharedStoreTests.swift
git commit -m "[feat] SharedStore: persist accentColorHex in app group

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Core — `HexColor` (pure hex parse/format)

**Files:**
- Create: `Core/Sources/ClaudeUsageCore/HexColor.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/HexColorTests.swift`

**Interfaces:**
- Produces:
  - `HexColor.parse(_ hex: String) -> (r: Double, g: Double, b: Double)?` — accepts `#RRGGBB` or `RRGGBB`, returns 0...1 components, `nil` on malformed input.
  - `HexColor.string(r: Double, g: Double, b: Double) -> String` — returns `#RRGGBB` uppercase, clamping 0...1.

- [ ] **Step 1: Write the failing test** — `HexColorTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageCore

final class HexColorTests: XCTestCase {
    func testParseWithHash() {
        let c = HexColor.parse("#FF9500")
        XCTAssertEqual(c?.r ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(c?.g ?? -1, 0.584, accuracy: 0.01)
        XCTAssertEqual(c?.b ?? -1, 0.0, accuracy: 0.001)
    }

    func testParseWithoutHash() {
        XCTAssertNotNil(HexColor.parse("00FF00"))
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(HexColor.parse("nope"))
        XCTAssertNil(HexColor.parse("#FFF"))
    }

    func testRoundTrip() {
        XCTAssertEqual(HexColor.string(r: 1, g: 0.584, b: 0), "#FF9500")
    }
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core --filter HexColorTests`
Expected: FAIL — `cannot find 'HexColor' in scope`.

- [ ] **Step 3: Implement** — `HexColor.swift`:

```swift
import Foundation

/// Pure hex ⇄ RGB helpers (no SwiftUI/UIKit) so logic stays host-testable.
public enum HexColor {
    /// Parses `#RRGGBB` or `RRGGBB`; returns 0...1 components, or nil if malformed.
    public static func parse(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255.0,
                Double((value >> 8) & 0xFF) / 255.0,
                Double(value & 0xFF) / 255.0)
    }

    /// Formats 0...1 components as `#RRGGBB` (uppercase).
    public static func string(r: Double, g: Double, b: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core --filter HexColorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/ClaudeUsageCore/HexColor.swift Core/Tests/ClaudeUsageCoreTests/HexColorTests.swift
git commit -m "[feat] Core: HexColor parse/format helpers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Core — `UsageRemoteFetcher` (URLSession path)

**Files:**
- Create: `Core/Sources/ClaudeUsageCore/UsageRemoteFetcher.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/UsageRemoteFetcherTests.swift`

**Interfaces:**
- Consumes: `ClaudeAPI.base`, `ClaudeAPI.usagePath(org:)`, `UsageHTTP.classify`, `UsageParser.parse`, `UsageSnapshot`.
- Produces:
  - `enum UsageFetchOutcome: Equatable { case success(UsageSnapshot); case needsLogin; case transient(String) }`
  - `UsageRemoteFetcher.buildUsageRequest(orgId:cookieHeader:userAgent:) -> URLRequest`
  - `UsageRemoteFetcher.fetchUsage(session:orgId:cookieHeader:userAgent:now:) async -> UsageFetchOutcome`

- [ ] **Step 1: Write the failing test** — `UsageRemoteFetcherTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageCore

/// Intercepts URLSession requests so fetchUsage can be tested without a network.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        MockURLProtocol.lastRequest = request
        let resp = HTTPURLResponse(url: request.url!, statusCode: MockURLProtocol.status,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class UsageRemoteFetcherTests: XCTestCase {
    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    func testBuildRequestSetsHeadersAndURL() {
        let req = UsageRemoteFetcher.buildUsageRequest(
            orgId: "org-1", cookieHeader: "a=b; c=d", userAgent: "UA/1.0")
        XCTAssertEqual(req.url?.absoluteString, "https://claude.ai/api/organizations/org-1/usage")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Cookie"), "a=b; c=d")
        XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"), "UA/1.0")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testFetchSuccessParsesSnapshot() async {
        MockURLProtocol.status = 200
        MockURLProtocol.body = Data("""
        {"five_hour":{"utilization":12.5,"resets_at":"2026-06-22T18:00:00Z"},
         "seven_day":{"utilization":20,"resets_at":"2026-06-28T00:00:00Z"}}
        """.utf8)
        let out = await UsageRemoteFetcher.fetchUsage(
            session: session(), orgId: "o", cookieHeader: "x=y", userAgent: "UA", now: Date())
        guard case .success(let snap) = out else { return XCTFail("expected success, got \(out)") }
        XCTAssertEqual(snap.fiveHour.utilization, 12.5, accuracy: 0.001)
    }

    func testFetch401IsNeedsLogin() async {
        MockURLProtocol.status = 401
        MockURLProtocol.body = Data()
        let out = await UsageRemoteFetcher.fetchUsage(
            session: session(), orgId: "o", cookieHeader: "x=y", userAgent: "UA", now: Date())
        XCTAssertEqual(out, .needsLogin)
    }

    func testFetch403IsTransientCloudflare() async {
        MockURLProtocol.status = 403
        MockURLProtocol.body = Data("Just a moment".utf8)
        let out = await UsageRemoteFetcher.fetchUsage(
            session: session(), orgId: "o", cookieHeader: "x=y", userAgent: "UA", now: Date())
        XCTAssertEqual(out, .transient("cloudflare"))
    }
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core --filter UsageRemoteFetcherTests`
Expected: FAIL — `cannot find 'UsageRemoteFetcher' in scope`.

- [ ] **Step 3: Implement** — `UsageRemoteFetcher.swift`:

```swift
import Foundation

public enum UsageFetchOutcome: Equatable {
    case success(UsageSnapshot)
    case needsLogin
    case transient(String)
}

/// Cookie-based usage fetch for background refresh — no WebKit, so it runs when
/// the app is suspended. Reuses UsageHTTP.classify + UsageParser.parse.
public enum UsageRemoteFetcher {
    public static func buildUsageRequest(orgId: String,
                                         cookieHeader: String,
                                         userAgent: String) -> URLRequest {
        var req = URLRequest(url: URL(string: ClaudeAPI.base + ClaudeAPI.usagePath(org: orgId))!)
        req.httpMethod = "GET"
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(ClaudeAPI.base + "/", forHTTPHeaderField: "Referer")
        return req
    }

    public static func fetchUsage(session: URLSession,
                                  orgId: String,
                                  cookieHeader: String,
                                  userAgent: String,
                                  now: Date) async -> UsageFetchOutcome {
        let req = buildUsageRequest(orgId: orgId, cookieHeader: cookieHeader, userAgent: userAgent)
        do {
            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let toLogin = http?.url?.path.contains("/login") ?? false
            let body = String(decoding: data, as: UTF8.self)
            switch UsageHTTP.classify(status: status, redirectedToLogin: toLogin, body: body) {
            case .needsLogin:
                return .needsLogin
            case .transient(let why):
                return .transient(why)
            case .success:
                do { return .success(try UsageParser.parse(data, now: now)) }
                catch { return .transient("parse") }
            }
        } catch {
            return .transient("io")
        }
    }
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core --filter UsageRemoteFetcherTests`
Expected: PASS (all 4).

- [ ] **Step 5: Run the FULL Core suite to confirm no regressions**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core`
Expected: PASS — previous 25 plus the new tests.

- [ ] **Step 6: Commit**

```bash
git add Core/Sources/ClaudeUsageCore/UsageRemoteFetcher.swift Core/Tests/ClaudeUsageCoreTests/UsageRemoteFetcherTests.swift
git commit -m "[feat] Core: UsageRemoteFetcher cookie-based URLSession fetch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `Shared/UsageTint.swift` + wire into both targets

**Files:**
- Create: `Shared/UsageTint.swift`
- Modify: `project.yml` (add `Shared` to both targets' `sources`)
- Then: `xcodegen generate`

**Interfaces:**
- Consumes: `HexColor`.
- Produces (SwiftUI):
  - `UsageTint.defaultAccentHex: String` = `"#FF9500"`
  - `UsageTint.presets: [String]`
  - `UsageTint.resolve(utilization: Double, hex: String?) -> Color`
  - `extension Color { init?(usageHex: String); func toHex() -> String? }`

- [ ] **Step 1: Create `Shared/UsageTint.swift`**

```swift
import SwiftUI
import ClaudeUsageCore

enum UsageTint {
    static let defaultAccentHex = "#FF9500"

    /// Preset swatches offered in Settings (default orange first).
    static let presets = ["#FF9500", "#FF5A1F", "#34C759", "#0A84FF", "#AF52DE", "#FF375F"]

    /// Accent color for a usage level: red once at/over the limit, else the chosen accent.
    static func resolve(utilization: Double, hex: String?) -> Color {
        if utilization >= 90 { return .red }
        return Color(usageHex: hex ?? defaultAccentHex) ?? .orange
    }
}

extension Color {
    init?(usageHex: String) {
        guard let c = HexColor.parse(usageHex) else { return nil }
        self = Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    /// Best-effort `#RRGGBB` for persisting a ColorPicker selection.
    func toHex() -> String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return HexColor.string(r: Double(r), g: Double(g), b: Double(b))
    }
}
```

- [ ] **Step 2: Add `Shared` to both targets in `project.yml`**

Change the app target line `sources: [App]` → `sources: [App, Shared]` and the extension `sources: [Widget]` → `sources: [Widget, Shared]`.

- [ ] **Step 3: Regenerate the project**

Run: `cd /Users/stanley/Downloads/08_Development_Projects/apple/claude-widget && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate`
Expected: "Created project at ClaudeUsage.xcodeproj".

- [ ] **Step 4: Build to confirm the shared file compiles into both targets**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Shared/UsageTint.swift project.yml
git commit -m "[feat] shared UsageTint: hex->Color + red-override resolver

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Widget uses the accent

**Files:**
- Modify: `Widget/UsageProvider.swift` (add `accentHex` to `UsageEntry`, read from store)
- Modify: `Widget/UsageWidgetView.swift` (replace `levelColor`, thread accent into rows)

**Interfaces:**
- Consumes: `UsageTint.resolve`, `SharedStore.accentColorHex`.
- Produces: `UsageEntry.accentHex: String?`.

- [ ] **Step 1: Add `accentHex` to `UsageEntry` and populate it** — in `UsageProvider.swift`:

Add the field to the struct and to `.sample`:

```swift
struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let needsLogin: Bool
    let accentHex: String?

    static let sample = UsageEntry(
        date: Date(),
        snapshot: UsageSnapshot(
            fiveHour: UsageWindow(utilization: 62, resetsAt: Date(timeIntervalSinceNow: 2 * 3600 + 14 * 60)),
            sevenDay: UsageWindow(utilization: 38, resetsAt: Date(timeIntervalSinceNow: 4 * 86400)),
            fetchedAt: Date()),
        needsLogin: false,
        accentHex: nil)
}
```

Update `currentEntry()`:

```swift
    private func currentEntry() -> UsageEntry {
        let s = store()
        return UsageEntry(date: Date(),
                          snapshot: s?.loadSnapshot(),
                          needsLogin: s?.authState == .needsLogin,
                          accentHex: s?.accentColorHex)
    }
```

- [ ] **Step 2: Replace `levelColor` and thread the accent** — in `UsageWidgetView.swift`:

Delete the `levelColor(_:)` function (lines ~5–11). In `UsageWidgetView.content`, pass the accent into the family views:

```swift
            switch family {
            case .systemSmall:          SmallView(snapshot: snap, accentHex: entry.accentHex)
            case .systemMedium:         MediumView(snapshot: snap, accentHex: entry.accentHex)
            case .accessoryRectangular: RectView(snapshot: snap)
            case .accessoryCircular:    CircularView(window: snap.fiveHour)
            default:                    SmallView(snapshot: snap, accentHex: entry.accentHex)
            }
```

Update `BarRow`, `SmallView`, `MediumRow`, `MediumView` to carry `accentHex` and use `UsageTint.resolve`:

```swift
private struct BarRow: View {
    let title: String
    let window: UsageWindow
    let accentHex: String?
    private var color: Color { UsageTint.resolve(utilization: window.utilization, hex: accentHex) }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption).bold()
                Spacer()
                Text(UsageFormat.percent(window.utilization))
                    .font(.caption).bold().foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(window.utilization, 100) / 100)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct SmallView: View {
    let snapshot: UsageSnapshot
    let accentHex: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("✳ CLAUDE").font(.caption2).bold().foregroundStyle(.secondary)
            BarRow(title: "5H", window: snapshot.fiveHour, accentHex: accentHex)
            BarRow(title: "1W", window: snapshot.sevenDay, accentHex: accentHex)
        }
        .padding(12)
    }
}

private struct MediumRow: View {
    let title: String
    let window: UsageWindow
    let accentHex: String?
    private var color: Color { UsageTint.resolve(utilization: window.utilization, hex: accentHex) }
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).bold().frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(window.utilization, 100) / 100)
                }
            }
            .frame(height: 8)
            Text(UsageFormat.percent(window.utilization))
                .font(.caption).bold().frame(width: 42, alignment: .trailing)
                .foregroundStyle(color)
            Text("resets \(window.resetsAt, style: .relative)")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
        }
    }
}

private struct MediumView: View {
    let snapshot: UsageSnapshot
    let accentHex: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("✳ CLAUDE USAGE").font(.caption2).bold().foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.fetchedAt, style: .relative) ago")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            MediumRow(title: "5H", window: snapshot.fiveHour, accentHex: accentHex)
            MediumRow(title: "1W", window: snapshot.sevenDay, accentHex: accentHex)
        }
        .padding(14)
    }
}
```

(`RectView` and `CircularView` are unchanged — lock-screen accessories are system-tinted.)

- [ ] **Step 3: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Widget/UsageProvider.swift Widget/UsageWidgetView.swift
git commit -m "[feat] widget: render bars/percent with the chosen accent

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: App — accent state, in-app bars, Settings picker

**Files:**
- Modify: `App/AppModel.swift` (add `accentColorHex` + `setAccent`)
- Modify: `App/RootView.swift` (`WindowRow` uses `UsageTint.resolve`)
- Modify: `App/SettingsView.swift` (Appearance section)

**Interfaces:**
- Consumes: `UsageTint`, `SharedStore.accentColorHex`, `Color(usageHex:)`, `Color.toHex()`.
- Produces: `AppModel.accentColorHex: String` (published), `AppModel.setAccent(_ hex: String)`.

- [ ] **Step 1: AppModel** — add the published property (initialized in `init`, after `service.loadSite()`):

```swift
    @Published var accentColorHex: String = UsageTint.defaultAccentHex
```

At the end of `init()` add:

```swift
        self.accentColorHex = store.accentColorHex ?? UsageTint.defaultAccentHex
```

Add the setter:

```swift
    func setAccent(_ hex: String) {
        accentColorHex = hex
        store.accentColorHex = hex
        WidgetCenter.shared.reloadAllTimelines()
    }
```

- [ ] **Step 2: RootView `WindowRow`** — replace the `color` computed property body to use the model's accent. Change `WindowRow` to read accent from the environment model:

```swift
struct WindowRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let window: UsageWindow

    private var color: Color { UsageTint.resolve(utilization: window.utilization, hex: model.accentColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(UsageFormat.percent(window.utilization)).font(.headline).foregroundStyle(color)
            }
            ProgressView(value: min(window.utilization, 100), total: 100)
                .tint(color)
            Text("resets \(window.resetsAt, style: .relative)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

(`WindowRow` is already used inside `RootView`, which injects `model` via `@EnvironmentObject`, so the environment object is available.)

- [ ] **Step 3: SettingsView** — add an Appearance section above "About":

```swift
            Section("Appearance") {
                HStack(spacing: 14) {
                    ForEach(UsageTint.presets, id: \.self) { hex in
                        Circle()
                            .fill(Color(usageHex: hex) ?? .orange)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.primary,
                                lineWidth: model.accentColorHex.caseInsensitiveCompare(hex) == .orderedSame ? 2 : 0))
                            .onTapGesture { model.setAccent(hex) }
                            .accessibilityLabel(hex)
                    }
                }
                .padding(.vertical, 4)
                ColorPicker("Custom color", selection: Binding(
                    get: { Color(usageHex: model.accentColorHex) ?? .orange },
                    set: { model.setAccent($0.toHex() ?? UsageTint.defaultAccentHex) }))
                Text("Bars turn red at 90%+ regardless of this color.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
```

- [ ] **Step 4: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add App/AppModel.swift App/RootView.swift App/SettingsView.swift
git commit -m "[feat] app: accent picker in Settings + tinted in-app bars

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: App — `Keychain.swift` + `Credentials`

**Files:**
- Create: `App/Keychain.swift`

**Interfaces:**
- Produces:
  - `struct Credentials: Codable { let cookieHeader: String; let userAgent: String }`
  - `enum Keychain { static func saveCredentials(_:); static func loadCredentials() -> Credentials?; static func deleteCredentials() }`

- [ ] **Step 1: Create `App/Keychain.swift`**

```swift
import Foundation
import Security

/// Cookie header + UA harvested from the logged-in webview, replayed by the
/// background URLSession fetch. Sensitive — Keychain only, never UserDefaults.
struct Credentials: Codable {
    let cookieHeader: String
    let userAgent: String
}

enum Keychain {
    private static let service = "com.stanleyswiss.claudeusage.creds"
    private static let account = "claude"

    static func saveCredentials(_ creds: Credentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadCredentials() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 2: Regenerate (new file) and build**

Run: `cd /Users/stanley/Downloads/08_Development_Projects/apple/claude-widget && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add App/Keychain.swift project.yml
git commit -m "[feat] app: Keychain wrapper for harvested cookie credentials

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: App — harvest cookies/UA on successful foreground fetch

**Files:**
- Modify: `App/UsageService.swift` (add `harvestCredentials()`)
- Modify: `App/AppModel.swift` (call it after `.success`)

**Interfaces:**
- Consumes: `Credentials`, `Keychain.saveCredentials`, `webView.configuration.websiteDataStore.httpCookieStore`.
- Produces: `UsageService.harvestCredentials() async`.

- [ ] **Step 1: Add `harvestCredentials()` to `UsageService`** (place after `refresh()`):

```swift
    /// Copies claude.ai cookies + the page User-Agent into the Keychain so the
    /// background task can replay an authenticated URLSession request.
    func harvestCredentials() async {
        let ua = (try? await webView.callAsyncJavaScript(
            "return navigator.userAgent;", arguments: [:], in: nil, contentWorld: .page)) as? String
        guard let ua, !ua.isEmpty else { return }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        let claude = cookies.filter { $0.domain.contains("claude.ai") }
        guard !claude.isEmpty else { return }
        let header = claude.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        Keychain.saveCredentials(Credentials(cookieHeader: header, userAgent: ua))
    }
```

- [ ] **Step 2: Call it after a successful refresh in `AppModel.refresh()`**:

```swift
        case .success(let s):
            snapshot = s; needsLogin = false; lastError = nil
            await service.harvestCredentials()
```

- [ ] **Step 3: Clear credentials on logout** — in `AppModel.logout()`, after `service.clearSession()`:

```swift
        Keychain.deleteCredentials()
```

- [ ] **Step 4: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add App/UsageService.swift App/AppModel.swift
git commit -m "[feat] app: harvest cookies+UA to Keychain on successful fetch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: App — background refresh via URLSession

**Files:**
- Modify: `App/BackgroundRefresh.swift` (replace the WebKit path)

**Interfaces:**
- Consumes: `SharedStore.appGroup()`, `Keychain.loadCredentials()`, `UsageRemoteFetcher.fetchUsage`, `WidgetCenter`.

- [ ] **Step 1: Replace the body of `BackgroundRefresh.handle` and add `runFetch()`** — `BackgroundRefresh.swift` becomes:

```swift
import Foundation
import BackgroundTasks
import WidgetKit
import ClaudeUsageCore

enum BackgroundRefresh {
    static let taskID = AppConfig.bgRefreshTaskID

    /// Call once, before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            handle(refresh)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule() // chain the next one

        let work = Task {
            let ok = await runFetch()
            WidgetCenter.shared.reloadAllTimelines()
            task.setTaskCompleted(success: ok)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Cookie-based fetch (no WebKit). Keeps the last snapshot on a transient
    /// failure so a Cloudflare lapse never shows a false "tap to log in".
    private static func runFetch() async -> Bool {
        guard let store = SharedStore.appGroup(),
              let orgId = store.orgId,
              let creds = Keychain.loadCredentials() else { return false }

        let outcome = await UsageRemoteFetcher.fetchUsage(
            session: .shared, orgId: orgId,
            cookieHeader: creds.cookieHeader, userAgent: creds.userAgent, now: Date())

        switch outcome {
        case .success(let snap):
            store.saveSnapshot(snap)
            store.authState = .ok
            return true
        case .needsLogin:
            store.authState = .needsLogin
            return false
        case .transient:
            return false // keep last snapshot, leave authState untouched
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add App/BackgroundRefresh.swift
git commit -m "[feat] app: background refresh via URLSession + harvested cookies

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Full verification + README note

**Files:**
- Modify: `README.md` (document the accent picker + background-refresh behavior)

- [ ] **Step 1: Run the whole Core test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core`
Expected: PASS — all (25 original + new HexColor/UsageRemoteFetcher/SharedStore tests).

- [ ] **Step 2: Clean build the app**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -destination 'generic/platform=iOS Simulator' clean build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Update `README.md`** — add to the features/usage section:

> - **Accent color:** choose your widget color in Settings → Appearance (presets + custom). Bars still turn red at 90%+ as a near-limit warning.
> - **Background refresh:** the app harvests your login cookies and refreshes usage in the background on a best-effort schedule (iOS decides timing; only works while Cloudflare clearance is valid). Tapping the widget remains the always-reliable refresh.

- [ ] **Step 4: Device validation (manual, on the user's iPhone via Xcode)**
  - Change the accent in Settings → home-screen widget recolors after a moment.
  - Drive usage ≥90% (or temporarily lower the threshold to confirm) → bar shows red.
  - Background: after a successful in-app refresh, background the app; over time confirm the widget % updates without opening the app (best-effort — may take a while; iOS-scheduled).

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "[docs] README: accent color + best-effort background refresh

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Feature A accent + default orange + ≥90% red → Tasks 1, 2, 4, 5, 6. ✓
- `accentColorHex` in SharedStore → Task 1. ✓
- `Shared/UsageTint.swift` in both targets → Task 4. ✓
- Replaces `levelColor`/`WindowRow.color` → Tasks 5, 6. ✓
- Settings picker (presets + ColorPicker) → Task 6. ✓
- Widget entry carries hex → Task 5. ✓
- Feature B harvest on success → Task 8; Keychain `AfterFirstUnlock` → Task 7; URLSession bg fetch reusing classify/parse → Tasks 3, 9; transient keeps snapshot, needsLogin flags → Tasks 3, 9. ✓
- `UsageRemoteFetcher` testable → Task 3. ✓
- No new entitlements; xcodegen re-run; tests green; honest expectations in README → Tasks 4/7, 10. ✓

**Placeholder scan:** none — every code step shows full code. ✓

**Type consistency:** `accentColorHex` (String?/String) consistent across SharedStore↔AppModel; `UsageTint.resolve(utilization:hex:)`, `Color(usageHex:)`, `Color.toHex()`, `UsageFetchOutcome`, `Credentials(cookieHeader:userAgent:)`, `Keychain.saveCredentials/loadCredentials/deleteCredentials` all used with matching signatures. ✓
