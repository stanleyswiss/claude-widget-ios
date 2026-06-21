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
