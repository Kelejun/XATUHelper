import SwiftUI
import UserNotifications

/// 提醒开关，课程表设置和首次引导共用
struct NotificationSettingsSection: View {
    @EnvironmentObject var app: AppState

    @AppStorage(NotificationSettings.classEnabled) private var classEnabled = false
    @AppStorage(NotificationSettings.classLead) private var classLead = NotificationSettings.defaultClassLead
    @AppStorage(NotificationSettings.examEnabled) private var examEnabled = false
    @AppStorage(NotificationSettings.examLead) private var examLead = NotificationSettings.defaultExamLead

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

            Toggle("考试提醒", isOn: $examEnabled)
            if examEnabled {
                Picker("开考前", selection: $examLead) {
                    ForEach(NotificationSettings.examLeadOptions, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
            }
        } header: {
            Text("提醒")
        } footer: {
            Text("上课提醒只排未来 7 天，每次刷新课表会重新排。考试提醒会在前一天 21:00、当天 08:00 和开考前再各弹一次。")
        }
        .onChange(of: classEnabled) { _, on in
            Task { await update(classOn: on) }
        }
        .onChange(of: examEnabled) { _, on in
            Task { await update(examOn: on) }
        }
        .onChange(of: classLead) { _, _ in
            Task { await app.rescheduleNotifications() }
        }
        .onChange(of: examLead) { _, _ in
            Task { await app.rescheduleNotifications() }
        }
    }

    private func update(classOn: Bool) async {
        if classOn { await requestAuthorizationIfNeeded() }
        await app.rescheduleNotifications()
    }

    private func update(examOn: Bool) async {
        if examOn { await requestAuthorizationIfNeeded() }
        await app.rescheduleNotifications()
    }
}

/// 第一次进课程表时问一次，之后不再弹
struct NotificationSetupSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @AppStorage(NotificationSettings.classEnabled) private var classEnabled = false
    @AppStorage(NotificationSettings.examEnabled) private var examEnabled = false
    @AppStorage(NotificationSettings.classLead) private var classLead = NotificationSettings.defaultClassLead
    @AppStorage(NotificationSettings.examLead) private var examLead = NotificationSettings.defaultExamLead

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("要不要在每节课前提醒你？")
                        .font(.headline)
                    Text("通知由系统到点弹出，App 不用开着。内容用的是本地缓存的课表，所以课表改了记得刷新一次。")
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

/// 打开开关时顺手要一下系统权限
func requestAuthorizationIfNeeded() async {
    let status = await NotificationService.authorizationStatus()
    guard status == .notDetermined else { return }
    _ = await NotificationService.requestAuthorization()
}

/// 第一次进考试页时单独问一次考试提醒
struct ExamNotificationSetupSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @AppStorage(NotificationSettings.examEnabled) private var examEnabled = false
    @AppStorage(NotificationSettings.examLead) private var examLead = NotificationSettings.defaultExamLead

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("考试要不要提前提醒？")
                        .font(.headline)
                    Text("会在前一天 21:00、当天 08:00 和开考前再各弹一次，内容用本地缓存的考试安排。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("考试提醒", isOn: $examEnabled)
                    if examEnabled {
                        Picker("开考前", selection: $examLead) {
                            ForEach(NotificationSettings.examLeadOptions, id: \.self) { minutes in
                                Text("\(minutes) 分钟").tag(minutes)
                            }
                        }
                    }
                }

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
            .onAppear {
                if !NotificationSettings.examOn { examEnabled = true }
            }
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
