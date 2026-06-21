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
