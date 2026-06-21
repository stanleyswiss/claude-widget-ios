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
        if let defaults {
            defaults.set("ok", forKey: "diag.canary")
            print("[ClaudeUsage] appGroup '\(AppConfig.appGroupID)' resolved; canary=\(defaults.string(forKey: "diag.canary") ?? "nil")")
        } else {
            print("[ClaudeUsage] appGroup '\(AppConfig.appGroupID)' is NIL — App Groups capability not provisioned")
        }
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
        let result = await service.refresh()
        switch result {
        case .success(let s):
            snapshot = s; needsLogin = false; lastError = nil
            print("[ClaudeUsage] refresh result: success 5H=\(Int(s.fiveHour.utilization))% 1W=\(Int(s.sevenDay.utilization))%")
        case .needsLogin:
            needsLogin = true
            print("[ClaudeUsage] refresh result: needsLogin")
        case .transient(let why):
            lastError = why
            print("[ClaudeUsage] refresh result: transient(\(why))")
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
