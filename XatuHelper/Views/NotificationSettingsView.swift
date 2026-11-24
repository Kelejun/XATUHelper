import SwiftUI
import UserNotifications

private struct LeadPicker: View {
    let title: String
    let options: [Int]
    @Binding var minutes: Int

    var body: some View {
        Picker(title, selection: $minutes) {
            ForEach(options, id: \.self) { Text("\($0) 分钟").tag($0) }
        }
    }
}

struct ClassNotificationSection: View {
    @EnvironmentObject private var app: AppState
    @AppStorage(NotificationSettings.classEnabled) private var enabled = false
    @AppStorage(NotificationSettings.classLead) private var lead = NotificationSettings.defaultClassLead

    var body: some View {
        Section {
            Toggle("上课提醒", isOn: $enabled)
            LeadPicker(title: "提前", options: NotificationSettings.classLeadOptions, minutes: $lead)
            NotificationSample(trigger: .course(lead))
        } header: {
            Text("上课提醒")
        } footer: {
            Text("通知只管 7 天，期间进入 app 更新。")
        }
        .onChange(of: enabled) { _, on in
            Task {
                if on { await requestAuthorizationIfNeeded() }
                await app.rescheduleNotifications()
            }
        }
        .onChange(of: lead) { _, _ in Task { await app.rescheduleNotifications() } }
    }
}

private struct ExamTimes: Equatable {
    var eve = NotificationSettings.examEveOn
    var morning = NotificationSettings.examMorningOn
    var before = NotificationSettings.examLeadEnabled
    var eveMinutes = NotificationSettings.examEveMinutes
    var morningMinutes = NotificationSettings.examMorningMinutes
    var lead = NotificationSettings.examLeadMinutes

    var count: Int { [eve, morning, before].filter { $0 }.count }
    var eveSample: NotificationSample { .init(trigger: .eve(eveMinutes)) }
    var morningSample: NotificationSample { .init(trigger: .morning(morningMinutes)) }
    var leadSample: NotificationSample { .init(trigger: .examLead(lead)) }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(eve, forKey: NotificationSettings.examEve)
        defaults.set(morning, forKey: NotificationSettings.examMorning)
        defaults.set(before, forKey: NotificationSettings.examLeadOn)
        defaults.set(eveMinutes, forKey: NotificationSettings.examEveTime)
        defaults.set(morningMinutes, forKey: NotificationSettings.examMorningTime)
        defaults.set(lead, forKey: NotificationSettings.examLead)
    }
}

private struct ClockPicker: View {
    @Binding var minutes: Int
    var body: some View {
        let calendar = Calendar.current
        DatePicker("时间", selection: Binding(get: {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: {
            minutes = calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0)
        }), displayedComponents: .hourAndMinute)
    }
}

private struct ExamTimeRows: View {
    @Binding var times: ExamTimes
    let previews: Bool

    var body: some View {
        Toggle("前一天提醒", isOn: $times.eve)
        if previews || times.eve {
            ClockPicker(minutes: $times.eveMinutes)
            if previews { times.eveSample }
        }
        Toggle("当天早间提醒", isOn: $times.morning)
        if previews || times.morning {
            ClockPicker(minutes: $times.morningMinutes)
            if previews { times.morningSample }
        }
        Toggle("开考前提醒", isOn: $times.before)
        if previews || times.before {
            LeadPicker(title: "提前", options: NotificationSettings.examLeadOptions, minutes: $times.lead)
            if previews { times.leadSample }
        }
    }
}

struct ExamNotificationSection: View {
    @EnvironmentObject private var app: AppState
    @AppStorage(NotificationSettings.examEnabled) private var enabled = false
    @State private var times = ExamTimes()

    var body: some View {
        Section("考试提醒") {
            Toggle("考试提醒", isOn: $enabled)
            ExamTimeRows(times: $times, previews: true)
        }
        .onChange(of: enabled) { _, on in
            Task {
                if on { await requestAuthorizationIfNeeded() }
                await app.rescheduleNotifications()
            }
        }
        .onChange(of: times) { _, value in
            value.save()
            Task { await app.rescheduleNotifications() }
        }
    }
}

struct CourseActivitySettingsSection: View {
    @AppStorage(CourseActivityController.beforeKey) private var before = false
    @AppStorage(CourseActivityController.duringKey) private var during = false

    var body: some View {
        Section {
            Toggle("课前", isOn: $before)
            CourseActivityPreview(phase: .before)
            CourseActivityPreview(phase: .between)
        }
        Section {
            Toggle("课中", isOn: $during)
            CourseActivityPreview(phase: .during)
        }
    }
}

private struct PromptActions: View {
    let title: String
    var canEnable = true
    let skip: () -> Void
    let enable: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Button(action: skip) { Text("先不用").frame(maxWidth: .infinity) }
            Button(action: enable) { Text(title).frame(maxWidth: .infinity) }.disabled(!canEnable)
        }
        .buttonStyle(.borderedProminent).tint(.blue).controlSize(.large)
    }
}

struct NotificationSetupSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var activityStep = NotificationSettings.hasPrompted
    @State private var lead = NotificationSettings.classLeadMinutes
    @State private var before = UserDefaults.standard.bool(forKey: CourseActivityController.beforeKey)
    @State private var during = UserDefaults.standard.bool(forKey: CourseActivityController.duringKey)
    @State private var previewDuring = false
    @State private var requesting = false
    @State private var denied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if activityStep {
                    Text("开启实时活动与灵动岛？").font(.title2.bold())
                    Text("在锁定屏幕上查看课程，支持灵动岛的机型也会在岛上显示。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("预览阶段", selection: $previewDuring) {
                        Text("课前预览").tag(false)
                        Text("课中预览").tag(true)
                    }.pickerStyle(.segmented)
                    CourseActivityPreview(phase: previewDuring ? .during : .before)
                    if !previewDuring { CourseActivityPreview(phase: .between) }
                    Toggle("课前", isOn: $before)
                    Toggle("课中", isOn: $during)
                    PromptActions(title: "完成", skip: finishActivity) {
                        UserDefaults.standard.set(before, forKey: CourseActivityController.beforeKey)
                        UserDefaults.standard.set(during, forKey: CourseActivityController.duringKey)
                        finishActivity()
                    }
                } else {
                    Text("上课前，要提醒你吗？").font(.title2.bold())
                    Text("上课前发一条通知，课程和教室抬眼就能看到。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NotificationSample(trigger: .course(lead))
                    LabeledContent("提醒时间") {
                        LeadPicker(title: "课前", options: NotificationSettings.classLeadOptions, minutes: $lead)
                            .labelsHidden()
                    }
                    PromptActions(title: "开启课程提醒", skip: next) {
                        guard !requesting else { return }
                        requesting = true
                        Task {
                            let allowed = await NotificationService.requestAuthorization()
                            if allowed {
                                UserDefaults.standard.set(lead, forKey: NotificationSettings.classLead)
                                UserDefaults.standard.set(true, forKey: NotificationSettings.classEnabled)
                                await app.rescheduleNotifications()
                            }
                            requesting = false
                            if allowed { next() } else { denied = true }
                        }
                    }.disabled(requesting)
                }
            }.padding(.horizontal, 22).padding(.vertical, 30)
        }
        .withReminderPreviewData()
        .interactiveDismissDisabled(requesting)
        .presentationDragIndicator(.visible)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(activityStep ? (previewDuring ? 430 : 535) : 350), .large])
        .alert("通知权限未开启", isPresented: $denied) {
            Button("继续", action: next)
        } message: { Text("可在系统设置中允许 XATune 发送通知。") }
    }

    private func next() {
        NotificationSettings.hasPrompted = true
        if UserDefaults.standard.bool(forKey: CourseActivityController.promptedKey) { dismiss() }
        else { activityStep = true }
    }

    private func finishActivity() {
        UserDefaults.standard.set(true, forKey: CourseActivityController.promptedKey)
        dismiss()
    }
}

struct ExamNotificationSetupSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var times = ExamTimes()
    @State private var editing = false
    @State private var requesting = false
    @State private var denied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("考试前，要提醒你吗？").font(.title2.bold())
                Text("到点查看开考时间、考场和座位号。").font(.subheadline).foregroundStyle(.secondary)
                if times.eve { times.eveSample }
                else if times.morning { times.morningSample }
                else if times.before { times.leadSample }
                DisclosureGroup(isExpanded: $editing) {
                    VStack(spacing: 12) { ExamTimeRows(times: $times, previews: false) }.padding(.vertical, 8)
                } label: {
                    LabeledContent("提醒时间", value: "\(times.count) 个时段")
                }
                PromptActions(title: "开启考前提醒", canEnable: times.count > 0, skip: finish) {
                    guard !requesting else { return }
                    requesting = true
                    Task {
                        let allowed = await NotificationService.requestAuthorization()
                        if allowed {
                            times.save()
                            UserDefaults.standard.set(true, forKey: NotificationSettings.examEnabled)
                            await app.rescheduleNotifications()
                        }
                        requesting = false
                        if allowed { finish() } else { denied = true }
                    }
                }.disabled(requesting)
            }.padding(.horizontal, 22).padding(.vertical, 30)
        }
        .presentationDetents(typeSize.isAccessibilitySize || editing ? [.large] : [.height(350), .large])
        .presentationDragIndicator(.visible)
        .withReminderPreviewData()
        .interactiveDismissDisabled(requesting)
        .alert("通知权限未开启", isPresented: $denied) {
            Button("完成", action: finish)
        } message: { Text("可在系统设置中允许 XATune 发送通知。") }
    }

    private func finish() {
        NotificationSettings.hasPromptedExam = true
        dismiss()
    }
}

private func requestAuthorizationIfNeeded() async {
    if await NotificationService.authorizationStatus() == .notDetermined {
        _ = await NotificationService.requestAuthorization()
    }
}
