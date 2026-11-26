import ActivityKit
import SwiftUI
import UserNotifications

private struct LeadPicker: View {
    let title: String
    let options: [Int]
    @Binding var minutes: Int

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $minutes) {
                ForEach(options, id: \.self) { Text("\($0) 分钟").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
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
            if enabled {
                LeadPicker(title: "提前", options: NotificationSettings.classLeadOptions, minutes: $lead)
                NotificationSample(trigger: .course(lead))
            }
        } header: {
            Text("上课提醒")
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
        .datePickerStyle(.compact)
    }
}

private struct ExamTimeRows: View {
    @Binding var times: ExamTimes
    let previews: Bool

    var body: some View {
        Toggle("前一天提醒", isOn: $times.eve)
        if times.eve {
            ClockPicker(minutes: $times.eveMinutes)
            if previews { times.eveSample }
        }
        Toggle("当天早间提醒", isOn: $times.morning)
        if times.morning {
            ClockPicker(minutes: $times.morningMinutes)
            if previews { times.morningSample }
        }
        Toggle("开考前提醒", isOn: $times.before)
        if times.before {
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
            if enabled {
                ExamTimeRows(times: $times, previews: true)
            }
        }
        .onChange(of: enabled) { _, on in
            if on && times.count == 0 {
                times.eve = true
                times.morning = true
                times.before = true
                times.save()
            }
            Task {
                if on { await requestAuthorizationIfNeeded() }
                await app.rescheduleNotifications()
            }
        }
        .onChange(of: times) { _, value in
            value.save()
            if value.count == 0 && enabled {
                enabled = false
            }
            Task { await app.rescheduleNotifications() }
        }
    }
}

struct CourseActivitySettingsSection: View {
    @AppStorage(CourseActivityController.beforeKey) private var before = false
    @AppStorage(CourseActivityController.beforeLeadKey) private var beforeLead = CourseActivityController.defaultBeforeLeadMinutes
    @AppStorage(CourseActivityController.duringKey) private var during = false
    @AppStorage(CourseActivityController.beforeExamKey) private var beforeExam = false
    @AppStorage(CourseActivityController.examLeadKey) private var examLead = CourseActivityController.defaultExamLeadMinutes
    @Environment(\.scenePhase) private var scenePhase
    @State private var activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

    var body: some View {
        Section {
            Toggle("课前", isOn: $before)
            if before {
                LeadPicker(title: "提前", options: CourseActivityController.beforeLeadOptions, minutes: $beforeLead)
            }
            CourseActivityPreview(phase: .before(beforeLead))
            CourseActivityPreview(phase: .between)
        } footer: {
            if (before || during || beforeExam) && !activitiesEnabled {
                Text("系统设置中未开启实时活动，开启后才会显示。")
            }
        }
        Section {
            Toggle("课中", isOn: $during)
            CourseActivityPreview(phase: .during)
        }
        Section {
            Toggle("考前", isOn: $beforeExam)
            if beforeExam {
                LeadPicker(title: "提前", options: CourseActivityController.examLeadOptions, minutes: $examLead)
            }
            CourseActivityPreview(phase: .exam(examLead))
        }
        .onAppear { activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            }
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
        VStack(spacing: 0) {
            Divider()
            layout {
                Button(action: skip) { Text("先不用").frame(maxWidth: .infinity) }
                Button(action: enable) { Text(title).frame(maxWidth: .infinity) }.disabled(!canEnable)
            }
            .buttonStyle(.borderedProminent).tint(.blue).controlSize(.large)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(.bar)
    }
}

struct NotificationSetupSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var activityStep = NotificationSettings.hasPrompted
    @State private var detent: PresentationDetent = NotificationSettings.hasPrompted ? .large : .height(420)
    @State private var lead = NotificationSettings.classLeadMinutes
    @State private var before = UserDefaults.standard.bool(forKey: CourseActivityController.beforeKey)
    @State private var beforeLead = CourseActivityController.beforeLeadMinutes
    @State private var during = UserDefaults.standard.bool(forKey: CourseActivityController.duringKey)
    @State private var requesting = false
    @State private var denied = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if activityStep { activityContent }
                    else { courseContent }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 30)
                .padding(.bottom, 18)
                .id("promptTop")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if activityStep { activityActions }
                else { courseActions }
            }
            .onChange(of: activityStep) { _, _ in
                proxy.scrollTo("promptTop", anchor: .top)
            }
        }
        .withReminderPreviewData()
        .interactiveDismissDisabled(requesting)
        .presentationDragIndicator(.visible)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(420), .large], selection: $detent)
        .alert("通知权限未开启", isPresented: $denied) {
            Button("继续", action: next)
        } message: { Text("可在系统设置中允许 XATune 发送通知。") }
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开启实时活动与灵动岛？").font(.title2.bold())
            Text("在锁定屏幕上查看课程，支持灵动岛的机型也会在岛上显示。")
                .font(.subheadline).foregroundStyle(.secondary)
            Toggle("课前", isOn: $before)
            if before {
                LeadPicker(title: "提前", options: CourseActivityController.beforeLeadOptions, minutes: $beforeLead)
            }
            CourseActivityPreview(phase: .before(beforeLead))
            CourseActivityPreview(phase: .between)
            Toggle("课中", isOn: $during)
            CourseActivityPreview(phase: .during)
        }
        .transition(.opacity)
    }

    private var activityActions: some View {
        PromptActions(title: "完成", skip: {
            UserDefaults.standard.set(false, forKey: CourseActivityController.beforeKey)
            UserDefaults.standard.set(false, forKey: CourseActivityController.duringKey)
            finishActivity()
        }) {
            UserDefaults.standard.set(before, forKey: CourseActivityController.beforeKey)
            if before {
                UserDefaults.standard.set(beforeLead, forKey: CourseActivityController.beforeLeadKey)
            }
            UserDefaults.standard.set(during, forKey: CourseActivityController.duringKey)
            finishActivity()
        }
    }

    private var courseContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("上课前，要提醒你吗？").font(.title2.bold())
            Text("上课前发一条通知，课程和教室抬眼就能看到。")
                .font(.subheadline).foregroundStyle(.secondary)
            NotificationSample(trigger: .course(lead))
            LabeledContent("提醒时间") {
                Picker("提醒时间", selection: $lead) {
                    ForEach(NotificationSettings.classLeadOptions, id: \.self) {
                        Text("课前 \($0) 分钟").tag($0)
                    }
                }.pickerStyle(.menu).labelsHidden()
            }
        }
        .transition(.opacity)
    }

    private var courseActions: some View {
        PromptActions(title: "开启课程提醒", skip: {
            UserDefaults.standard.set(false, forKey: NotificationSettings.classEnabled)
            Task { await app.rescheduleNotifications() }
            next()
        }) {
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

    private func next() {
        NotificationSettings.hasPrompted = true
        if UserDefaults.standard.bool(forKey: CourseActivityController.promptedKey) { dismiss() }
        else {
            withAnimation {
                detent = .large
                activityStep = true
            }
        }
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
    @State private var activityStep = NotificationSettings.hasPromptedExam
    @State private var times = ExamTimes()
    @State private var editing = false
    @State private var beforeExam = UserDefaults.standard.bool(forKey: CourseActivityController.beforeExamKey)
    @State private var examLead = CourseActivityController.examLeadMinutes
    @State private var detent: PresentationDetent = NotificationSettings.hasPromptedExam ? .large : .height(450)
    @State private var requesting = false
    @State private var denied = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if activityStep { examActivityContent }
                    else { examNotificationContent }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 30)
                .padding(.bottom, 18)
                .id("examPromptTop")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if activityStep { examActivityActions }
                else { examNotificationActions }
            }
            .onChange(of: activityStep) { _, _ in
                proxy.scrollTo("examPromptTop", anchor: .top)
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(450), .large], selection: $detent)
        .onChange(of: editing) { _, expanded in
            guard !activityStep else { return }
            withAnimation {
                detent = expanded || typeSize.isAccessibilitySize ? .large : .height(450)
            }
        }
        .presentationDragIndicator(.visible)
        .withReminderPreviewData()
        .interactiveDismissDisabled(requesting)
        .alert("通知权限未开启", isPresented: $denied) {
            Button("继续", action: next)
        } message: { Text("可在系统设置中允许 XATune 发送通知。") }
    }

    private var examNotificationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("考试前，要提醒你吗？").font(.title2.bold())
            Text("到点查看开考时间、考场和座位号。").font(.subheadline).foregroundStyle(.secondary)
            if times.eve { times.eveSample }
            else if times.morning { times.morningSample }
            else if times.before { times.leadSample }
            Button {
                withAnimation { editing.toggle() }
            } label: {
                HStack {
                    Text("提醒时间")
                    Spacer()
                    Text("\(times.count) 个时段").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(editing ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(editing ? "已展开" : "已折叠")
            if editing {
                VStack(alignment: .leading, spacing: 12) {
                    ExamTimeRows(times: $times, previews: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
        .transition(.opacity)
    }

    private var examNotificationActions: some View {
        PromptActions(title: "开启考前提醒", canEnable: times.count > 0, skip: {
            UserDefaults.standard.set(false, forKey: NotificationSettings.examEnabled)
            Task { await app.rescheduleNotifications() }
            next()
        }) {
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
                if allowed { next() } else { denied = true }
            }
        }.disabled(requesting)
    }

    private var examActivityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开启实时活动与灵动岛？").font(.title2.bold())
            Text("在锁定屏幕上查看考试倒计时与考场，支持灵动岛的机型也会在岛上显示。")
                .font(.subheadline).foregroundStyle(.secondary)
            Toggle("考前", isOn: $beforeExam)
            if beforeExam {
                LeadPicker(title: "提前", options: CourseActivityController.examLeadOptions, minutes: $examLead)
            }
            CourseActivityPreview(phase: .exam(examLead))
        }
        .transition(.opacity)
    }

    private var examActivityActions: some View {
        PromptActions(title: "完成", skip: {
            UserDefaults.standard.set(false, forKey: CourseActivityController.beforeExamKey)
            finishActivity()
        }) {
            UserDefaults.standard.set(beforeExam, forKey: CourseActivityController.beforeExamKey)
            if beforeExam {
                UserDefaults.standard.set(examLead, forKey: CourseActivityController.examLeadKey)
            }
            finishActivity()
        }
    }

    private func next() {
        NotificationSettings.hasPromptedExam = true
        if UserDefaults.standard.bool(forKey: CourseActivityController.examPromptedKey) { dismiss() }
        else {
            withAnimation {
                detent = .large
                activityStep = true
            }
        }
    }

    private func finishActivity() {
        UserDefaults.standard.set(true, forKey: CourseActivityController.examPromptedKey)
        dismiss()
    }
}

private func requestAuthorizationIfNeeded() async {
    if await NotificationService.authorizationStatus() == .notDetermined {
        _ = await NotificationService.requestAuthorization()
    }
}
