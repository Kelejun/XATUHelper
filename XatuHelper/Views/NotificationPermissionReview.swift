import SwiftUI

@MainActor
final class NotificationPermissionReview: ObservableObject {
    private static let reviewedKey = "notify.reminderSetupReviewed.2026-11-26"
    @Published private(set) var pending: Bool
    @Published private(set) var dismissedInSession = false
    @Published private(set) var presenter: UUID?
    private let defaults: UserDefaults

    init(hasCachedAccount: Bool, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let previousSetup = ["notify.prompted", "notify.examPrompted", "courseProgress.prompted",
                             "notify.permissionReviewed.2026-11", "notify.prompted.2026-11",
                             "notify.examPrompted.2026-11", "courseProgress.prompted.2026-11",
                             "notify.reminderSetupReviewed.2026-11-25", "notify.prompted.2026-11-25",
                             "notify.examPrompted.2026-11-25", "courseProgress.prompted.2026-11-25"].contains { defaults.bool(forKey: $0) }
        if !hasCachedAccount && !previousSetup {
            defaults.set(true, forKey: Self.reviewedKey)
        }
        pending = !defaults.bool(forKey: Self.reviewedKey) &&
            !(defaults.bool(forKey: NotificationSettings.prompted) && defaults.bool(forKey: CourseActivityController.promptedKey))
    }

    func claim(_ scene: UUID) -> Bool {
        guard pending, presenter == nil else { return false }
        presenter = scene
        return true
    }

    func release(_ scene: UUID) {
        guard presenter == scene else { return }
        presenter = nil
    }

    func finish(_ scene: UUID) {
        guard presenter == scene else { return }
        let completed = defaults.bool(forKey: NotificationSettings.prompted) &&
            defaults.bool(forKey: CourseActivityController.promptedKey)
        if completed {
            defaults.set(true, forKey: Self.reviewedKey)
        } else {
            dismissedInSession = true
        }
        pending = false
        presenter = nil
    }
}

private struct NotificationReviewPendingKey: EnvironmentKey {
    static let defaultValue = false
}

private struct CourseReminderSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notificationReviewPending: Bool {
        get { self[NotificationReviewPendingKey.self] }
        set { self[NotificationReviewPendingKey.self] = newValue }
    }

    var courseReminderSuppressed: Bool {
        get { self[CourseReminderSuppressedKey.self] }
        set { self[CourseReminderSuppressedKey.self] = newValue }
    }
}

struct NotificationPermissionReviewPresenter: View {
    @ObservedObject var review: NotificationPermissionReview
    let canPresent: Bool
    @State private var sceneID = UUID()
    @State private var showing = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: canPresent && review.pending && review.presenter == nil) {
                guard canPresent, review.claim(sceneID) else { return }
                showing = true
            }
            .sheet(isPresented: $showing, onDismiss: { review.finish(sceneID) }) {
                NotificationSetupSheet()
            }
            .onDisappear { review.release(sceneID) }
    }
}
