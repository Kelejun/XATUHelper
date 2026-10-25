import SwiftUI
import UserNotifications

/// 提醒开关：总设置里直接展开，首次引导也复用
struct NotificationSettingsSection: View {
    @EnvironmentObject var app: AppState

    @AppStorage(NotificationSettings.classEnabled) private var classEnabled = false
    @AppStorage(NotificationSettings.classLead) private var classLead = NotificationSettings.defaultClassLead
    @AppStorage(NotificationSettings.examEnabled) private var examEnabled = false
    @AppStorage(NotificationSettings.examLead) private var examLead = NotificationSettings.defaultExamLead
    @AppStorage(NotificationSettings.examEve) private var examEveOn = true
    @AppStorage(NotificationSettings.examMorning) private var examMorningOn = true
    @AppStorage(NotificationSettings.examLeadOn) private var examLeadOn = true
    @AppStorage(NotificationSettings.examEveTime) private var examEveMinutes = 21 * 60
    @AppStorage(NotificationSettings.examMorningTime) private var examMorningMinutes = 8 * 60

    var body: some View {
        Group {
            Section {
                Toggle("上课提醒", isOn: $classEnabled)
                if classEnabled {
                    Picker("提前", selection: $classLead) {
                        ForEach(NotificationSettings.classLeadOptions, id: \.self) { minutes in
                            Text("\(minutes) 分钟").tag(minutes)
                        }
                    }
                }
            } header: {
                Text("上课提醒")
            } footer: {
                Text("通知只管 7 天，期间进入 app 更新。")
            }

            Section {
                Toggle("考试提醒", isOn: $examEnabled)
                if examEnabled {
                    Toggle("前一天提醒", isOn: $examEveOn)
                    if examEveOn {
                        DatePicker("时间", selection: timeBinding($examEveMinutes),
                                   displayedComponents: .hourAndMinute)
                    }

                    Toggle("当天早间提醒", isOn: $examMorningOn)
                    if examMorningOn {
                        DatePicker("时间", selection: timeBinding($examMorningMinutes),
                                   displayedComponents: .hourAndMinute)
                    }

                    Toggle("开考前提醒", isOn: $examLeadOn)
                    if examLeadOn {
                        Picker("提前", selection: $examLead) {
                            ForEach(NotificationSettings.examLeadOptions, id: \.self) { minutes in
                                Text("\(minutes) 分钟").tag(minutes)
                            }
                        }
                    }
                }
            } header: {
                Text("考试提醒")
            } footer: {
                Text("三种提醒各自独立，关掉哪个就不发哪一条。")
            }
        }
        .onChange(of: classEnabled) { _, on in
            Task {
                if on { await requestAuthorizationIfNeeded() }
                await app.rescheduleNotifications()
            }
        }
        .onChange(of: examEnabled) { _, on in
            Task {
                if on { await requestAuthorizationIfNeeded() }
                await app.rescheduleNotifications()
            }
        }
        .onChange(of: classLead) { _, _ in Task { await app.rescheduleNotifications() } }
        .onChange(of: examLead) { _, _ in Task { await app.rescheduleNotifications() } }
        .onChange(of: examEveOn) { _, _ in Task { await app.rescheduleNotifications() } }
        .onChange(of: examMorningOn) { _, _ in Task { await app.rescheduleNotifications() } }
        .onChange(of: examLeadOn) { _, _ in Task { await app.rescheduleNotifications() } }
        .onChange(of: examEveMinutes) { _, _ in Task { await app.rescheduleNotifications() } }
        .onChange(of: examMorningMinutes) { _, _ in Task { await app.rescheduleNotifications() } }
    }

    /// 把「从零点算起的分钟数」包成时间选择器要的 Date
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                let base = calendar.startOfDay(for: Date())
                return calendar.date(byAdding: .minute, value: minutes.wrappedValue, to: base) ?? base
            },
            set: { newValue in
                let calendar = Calendar.current
                minutes.wrappedValue = calendar.component(.hour, from: newValue) * 60
                    + calendar.component(.minute, from: newValue)
            }
        )
    }
}

/// 第一次进课程表时问一次，之后不再弹
struct NotificationSetupSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @AppStorage(NotificationSettings.classEnabled) private var classEnabled = false
    @AppStorage(NotificationSettings.examEnabled) private var examEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("要不要在每节课前提醒你？")
                        .font(.headline)
                    Text("通知由系统到点弹出，App 不用开着。内容用的是本地缓存的课表，课表改了记得刷新一次。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                NotificationSettingsSection()

                Section {
                    Button("开启提醒") {
                        Task { await enable() }
                    }
                    Button("先不用") {
                        NotificationSettings.hasPrompted = true
                        NotificationSettings.hasPromptedExam = true
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("提醒")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func enable() async {
        NotificationSettings.hasPrompted = true
        NotificationSettings.hasPromptedExam = true
        classEnabled = true
        examEnabled = true
        _ = await NotificationService.requestAuthorization()
        await app.rescheduleNotifications()
        dismiss()
    }
}

/// 第一次进考试页时单独问一次考试提醒
struct ExamNotificationSetupSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @AppStorage(NotificationSettings.examEnabled) private var examEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("考试要不要提前提醒？")
                        .font(.headline)
                    Text("前一天、当天早间和开考前各弹一次，内容用本地缓存的考试安排。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                NotificationSettingsSection()

                Section {
                    Button("开启提醒") {
                        Task { await enable() }
                    }
                    Button("先不用") {
                        NotificationSettings.hasPromptedExam = true
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("考试提醒")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func enable() async {
        NotificationSettings.hasPromptedExam = true
        examEnabled = true
        _ = await NotificationService.requestAuthorization()
        await app.rescheduleNotifications()
        dismiss()
    }
}

/// 打开开关时顺手要一下系统权限
func requestAuthorizationIfNeeded() async {
    let status = await NotificationService.authorizationStatus()
    guard status == .notDetermined else { return }
    _ = await NotificationService.requestAuthorization()
}
