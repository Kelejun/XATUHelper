import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif

/// 上课提醒单独一节，总设置里夹在中间的入口按钮前面
struct ClassNotificationSection: View {
    @Environment(AppState.self) var app

    @AppStorage(NotificationSettings.classEnabled) var classEnabled = false
    @AppStorage(NotificationSettings.classLead) var classLead = NotificationSettings.defaultClassLead

    var body: some View {
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
        .onChange(of: classEnabled) { _, on in
            Task {
                if on { await requestAuthorizationIfNeeded() }
                await app.rescheduleNotifications()
            }
        }
        .onChange(of: classLead) { _, _ in Task { await app.rescheduleNotifications() } }
    }
}

/// 考试提醒单独一节
struct ExamNotificationSection: View {
    @Environment(AppState.self) var app

    @AppStorage(NotificationSettings.examEnabled) var examEnabled = false
    @AppStorage(NotificationSettings.examLead) var examLead = NotificationSettings.defaultExamLead
    @AppStorage(NotificationSettings.examEve) var examEveOn = true
    @AppStorage(NotificationSettings.examMorning) var examMorningOn = true
    @AppStorage(NotificationSettings.examLeadOn) var examLeadOn = true
    @AppStorage(NotificationSettings.examEveTime) var examEveMinutes = 21 * 60
    @AppStorage(NotificationSettings.examMorningTime) var examMorningMinutes = 8 * 60

    var body: some View {
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
        }
        .onChange(of: examEnabled) { _, on in
            Task {
                if on { await requestAuthorizationIfNeeded() }
                await app.rescheduleNotifications()
            }
        }
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

/// 首次引导里两节一起出现
struct NotificationSettingsSection: View {
    var body: some View {
        Group {
            ClassNotificationSection()
            ExamNotificationSection()
        }
    }
}

/// 第一次进课程表时问一次，之后不再弹
struct NotificationSetupSheet: View {
    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss

    @AppStorage(NotificationSettings.classEnabled) var classEnabled = false
    @AppStorage(NotificationSettings.examEnabled) var examEnabled = false

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
    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss

    @AppStorage(NotificationSettings.examEnabled) var examEnabled = false

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
