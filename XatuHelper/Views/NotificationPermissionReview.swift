import SwiftUI
import UserNotifications

/// Shared by foreground scenes so only one window presents the update's permission review.
@MainActor
final class NotificationPermissionReview: ObservableObject {
    private static let reviewedKey = "notify.permissionReviewed.2026-11"
    @Published private(set) var pending: Bool
    private let defaults: UserDefaults
    @Published private(set) var presenter: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pending = !defaults.bool(forKey: Self.reviewedKey)
    }

    func claim(_ scene: UUID) -> Bool {
        guard pending, presenter == nil || presenter == scene else { return false }
        presenter = scene
        return true
    }

    func release(_ scene: UUID) {
        guard presenter == scene else { return }
        if defaults.bool(forKey: Self.reviewedKey) { pending = false }
        presenter = nil
    }

    func markPresented() {
        defaults.set(true, forKey: Self.reviewedKey)
    }

    func finish() {
        pending = false
        presenter = nil
    }
}

private struct NotificationReviewPendingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notificationReviewPending: Bool {
        get { self[NotificationReviewPendingKey.self] }
        set { self[NotificationReviewPendingKey.self] = newValue }
    }
}

struct NotificationPermissionReviewPresenter: View {
    @ObservedObject var review: NotificationPermissionReview
    let canPresent: Bool
    @Environment(\.openURL) private var openURL
    @State private var sceneID = UUID()
    @State private var status: UNAuthorizationStatus?
    @State private var showing = false
    @State private var answering = false

    private var eligible: Bool {
        canPresent && review.pending && (review.presenter == nil || review.presenter == sceneID)
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: eligible) {
                guard eligible, !showing, !answering, review.claim(sceneID) else { return }
                let current = await NotificationService.authorizationStatus()
                guard !Task.isCancelled else {
                    review.release(sceneID)
                    return
                }
                status = current
                showing = true
                review.markPresented()
            }
            .onDisappear { review.release(sceneID) }
            .alert(title, isPresented: $showing, presenting: status) { permission in
                if permission == .notDetermined {
                    Button("先不用", role: .cancel) { review.finish() }
                    Button("允许通知") {
                        answering = true
                        Task {
                            _ = await NotificationService.requestAuthorization()
                            review.finish()
                            answering = false
                        }
                    }
                } else {
                    Button(permission == .denied ? "先不用" : "保留当前设置", role: .cancel) { review.finish() }
                    Button("打开系统设置") {
                        review.finish()
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            } message: { permission in
                switch permission {
                case .notDetermined: Text("允许后，XATune 可以发送你开启的课程、考试等提醒。")
                case .denied: Text("通知权限已关闭。可以在系统设置中允许 XATune 发送提醒。")
                case .provisional: Text("当前为静默通知。可以在系统设置中调整提醒方式。")
                default: Text("通知权限已开启。可以保留当前设置，或更改通知方式。")
                }
            }
    }

    private var title: String {
        status == .notDetermined || status == .denied ? "接收 XATune 的通知？" : "继续接收 XATune 的通知？"
    }
}
