import SwiftUI
import UIKit

struct ElectricityRefreshSettingsSection: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ElectricityRefreshSettings.automaticKey) private var automaticEnabled = true
    @AppStorage(ElectricityRefreshSettings.backgroundKey) private var backgroundEnabled = false
    @AppStorage(ElectricityRefreshSettings.exitReminderKey) private var exitReminderEnabled = false
    @AppStorage("showDiagnostics") private var showDiagnostics = false
    @State private var showsNotificationAlert = false
    @State private var backgroundUnavailable = false
    @State private var testingNotification = false
    @State private var notificationFeedback: String?

    var body: some View {
        Section {
            Toggle("每日自动刷新电费余额", isOn: $automaticEnabled)
            if automaticEnabled {
                Toggle("后台自动刷新（测试）", isOn: $backgroundEnabled)
                if backgroundEnabled {
                    Toggle("退出时提醒（测试）", isOn: $exitReminderEnabled)
                    if showDiagnostics && exitReminderEnabled {
                        LabeledContent("最近退出回调", value: terminationCallbackText)
                            .font(.footnote)
                        if let status = BackgroundElectricityRefresh.lastExitNotificationStatus {
                            Text(status).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("发送测试通知（5 秒后）") {
                            Task { await testExitNotification() }
                        }
                        .disabled(testingNotification)
                        if let feedback = notificationFeedback {
                            Text(feedback).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let error = BackgroundElectricityRefresh.lastExitNotificationError {
                            Text("上次通知提交失败：\(error)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if backgroundUnavailable {
                        Label("系统未允许后台 App 刷新", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Button("打开系统设置") { openSystemSettings() }
                    }
                    if let error = app.backgroundElectricityScheduleError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("电费")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("自动刷新每天成功一次并保存余额记录；关闭后仅手动查询。")
                if automaticEnabled && backgroundEnabled {
                    Text("每天 00:01 后申请由系统择机唤醒，不能保证准时或每天执行。若后台查询失败，将暂停后台尝试，等下次主动打开 App 补查成功后恢复。")
                    Text("请勿在多任务界面上划关闭 App，否则后台自动刷新电费可能不生效。")
                    if exitReminderEnabled {
                        Text("退出时提醒需要通知权限。App 挂起后被划掉通常没有退出回调，因此不能保证提醒。")
                        if showDiagnostics {
                            Text("测试通知只验证通知权限与投递，不代表能检测退出。")
                        }
                    }
                } else if automaticEnabled {
                    Text("每天第一次打开 App 时查询余额。开启后台自动刷新后，也会尝试在后台查询。")
                }
            }
        }
        .onChange(of: automaticEnabled) { _, _ in updateSchedule() }
        .onChange(of: backgroundEnabled) { _, _ in updateSchedule() }
        .onChange(of: exitReminderEnabled) { _, enabled in
            if enabled {
                Task {
                    guard await NotificationService.requestAuthorization() else {
                        exitReminderEnabled = false
                        showsNotificationAlert = true
                        return
                    }
                }
            } else {
                BackgroundElectricityRefresh.clearExitReminder()
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            backgroundUnavailable = UIApplication.shared.backgroundRefreshStatus != .available
        }
        .alert("需要允许通知", isPresented: $showsNotificationAlert) {
            Button("打开系统设置") { openSystemSettings() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在系统设置中允许通知，以接收后台电费刷新退出提醒。")
        }
    }

    private var terminationCallbackText: String {
        guard let date = BackgroundElectricityRefresh.lastTerminationCallback else { return "未收到" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func testExitNotification() async {
        testingNotification = true
        defer { testingNotification = false }
        guard await NotificationService.requestAuthorization() else {
            showsNotificationAlert = true
            return
        }
        guard ElectricityRefreshSettings.exitReminderEnabled else { return }
        do {
            try await BackgroundElectricityRefresh.scheduleTestNotification()
            notificationFeedback = "已安排，请切到后台等待 5 秒，确认是否收到通知。"
        } catch {
            notificationFeedback = "通知提交失败：\(error.localizedDescription)"
        }
    }

    private func updateSchedule() {
        app.scheduleBackgroundElectricityRefresh()
        if !ElectricityRefreshSettings.exitReminderEnabled {
            BackgroundElectricityRefresh.clearExitReminder()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
