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
