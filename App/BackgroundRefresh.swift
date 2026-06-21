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
