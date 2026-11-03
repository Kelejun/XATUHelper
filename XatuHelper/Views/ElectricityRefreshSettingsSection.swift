import SwiftUI
import UIKit

struct ElectricityRefreshSettingsSection: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ElectricityRefreshSettings.automaticKey) private var automaticEnabled = true
    @AppStorage(ElectricityRefreshSettings.backgroundKey) private var backgroundEnabled = false
    @AppStorage(ElectricityRefreshSettings.exitReminderKey) private var exitReminderEnabled = false
    @State private var showsNotificationAlert = false
    @State private var backgroundUnavailable = false

    var body: some View {
        Section {
            Toggle("每日自动刷新电费余额", isOn: $automaticEnabled)
            if automaticEnabled {
                Toggle("后台自动刷新", isOn: $backgroundEnabled)
                if backgroundEnabled {
                    Toggle("退出时提醒", isOn: $exitReminderEnabled)
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
                        Text("退出时提醒需要通知权限。仅在系统通知 App 即将退出时尝试发送；App 已挂起或被强制终止时可能无法提醒。")
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
