# Claude Usage Widget (iOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native iOS WidgetKit app (home + lock screen) showing Claude 5-hour and 7-day usage, fetched via a logged-in `WKWebView`, sideloaded with a paid Apple Developer account.

**Architecture:** A local Swift Package (`ClaudeUsageCore`) holds all pure logic (models, JSON parsing, org selection, fetch-result classification, formatting, App-Group store) and is unit-tested with `swift test`. An Xcode project — generated from `project.yml` via XcodeGen — has two targets sharing an App Group: a SwiftUI **host app** (login + fetch + background refresh) and a **WidgetKit extension** (renders cached data). The widget only reads cache; all networking happens in the app by running `fetch()` inside the claude.ai page (so Cloudflare and httpOnly cookies are handled by the browser).

**Tech Stack:** Swift 5.9+, SwiftUI, WidgetKit, WebKit (`WKWebView.callAsyncJavaScript`), BackgroundTasks, Swift Package Manager, XcodeGen, XCTest.

---

## Conventions (used throughout)

- **Bundle id base:** `com.stanley.claudeusage` (app), `com.stanley.claudeusage.widget` (extension). Change `stanley` if you prefer — keep all three values below consistent if you do.
- **App Group:** `group.com.stanley.claudeusage`
- **BG task id:** `com.stanley.claudeusage.refresh`
- **Min iOS:** 16.0
- **Repo root:** `/Users/stanley/Downloads/08_Development_Projects/apple/claude-widget`
- **Commit style:** `[type] what and why` (matches project rule). Run `git add -A && git commit` from repo root in each commit step.

Directory layout this plan produces:
```
claude-widget/
  Core/                         # local Swift package (pure logic, unit-tested)
    Package.swift
    Sources/ClaudeUsageCore/*.swift
    Tests/ClaudeUsageCoreTests/*.swift
  App/                          # host app target sources
  Widget/                       # widget extension target sources
  project.yml                   # XcodeGen spec
  ClaudeUsage.xcodeproj         # generated (gitignored)
```

---

## Phase 0 — Tooling & scaffold

### Task 0.1: Verify toolchain, install XcodeGen

**Files:** none (environment only)

- [ ] **Step 1: Verify Swift + Xcode are present**

Run: `swift --version && xcodebuild -version`
Expected: Swift 5.9 or newer, Xcode 15 or newer.

If `xcodebuild` errors with "requires Xcode, but active developer directory is a command line tools instance", select full Xcode:
`sudo xcode-select -s /Applications/Xcode.app` (or prefix every `xcodebuild` command below with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

- [ ] **Step 2: Install XcodeGen**

Run: `brew install xcodegen && xcodegen --version`
Expected: prints a version (2.40+). If `brew` is missing, install Homebrew first from https://brew.sh.

- [ ] **Step 3: Add XcodeGen output to .gitignore**

Append to `.gitignore`:
```
# XcodeGen output (regenerate with `xcodegen generate`)
*.xcodeproj
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "[chore] ignore generated xcodeproj"
```

### Task 0.2: Create Core Swift package skeleton

**Files:**
- Create: `Core/Package.swift`
- Create: `Core/Sources/ClaudeUsageCore/Empty.swift`
- Create: `Core/Tests/ClaudeUsageCoreTests/SmokeTests.swift`

- [ ] **Step 1: Write `Core/Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageCore",
    platforms: [.iOS(.v16), .macOS(.v12)],
    products: [
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"]),
    ],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .testTarget(name: "ClaudeUsageCoreTests", dependencies: ["ClaudeUsageCore"]),
    ]
)
```

- [ ] **Step 2: Write `Core/Sources/ClaudeUsageCore/Empty.swift`**

```swift
// Package marker; real types are added in later tasks.
public enum ClaudeUsageCore {}
```

- [ ] **Step 3: Write `Core/Tests/ClaudeUsageCoreTests/SmokeTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageCore

final class SmokeTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Run the test suite**

Run: `cd Core && swift test && cd ..`
Expected: builds and reports 1 test passing.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "[chore] scaffold ClaudeUsageCore swift package"
```

---

## Phase 1 — Core logic (TDD)

All Phase 1 work happens in `Core/`. Run tests with `cd Core && swift test`. Core imports **only Foundation** — never UIKit/SwiftUI/WebKit (so it compiles on macOS for tests and on iOS for the app).

### Task 1.1: Constants + models

**Files:**
- Create: `Core/Sources/ClaudeUsageCore/Constants.swift`
- Create: `Core/Sources/ClaudeUsageCore/Models.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/ModelsTests.swift`
- Delete: `Core/Sources/ClaudeUsageCore/Empty.swift`

- [ ] **Step 1: Write the failing test `ModelsTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageCore

final class ModelsTests: XCTestCase {
    func testSnapshotCodableRoundTrip() throws {
        let snap = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 62, resetsAt: Date(timeIntervalSince1970: 1_700_000_000)),
            sevenDay: UsageWindow(utilization: 38, resetsAt: Date(timeIntervalSince1970: 1_700_500_000)),
            fetchedAt: Date(timeIntervalSince1970: 1_699_999_000))
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snap)
    }

    func testConstantsUsagePath() {
        XCTAssertEqual(ClaudeAPI.usagePath(org: "abc"), "/api/organizations/abc/usage")
        XCTAssertEqual(ClaudeAPI.orgsPath, "/api/organizations")
        XCTAssertTrue(AppConfig.appGroupID.hasPrefix("group."))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Core && swift test && cd ..`
Expected: FAIL — `UsageSnapshot` / `ClaudeAPI` not found.

- [ ] **Step 3: Write `Constants.swift`**

```swift
import Foundation

public enum ClaudeAPI {
    public static let base = "https://claude.ai"
    public static let loginURL = base + "/login"
    public static let orgsPath = "/api/organizations"
    public static func usagePath(org: String) -> String { "/api/organizations/\(org)/usage" }
}

public enum AppConfig {
    public static let appGroupID = "group.com.stanley.claudeusage"
    public static let bgRefreshTaskID = "com.stanley.claudeusage.refresh"
    public static let widgetKind = "ClaudeUsageWidget"
    public static let deepLinkURL = "claudeusage://refresh"
}
```

- [ ] **Step 4: Write `Models.swift` and delete `Empty.swift`**

```swift
import Foundation

public struct UsageWindow: Codable, Equatable, Sendable {
    public var utilization: Double   // 0...100
    public var resetsAt: Date
    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var fiveHour: UsageWindow
    public var sevenDay: UsageWindow
    public var fetchedAt: Date
    public init(fiveHour: UsageWindow, sevenDay: UsageWindow, fetchedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.fetchedAt = fetchedAt
    }
}
```

Run: `rm Core/Sources/ClaudeUsageCore/Empty.swift`

- [ ] **Step 5: Run test to verify it passes**

Run: `cd Core && swift test && cd ..`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "[feat] add core constants and usage models"
```

### Task 1.2: ISO-8601 parsing

**Files:**
- Create: `Core/Sources/ClaudeUsageCore/ISO8601.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/ISO8601Tests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeUsageCore

final class ISO8601Tests: XCTestCase {
    func testParsesPlainInternetDateTime() {
        let d = ISO8601.parse("2026-06-21T18:00:00Z")
        XCTAssertNotNil(d)
        XCTAssertEqual(d!.timeIntervalSince1970, 1781373600, accuracy: 1)
    }
    func testParsesFractionalSeconds() {
        XCTAssertNotNil(ISO8601.parse("2026-06-21T18:00:00.123Z"))
    }
    func testEmptyAndGarbageReturnNil() {
        XCTAssertNil(ISO8601.parse(""))
        XCTAssertNil(ISO8601.parse("not-a-date"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Core && swift test && cd ..`
Expected: FAIL — `ISO8601` not found.

- [ ] **Step 3: Write `ISO8601.swift`**

```swift
import Foundation

public enum ISO8601 {
    /// Parses an ISO-8601 timestamp, tolerating optional fractional seconds.
    public static func parse(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Core && swift test && cd ..`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "[feat] add tolerant ISO-8601 date parsing"
```

### Task 1.3: Usage JSON parser

**Files:**
- Create: `Core/Sources/ClaudeUsageCore/UsageParser.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/UsageParserTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeUsageCore

final class UsageParserTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_781_000_000)

    func testParsesBothWindows() throws {
        let json = """
        {"five_hour":{"utilization":62.5,"resets_at":"2026-06-21T18:00:00Z"},
         "seven_day":{"utilization":38,"resets_at":"2026-06-25T09:00:00Z"}}
        """.data(using: .utf8)!
        let snap = try UsageParser.parse(json, now: now)
        XCTAssertEqual(snap.fiveHour.utilization, 62.5, accuracy: 0.001)
        XCTAssertEqual(snap.sevenDay.utilization, 38, accuracy: 0.001)
        XCTAssertEqual(snap.fiveHour.resetsAt.timeIntervalSince1970, 1781373600, accuracy: 1)
        XCTAssertEqual(snap.fetchedAt, now)
    }

    func testMissingUtilizationDefaultsToZero() throws {
        let json = """
        {"five_hour":{"resets_at":"2026-06-21T18:00:00Z"},
         "seven_day":{"utilization":10,"resets_at":"2026-06-25T09:00:00Z"}}
        """.data(using: .utf8)!
        let snap = try UsageParser.parse(json, now: now)
        XCTAssertEqual(snap.fiveHour.utilization, 0)
    }

    func testMissingWindowThrows() {
        let json = #"{"five_hour":{"utilization":1,"resets_at":"2026-06-21T18:00:00Z"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try UsageParser.parse(json, now: now))
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try UsageParser.parse(Data("nope".utf8), now: now))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Core && swift test && cd ..`
Expected: FAIL — `UsageParser` not found.

- [ ] **Step 3: Write `UsageParser.swift`**

```swift
import Foundation

public enum UsageParseError: Error, Equatable {
    case invalidJSON
    case missingWindow(String)
}

public enum UsageParser {
    /// Parses the body of GET /api/organizations/{org}/usage.
    public static func parse(_ body: Data, now: Date) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw UsageParseError.invalidJSON
        }
        return UsageSnapshot(
            fiveHour: try window(in: root, key: "five_hour"),
            sevenDay: try window(in: root, key: "seven_day"),
            fetchedAt: now)
    }

    private static func window(in root: [String: Any], key: String) throws -> UsageWindow {
        guard let obj = root[key] as? [String: Any] else {
            throw UsageParseError.missingWindow(key)
        }
        let util = (obj["utilization"] as? NSNumber)?.doubleValue ?? 0
        let reset = ISO8601.parse(obj["resets_at"] as? String ?? "") ?? Date(timeIntervalSince1970: 0)
        return UsageWindow(utilization: util, resetsAt: reset)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Core && swift test && cd ..`
Expected: PASS (4 tests in this file).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "[feat] parse usage endpoint JSON into UsageSnapshot"
```

### Task 1.4: Org selection

**Files:**
- Create: `Core/Sources/ClaudeUsageCore/OrgSelector.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/OrgSelectorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeUsageCore

final class OrgSelectorTests: XCTestCase {
    func testPrefersChatCapableOrg() {
        let json = """
        [{"uuid":"a","capabilities":["api"]},
         {"uuid":"b","capabilities":["chat","claude_ai"]}]
        """.data(using: .utf8)!
        XCTAssertEqual(OrgSelector.selectOrgId(from: json), "b")
    }
    func testFallsBackToFirstWhenNoChatCapability() {
        let json = #"[{"uuid":"a","capabilities":["api"]}]"#.data(using: .utf8)!
        XCTAssertEqual(OrgSelector.selectOrgId(from: json), "a")
    }
    func testFallsBackToIdWhenNoUuid() {
        let json = #"[{"id":"x","capabilities":["chat"]}]"#.data(using: .utf8)!
        XCTAssertEqual(OrgSelector.selectOrgId(from: json), "x")
    }
    func testEmptyArrayReturnsNil() {
        XCTAssertNil(OrgSelector.selectOrgId(from: Data("[]".utf8)))
    }
    func testInvalidReturnsNil() {
        XCTAssertNil(OrgSelector.selectOrgId(from: Data("{}".utf8)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Core && swift test && cd ..`
Expected: FAIL — `OrgSelector` not found.

- [ ] **Step 3: Write `OrgSelector.swift`**

```swift
import Foundation

public enum OrgSelector {
    /// Picks an org id from the GET /api/organizations array body.
    /// Prefers an org whose capabilities include "chat" or "claude_ai".
    public static func selectOrgId(from body: Data) -> String? {
        guard let arr = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]],
              !arr.isEmpty else { return nil }
        for org in arr {
            let caps = (org["capabilities"] as? [Any])?.compactMap { $0 as? String } ?? []
            let isChat = caps.contains {
                let l = $0.lowercased()
                return l.contains("chat") || l.contains("claude_ai")
            }
            if isChat, let id = id(of: org) { return id }
        }
        return id(of: arr[0])
    }

    private static func id(of org: [String: Any]) -> String? {
        if let uuid = org["uuid"] as? String, !uuid.isEmpty { return uuid }
        if let id = org["id"] as? String, !id.isEmpty { return id }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Core && swift test && cd ..`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "[feat] select chat-capable org id from organizations list"
```

### Task 1.5: Fetch-result classification (state machine)

**Files:**
- Create: `Core/Sources/ClaudeUsageCore/FetchClassification.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/FetchClassificationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeUsageCore

final class FetchClassificationTests: XCTestCase {
    func testSuccess() {
        XCTAssertEqual(UsageHTTP.classify(status: 200, redirectedToLogin: false, body: "{}"), .success)
    }
    func testUnauthorized() {
        XCTAssertEqual(UsageHTTP.classify(status: 401, redirectedToLogin: false, body: ""), .needsLogin)
    }
    func testRedirectToLogin() {
        XCTAssertEqual(UsageHTTP.classify(status: 200, redirectedToLogin: true, body: ""), .needsLogin)
    }
    func testCloudflareByStatus() {
        XCTAssertEqual(UsageHTTP.classify(status: 403, redirectedToLogin: false, body: ""), .transient("cloudflare"))
        XCTAssertEqual(UsageHTTP.classify(status: 503, redirectedToLogin: false, body: ""), .transient("cloudflare"))
    }
    func testCloudflareByBody() {
        XCTAssertEqual(UsageHTTP.classify(status: 200, redirectedToLogin: false, body: "Just a moment..."),
                       .success) // 200 wins; body marker only matters for non-200
        XCTAssertEqual(UsageHTTP.classify(status: 500, redirectedToLogin: false, body: "Just a moment..."),
                       .transient("cloudflare"))
    }
    func testOtherHTTP() {
        XCTAssertEqual(UsageHTTP.classify(status: 500, redirectedToLogin: false, body: ""), .transient("http-500"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Core && swift test && cd ..`
Expected: FAIL — `UsageHTTP` / `FetchClassification` not found.

- [ ] **Step 3: Write `FetchClassification.swift`**

```swift
import Foundation

public enum FetchClassification: Equatable, Sendable {
    case success
    case needsLogin
    case transient(String)
}

public enum UsageHTTP {
    /// Classifies a usage/orgs HTTP response into the app's fetch state machine.
    public static func classify(status: Int, redirectedToLogin: Bool, body: String) -> FetchClassification {
        if redirectedToLogin { return .needsLogin }
        switch status {
        case 200:
            return .success
        case 401:
            return .needsLogin
        case 403, 503:
            return .transient("cloudflare")
        default:
            if body.contains("Just a moment") { return .transient("cloudflare") }
            return .transient("http-\(status)")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Core && swift test && cd ..`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "[feat] classify usage fetch responses (success/needsLogin/transient)"
```

### Task 1.6: Formatting + level

**Files:**
- Create: `Core/Sources/ClaudeUsageCore/UsageFormat.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/UsageFormatTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeUsageCore

final class UsageFormatTests: XCTestCase {
    func testPercentRounds() {
        XCTAssertEqual(UsageFormat.percent(62.4), "62%")
        XCTAssertEqual(UsageFormat.percent(62.6), "63%")
    }
    func testCountdownDaysHoursMinutes() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(UsageFormat.countdown(to: Date(timeIntervalSince1970: 2 * 86400 + 3 * 3600), from: now), "2d 3h")
        XCTAssertEqual(UsageFormat.countdown(to: Date(timeIntervalSince1970: 2 * 3600 + 14 * 60), from: now), "2h 14m")
        XCTAssertEqual(UsageFormat.countdown(to: Date(timeIntervalSince1970: 45 * 60), from: now), "45m")
        XCTAssertEqual(UsageFormat.countdown(to: Date(timeIntervalSince1970: -10), from: now), "now")
    }
    func testLevelBuckets() {
        XCTAssertEqual(UsageLevel(utilization: 10), .calm)
        XCTAssertEqual(UsageLevel(utilization: 75), .warn)
        XCTAssertEqual(UsageLevel(utilization: 95), .critical)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Core && swift test && cd ..`
Expected: FAIL — `UsageFormat` / `UsageLevel` not found.

- [ ] **Step 3: Write `UsageFormat.swift`**

```swift
import Foundation

public enum UsageLevel: Equatable, Sendable {
    case calm       // < 70
    case warn       // 70..<90
    case critical   // >= 90
    public init(utilization: Double) {
        switch utilization {
        case ..<70: self = .calm
        case ..<90: self = .warn
        default: self = .critical
        }
    }
}

public enum UsageFormat {
    public static func percent(_ utilization: Double) -> String {
        "\(Int(utilization.rounded()))%"
    }

    /// Short countdown like "2d 3h", "2h 14m", "45m", or "now" if already past.
    public static func countdown(to reset: Date, from now: Date) -> String {
        let secs = Int(reset.timeIntervalSince(now))
        if secs <= 0 { return "now" }
        let days = secs / 86400
        let hours = (secs % 86400) / 3600
        let mins = (secs % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Core && swift test && cd ..`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "[feat] add percent/countdown formatting and usage level buckets"
```

### Task 1.7: Shared store (App Group serialization)

**Files:**
- Create: `Core/Sources/ClaudeUsageCore/SharedStore.swift`
- Test: `Core/Tests/ClaudeUsageCoreTests/SharedStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeUsageCore

final class SharedStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "test." + UUID().uuidString
        return UserDefaults(suiteName: suite)!
    }

    func testSnapshotRoundTrip() {
        let defaults = makeDefaults()
        let store = SharedStore(defaults: defaults)
        XCTAssertNil(store.loadSnapshot())
        let snap = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 62, resetsAt: Date(timeIntervalSince1970: 1_781_000_000)),
            sevenDay: UsageWindow(utilization: 38, resetsAt: Date(timeIntervalSince1970: 1_781_500_000)),
            fetchedAt: Date(timeIntervalSince1970: 1_780_900_000))
        store.saveSnapshot(snap)
        XCTAssertEqual(store.loadSnapshot(), snap)
    }

    func testOrgIdAndAuthState() {
        let store = SharedStore(defaults: makeDefaults())
        XCTAssertNil(store.orgId)
        store.orgId = "abc"
        store.authState = .ok
        XCTAssertEqual(store.orgId, "abc")
        XCTAssertEqual(store.authState, .ok)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Core && swift test && cd ..`
Expected: FAIL — `SharedStore` not found.

- [ ] **Step 3: Write `SharedStore.swift`**

```swift
import Foundation

public enum AuthState: String, Sendable {
    case unknown
    case ok
    case needsLogin = "needs_login"
}

/// Thin wrapper over a (shared App Group) UserDefaults. Injectable for tests.
public struct SharedStore {
    public static let snapshotKey = "usage.snapshot"
    public static let orgIdKey = "usage.orgId"
    public static let authStateKey = "usage.authState"

    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// Convenience for the real App Group; returns nil if entitlement is missing.
    public static func appGroup() -> SharedStore? {
        guard let d = UserDefaults(suiteName: AppConfig.appGroupID) else { return nil }
        return SharedStore(defaults: d)
    }

    public func saveSnapshot(_ snapshot: UsageSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.snapshotKey)
        }
    }

    public func loadSnapshot() -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    public var orgId: String? {
        get { defaults.string(forKey: Self.orgIdKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.orgIdKey) }
    }

    public var authState: AuthState {
        get { AuthState(rawValue: defaults.string(forKey: Self.authStateKey) ?? "") ?? .unknown }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.authStateKey) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Core && swift test && cd ..`
Expected: PASS. Then run the whole suite once: `cd Core && swift test && cd ..` — expect all Phase 1 tests green.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "[feat] add App-Group SharedStore for snapshot/org/auth state"
```

---

## Phase 2 — Generate the Xcode project (minimal, building)

Goal: a generated `ClaudeUsage.xcodeproj` with both targets that **compiles and links Core** for the iOS Simulator. Real UI comes in Phases 3–4. The widget target keeps its single `@main` `WidgetBundle` from here on.

### Task 2.1: Write XcodeGen spec, entitlements, Info.plists, minimal sources

**Files:**
- Create: `project.yml`
- Create: `App/ClaudeUsage.entitlements`
- Create: `App/Info.plist`
- Create: `App/ClaudeUsageApp.swift` (minimal)
- Create: `Widget/ClaudeUsageWidget.entitlements`
- Create: `Widget/Info.plist`
- Create: `Widget/WidgetBundle.swift` (minimal)

- [ ] **Step 1: Write `project.yml`**

```yaml
name: ClaudeUsage
options:
  bundleIdPrefix: com.stanley
  deploymentTarget:
    iOS: "16.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.0"
packages:
  ClaudeUsageCore:
    path: Core
targets:
  ClaudeUsage:
    type: application
    platform: iOS
    sources: [App]
    dependencies:
      - package: ClaudeUsageCore
      - target: ClaudeUsageWidgetExtension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.stanley.claudeusage
        INFOPLIST_FILE: App/Info.plist
        CODE_SIGN_ENTITLEMENTS: App/ClaudeUsage.entitlements
        CURRENT_PROJECT_VERSION: "1"
        MARKETING_VERSION: "1.0"
        GENERATE_INFOPLIST_FILE: NO
        TARGETED_DEVICE_FAMILY: "1"
  ClaudeUsageWidgetExtension:
    type: app-extension
    platform: iOS
    sources: [Widget]
    dependencies:
      - package: ClaudeUsageCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.stanley.claudeusage.widget
        INFOPLIST_FILE: Widget/Info.plist
        CODE_SIGN_ENTITLEMENTS: Widget/ClaudeUsageWidget.entitlements
        CURRENT_PROJECT_VERSION: "1"
        MARKETING_VERSION: "1.0"
        GENERATE_INFOPLIST_FILE: NO
        TARGETED_DEVICE_FAMILY: "1"
```

- [ ] **Step 2: Write `App/ClaudeUsage.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.stanley.claudeusage</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Write `Widget/ClaudeUsageWidget.entitlements`** (identical group)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.stanley.claudeusage</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 4: Write `App/Info.plist`** (declares the BG task id + URL scheme)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
    </dict>
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>com.stanley.claudeusage.refresh</string>
    </array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>claudeusage</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 5: Write `Widget/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 6: Write minimal `App/ClaudeUsageApp.swift`**

```swift
import SwiftUI

@main
struct ClaudeUsageApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Claude Usage")
        }
    }
}
```

- [ ] **Step 7: Write minimal `Widget/WidgetBundle.swift`**

```swift
import WidgetKit
import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
    }
}

struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConfig.widgetKind, provider: PlaceholderProvider()) { _ in
            Text("Claude")
        }
        .configurationDisplayName("Claude Usage")
        .description("Your Claude usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct PlaceholderEntry: TimelineEntry { let date: Date }

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: Date())], policy: .never))
    }
}
```

- [ ] **Step 8: Generate the project**

Run: `xcodegen generate`
Expected: "Created project at ClaudeUsage.xcodeproj".

- [ ] **Step 9: Build for the simulator (no signing needed)**

Run:
```bash
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`. If it fails, read the first error, fix the offending file, re-run.

- [ ] **Step 10: Commit**

```bash
git add -A && git commit -m "[feat] generate Xcode project with app + widget targets (minimal)"
```

---

## Phase 3 — Host app

The host app owns the WebView and all fetching. These files are integration glue (WebView + network + main-actor UI), so they are verified by **building** (Step "build for simulator") and by **on-device behavior in Phase 5**, not by unit tests. After each task, run the same simulator build command from Task 2.1 Step 9 and expect `BUILD SUCCEEDED`.

### Task 3.1: UsageService (WebView fetch + refresh)

**Files:**
- Create: `App/UsageService.swift`

- [ ] **Step 1: Write `App/UsageService.swift`**

```swift
import Foundation
import WebKit
import ClaudeUsageCore

/// Owns a persistent WKWebView signed into claude.ai and fetches usage by
/// running fetch() inside the page (so cookies + Cloudflare are handled by the browser).
@MainActor
final class UsageService: NSObject, WKNavigationDelegate {
    enum Result {
        case success(UsageSnapshot)
        case needsLogin
        case transient(String)
    }

    let webView: WKWebView
    private let store: SharedStore
    private var loadContinuations: [CheckedContinuation<Void, Never>] = []
    private var isLoaded = false

    init(store: SharedStore) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistent cookies survive launches
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.store = store
        super.init()
        self.webView.navigationDelegate = self
    }

    /// Loads claude.ai so the page origin is available for same-origin fetch().
    func loadSite() {
        isLoaded = false
        webView.load(URLRequest(url: URL(string: ClaudeAPI.base + "/")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        let conts = loadContinuations
        loadContinuations.removeAll()
        conts.forEach { $0.resume() }
    }

    private func waitForLoad() async {
        if isLoaded { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            loadContinuations.append(c)
        }
    }

    /// Fetches usage; resolves org first if unknown. Persists snapshot on success.
    func refresh() async -> Result {
        await waitForLoad()

        var org = store.orgId
        if org == nil {
            guard let r = await jsFetch(path: ClaudeAPI.orgsPath) else { return .transient("io") }
            switch UsageHTTP.classify(status: r.status, redirectedToLogin: r.toLogin, body: r.body) {
            case .needsLogin:
                store.authState = .needsLogin; return .needsLogin
            case .transient(let why):
                return .transient(why)
            case .success:
                guard let id = OrgSelector.selectOrgId(from: Data(r.body.utf8)) else {
                    return .transient("org-unknown")
                }
                org = id; store.orgId = id
            }
        }

        guard let r = await jsFetch(path: ClaudeAPI.usagePath(org: org!)) else { return .transient("io") }
        switch UsageHTTP.classify(status: r.status, redirectedToLogin: r.toLogin, body: r.body) {
        case .needsLogin:
            store.authState = .needsLogin; return .needsLogin
        case .transient(let why):
            return .transient(why)
        case .success:
            do {
                let snap = try UsageParser.parse(Data(r.body.utf8), now: Date())
                store.saveSnapshot(snap); store.authState = .ok
                return .success(snap)
            } catch {
                return .transient("parse")
            }
        }
    }

    private struct JSResult { let status: Int; let toLogin: Bool; let body: String }

    private func jsFetch(path: String) async -> JSResult? {
        let js = """
        const res = await fetch(path, { credentials: 'include', headers: { 'Accept': '*/*' } });
        const body = await res.text();
        const toLogin = res.redirected && res.url.indexOf('/login') !== -1;
        return JSON.stringify({ status: res.status, toLogin: toLogin, body: body });
        """
        do {
            let value = try await webView.callAsyncJavaScript(
                js, arguments: ["path": path], in: nil, contentWorld: .page)
            guard let s = value as? String,
                  let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
                  let status = obj["status"] as? Int else { return nil }
            return JSResult(status: status,
                            toLogin: obj["toLogin"] as? Bool ?? false,
                            body: obj["body"] as? String ?? "")
        } catch {
            return nil
        }
    }

    /// Clears the claude.ai session (logout).
    func clearSession() async {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let claude = records.filter { $0.displayName.contains("claude") || $0.displayName.contains("anthropic") }
        await dataStore.removeData(ofTypes: types, for: claude)
        self.store.authState = .needsLogin
    }
}
```

- [ ] **Step 2: Build for the simulator**

Run the Task 2.1 Step 9 build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "[feat] add UsageService: in-WebView fetch + refresh state machine"
```

### Task 3.2: AppModel + LoginWebView + RootView

**Files:**
- Create: `App/AppModel.swift`
- Create: `App/LoginWebView.swift`
- Create: `App/RootView.swift`
- Create: `App/SettingsView.swift`
- Modify: `App/ClaudeUsageApp.swift`

- [ ] **Step 1: Write `App/AppModel.swift`**

```swift
import Foundation
import SwiftUI
import WidgetKit
import ClaudeUsageCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let service: UsageService
    let store: SharedStore

    @Published var snapshot: UsageSnapshot?
    @Published var needsLogin = false
    @Published var lastError: String?
    @Published var isRefreshing = false

    init() {
        let defaults = UserDefaults(suiteName: AppConfig.appGroupID)
        let store = SharedStore(defaults: defaults ?? .standard)
        self.store = store
        self.service = UsageService(store: store)
        self.snapshot = store.loadSnapshot()
        self.needsLogin = store.authState == .needsLogin
        service.loadSite()
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        switch await service.refresh() {
        case .success(let s):
            snapshot = s; needsLogin = false; lastError = nil
        case .needsLogin:
            needsLogin = true
        case .transient(let why):
            lastError = why
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func logout() async {
        await service.clearSession()
        snapshot = nil
        needsLogin = true
        service.loadSite()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

- [ ] **Step 2: Write `App/LoginWebView.swift`**

```swift
import SwiftUI
import WebKit
import ClaudeUsageCore

/// Shows the shared WKWebView at claude.ai/login so cookies land in the same store.
struct LoginWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView.load(URLRequest(url: URL(string: ClaudeAPI.loginURL)!))
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Sheet chrome with a Done button the user taps after logging in.
struct LoginSheet: View {
    let webView: WKWebView
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            LoginWebView(webView: webView)
                .ignoresSafeArea()
                .navigationTitle("Log in to Claude")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
        }
    }
}
```

- [ ] **Step 3: Write `App/RootView.swift`**

```swift
import SwiftUI
import ClaudeUsageCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let snap = model.snapshot {
                    WindowRow(title: "5H", window: snap.fiveHour)
                    WindowRow(title: "1W", window: snap.sevenDay)
                    Text("Updated \(snap.fetchedAt, style: .relative) ago")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "gauge.medium").font(.largeTitle)
                        Text("No data yet").font(.headline)
                        Text("Log in and refresh.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if let err = model.lastError {
                    Text("Last issue: \(err)").font(.caption2).foregroundStyle(.orange)
                }

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label(model.isRefreshing ? "Refreshing…" : "Refresh now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRefreshing)

                if model.needsLogin {
                    Button("Log in to Claude") { showLogin = true }
                }
            }
            .padding()
            .navigationTitle("Claude Usage")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gear") }
                }
            }
            .onChange(of: model.needsLogin) { needs in
                if needs { showLogin = true }
            }
            .sheet(isPresented: $showLogin) {
                LoginSheet(webView: model.service.webView) {
                    showLogin = false
                    Task { await model.refresh() }
                }
            }
            .task { await model.refresh() }
        }
    }
}

struct WindowRow: View {
    let title: String
    let window: UsageWindow

    private var color: Color {
        switch UsageLevel(utilization: window.utilization) {
        case .calm: return .green
        case .warn: return .orange
        case .critical: return .red
        }
    }

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

- [ ] **Step 4: Replace `App/ClaudeUsageApp.swift`**

```swift
import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }
}
```

- [ ] **Step 5: Write `App/SettingsView.swift`**

```swift
import SwiftUI
import ClaudeUsageCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Account", value: model.needsLogin ? "Logged out" : "Logged in")
                if let snap = model.snapshot {
                    LabeledContent("Last update") { Text(snap.fetchedAt, style: .relative) }
                }
                LabeledContent("Org id", value: model.store.orgId ?? "—")
            }
            Section("Account") {
                Button(role: .destructive) {
                    Task { await model.logout() }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Section("About") {
                LabeledContent("App Group", value: AppConfig.appGroupID)
                LabeledContent("Data source", value: "claude.ai/api/.../usage")
            }
        }
        .navigationTitle("Settings")
    }
}
```

- [ ] **Step 6: Build for the simulator**

Run the Task 2.1 Step 9 build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "[feat] add AppModel, login sheet, settings, and root usage screen"
```

### Task 3.3: Background refresh

**Files:**
- Create: `App/BackgroundRefresh.swift`
- Modify: `App/ClaudeUsageApp.swift`

- [ ] **Step 1: Write `App/BackgroundRefresh.swift`**

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

        let work = Task { @MainActor in
            let result = await AppModel.shared.service.refresh()
            WidgetCenter.shared.reloadAllTimelines()
            if case .success = result {
                task.setTaskCompleted(success: true)
            } else {
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { work.cancel() }
    }
}
```

- [ ] **Step 2: Update `App/ClaudeUsageApp.swift` to register + schedule**

```swift
import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel.shared

    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                Task { await model.refresh() }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 3: Build for the simulator**

Run the Task 2.1 Step 9 build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "[feat] schedule best-effort background refresh via BGAppRefreshTask"
```

---

## Phase 4 — Widget extension

Replace the minimal widget from Phase 2 with the real timeline + views. Verified by simulator build here and on-device in Phase 5.

### Task 4.1: Real timeline provider + entry

**Files:**
- Modify: `Widget/WidgetBundle.swift` (split provider into its own file)
- Create: `Widget/UsageProvider.swift`

- [ ] **Step 1: Write `Widget/UsageProvider.swift`**

```swift
import WidgetKit
import Foundation
import ClaudeUsageCore

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let needsLogin: Bool

    static let sample = UsageEntry(
        date: Date(),
        snapshot: UsageSnapshot(
            fiveHour: UsageWindow(utilization: 62, resetsAt: Date(timeIntervalSinceNow: 2 * 3600 + 14 * 60)),
            sevenDay: UsageWindow(utilization: 38, resetsAt: Date(timeIntervalSinceNow: 4 * 86400)),
            fetchedAt: Date()),
        needsLogin: false)
}

struct UsageProvider: TimelineProvider {
    private func store() -> SharedStore? { SharedStore.appGroup() }

    func placeholder(in context: Context) -> UsageEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(context.isPreview ? .sample : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = currentEntry()
        let next = Date(timeIntervalSinceNow: 15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> UsageEntry {
        let s = store()
        return UsageEntry(date: Date(),
                          snapshot: s?.loadSnapshot(),
                          needsLogin: s?.authState == .needsLogin)
    }
}
```

- [ ] **Step 2: Update `Widget/WidgetBundle.swift` to use the real provider (views come next task)**

```swift
import WidgetKit
import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
    }
}

struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConfig.widgetKind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your 5-hour and weekly Claude usage.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
```

(`UsageWidgetView` is created in Task 4.2 — build will fail until then; that's expected, do not build yet.)

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "[feat] add widget timeline provider reading App-Group cache"
```

### Task 4.2: Widget views (all four families)

**Files:**
- Create: `Widget/UsageWidgetView.swift`

- [ ] **Step 1: Write `Widget/UsageWidgetView.swift`**

```swift
import WidgetKit
import SwiftUI
import ClaudeUsageCore

private func levelColor(_ utilization: Double) -> Color {
    switch UsageLevel(utilization: utilization) {
    case .calm: return .green
    case .warn: return .orange
    case .critical: return .red
    }
}

/// Applies the iOS 17+ required container background; no-op on iOS 16.
private struct ContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(.fill.tertiary, for: .widget)
        } else {
            content
        }
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        content
            .modifier(ContainerBackground())
            .widgetURL(URL(string: AppConfig.deepLinkURL))
    }

    @ViewBuilder private var content: some View {
        if entry.needsLogin {
            NeedsLoginView(family: family)
        } else if let snap = entry.snapshot {
            switch family {
            case .systemSmall:        SmallView(snapshot: snap)
            case .systemMedium:       MediumView(snapshot: snap)
            case .accessoryRectangular: RectView(snapshot: snap)
            case .accessoryCircular:  CircularView(window: snap.fiveHour)
            default:                  SmallView(snapshot: snap)
            }
        } else {
            Text("—").font(.headline).foregroundStyle(.secondary)
        }
    }
}

private struct NeedsLoginView: View {
    let family: WidgetFamily
    var body: some View {
        if family == .accessoryCircular {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
        } else {
            VStack(spacing: 2) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                Text("Tap to log in").font(.caption2)
            }
        }
    }
}

// MARK: - Home screen

private struct BarRow: View {
    let title: String
    let window: UsageWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption).bold()
                Spacer()
                Text(UsageFormat.percent(window.utilization))
                    .font(.caption).bold().foregroundStyle(levelColor(window.utilization))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(levelColor(window.utilization))
                        .frame(width: geo.size.width * min(window.utilization, 100) / 100)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct SmallView: View {
    let snapshot: UsageSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("✳ CLAUDE").font(.caption2).bold().foregroundStyle(.secondary)
            BarRow(title: "5H", window: snapshot.fiveHour)
            BarRow(title: "1W", window: snapshot.sevenDay)
        }
        .padding(12)
    }
}

private struct MediumRow: View {
    let title: String
    let window: UsageWindow
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).bold().frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(levelColor(window.utilization))
                        .frame(width: geo.size.width * min(window.utilization, 100) / 100)
                }
            }
            .frame(height: 8)
            Text(UsageFormat.percent(window.utilization))
                .font(.caption).bold().frame(width: 42, alignment: .trailing)
                .foregroundStyle(levelColor(window.utilization))
            Text("resets \(window.resetsAt, style: .relative)")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
        }
    }
}

private struct MediumView: View {
    let snapshot: UsageSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("✳ CLAUDE USAGE").font(.caption2).bold().foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.fetchedAt, style: .relative) ago")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            MediumRow(title: "5H", window: snapshot.fiveHour)
            MediumRow(title: "1W", window: snapshot.sevenDay)
        }
        .padding(14)
    }
}

// MARK: - Lock screen

private struct RectView: View {
    let snapshot: UsageSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude").font(.caption2).bold()
            Text("5H \(UsageFormat.percent(snapshot.fiveHour.utilization)) · 1W \(UsageFormat.percent(snapshot.sevenDay.utilization))")
                .font(.caption)
            Text("5H resets \(snapshot.fiveHour.resetsAt, style: .relative)")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct CircularView: View {
    let window: UsageWindow
    var body: some View {
        Gauge(value: min(window.utilization, 100), in: 0...100) {
            Text("5H")
        } currentValueLabel: {
            Text("\(Int(window.utilization.rounded()))")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}
```

- [ ] **Step 2: Build for the simulator**

Run the Task 2.1 Step 9 build command.
Expected: `** BUILD SUCCEEDED **`. Fix any compile errors before continuing.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "[feat] add widget views for small/medium/lock-screen with live countdowns"
```

---

## Phase 5 — Sign, sideload, validate (on device)

These steps require Xcode GUI, your iPhone connected, and your paid Apple Developer team. They are manual; check each box after confirming the described result.

### Task 5.1: Configure signing and run on device

- [ ] **Step 1: Open the project**

Run: `open ClaudeUsage.xcodeproj`

- [ ] **Step 2: Set the team on both targets**

In Xcode → target **ClaudeUsage** → Signing & Capabilities → check "Automatically manage signing" → select your paid Developer **Team**. Repeat for target **ClaudeUsageWidgetExtension**.
Expected: no red signing errors; provisioning profiles generate for both bundle ids.

- [ ] **Step 3: Confirm App Group capability on both targets**

In Signing & Capabilities for each target, confirm the **App Groups** capability lists `group.com.stanley.claudeusage` and is checked. (It comes from the entitlements files; Xcode may ask to register it — allow.)
Expected: App Group enabled on app and widget.

- [ ] **Step 4: Select your iPhone and Run**

Pick your connected iPhone as the run destination → press Run (⌘R). Trust the developer certificate on the phone if prompted (Settings → General → VPN & Device Management).
Expected: the app launches on the phone showing "No data yet".

### Task 5.2: End-to-end validation

- [ ] **Step 1: Log in**

In the app, tap "Log in to Claude" (or the sheet appears automatically), complete the claude.ai login in the WebView (including any Cloudflare check), tap **Done**.
Expected: the app dismisses the sheet and shows 5H and 1W percentages.

- [ ] **Step 2: Cross-check the numbers**

Open `https://claude.ai/settings/usage` in a browser.
Expected: the widget/app 5H and 1W percentages match (within rounding).

- [ ] **Step 3: Add the home-screen widget**

Long-press home screen → + → search "Claude Usage" → add the small and medium sizes.
Expected: both render the current percentages, bars, and a live "resets …" countdown that updates over time.

- [ ] **Step 4: Add lock-screen widgets**

Lock screen → Customize → add the rectangular and circular Claude Usage accessories.
Expected: rectangular shows "5H x% · 1W y%"; circular shows the 5H gauge.

- [ ] **Step 5: Verify refresh + persistence**

Force-quit and reopen the app.
Expected: still logged in (no re-login), numbers refresh, and the widgets update shortly after (or immediately via the app's `reloadAllTimelines`).

- [ ] **Step 6: Tag the working build**

```bash
git add -A && git commit -m "[chore] v1 validated on device" --allow-empty
git tag v1.0
```

---

## Done / success criteria (from the spec)

- After one in-app login, the home-screen widget shows 5H and 1W % matching `claude.ai/settings/usage`. ✅ Task 5.2
- Countdown to each reset ticks live. ✅ Task 4.2 (`Text(_, style: .relative)`)
- Lock-screen rectangular + circular render in light/dark. ✅ Task 5.2
- Reopening the app refreshes data and the widget updates. ✅ Task 3.3 / 5.2
- Session survives relaunch without re-login. ✅ persistent `WKWebsiteDataStore` (Task 3.1)

## Deferred to Phase 2 (not in this plan)

Harvested-cookie `URLSession` background path, multi-org picker, configurable interval/threshold intent, lock-screen-only install.
