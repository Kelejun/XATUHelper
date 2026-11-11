import SwiftUI
import UIKit

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsContent()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .modifier(SettingsAnnouncementBlocker())
    }
}

struct SettingsContent: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CheckinLocationSettings.revealedKey) private var showCheckinLocation = false
    @State private var versionTapCount = 0
    @EnvironmentObject private var announcements: AnnouncementCenter
    @State private var selectedAnnouncement: ReceivedAnnouncement?

    static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let commit = BuildInfo.commit.isEmpty || BuildInfo.commit == "dev" ? build : BuildInfo.commit
        return "\(short)（\(commit)）"
    }

    var body: some View {
        Form {
            Section("账号") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountName)
                                .font(.title3.weight(.semibold))
                            Text("学号：\(app.studentID.isEmpty ? "—" : app.studentID)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    Button(role: .destructive) {
                        app.logout()
                        dismiss()
                    } label: {
                        Text("退出登录")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.vertical, 8)
            }

            AnnouncementSettingsSection { selectedAnnouncement = $0 }

            Section("通用") {
                if !app.isDemoMode {
                    NavigationLink {
                        Form {
                            ElectricityRefreshSettingsSection()
                        }
                        .formStyle(.grouped)
                        .navigationTitle("电费更新")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Text("电费更新")
                    }
                    NavigationLink {
                        ReminderSettingsContent()
                    } label: {
                        Text("提醒")
                    }
                }
                NavigationLink {
                    TimetableSettingsContent()
                } label: {
                    Text("课程表")
                }
            }

            Section {
                Button {
                    versionTapCount += 1
                    if versionTapCount >= 5 {
                        showCheckinLocation = true
                        versionTapCount = 0
                    }
                } label: {
                    LabeledContent("版本", value: Self.versionText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                PrivacyPolicyLink()
                Link(destination: URL(string: "https://qm.qq.com/q/k1mGynJlrW")!) {
                    LabeledContent {
                        Text("934935585")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("加入QQ交流群")
                    }
                }
                Link(destination: URL(string: "https://github.com/Kelejun/XATUHelper")!) {
                    LabeledContent("GitHub 仓库", value: "Kelejun/XATUHelper")
                }
            } header: {
                Text("App")
            } footer: {
                if !BuildInfo.builtAt.isEmpty {
                    Text("构建于 \(BuildInfo.builtAt)")
                }
            }

            DiagnosticsSettingsSections()
        }
        .sheet(item: $selectedAnnouncement) { record in
            AnnouncementDetailView(announcement: record.announcement, receivedAt: record.receivedAt) {
                announcements.acknowledge(record)
                selectedAnnouncement = nil
            }
        }
        .task {
            if app.plan.studentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               app.isLoggedIn, !app.isDemoMode {
                await app.refreshPlan()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SettingsAnnouncementBlocker())
    }

    private var accountName: String {
        let name = app.plan.studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未获取姓名" : name
    }
}

private struct ReminderSettingsContent: View {
    var body: some View {
        Form {
            ClassNotificationSection()
            ExamNotificationSection()
        }
        .formStyle(.grouped)
        .navigationTitle("提醒")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DiagnosticsSettingsSections: View {
    @AppStorage("showDiagnostics") private var showDiagnostics = false
    @AppStorage(CheckinLocationSettings.revealedKey) private var showCheckinLocation = false

    var body: some View {
        Group {
            Section {
                Toggle("显示诊断数据", isOn: $showDiagnostics)
                if showDiagnostics {
                    Button("复制诊断数据") {
                        UIPasteboard.general.string = EamsService.diagnosticDump
                    }
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("如果出现解析问题，可复制诊断信息给开发者处理")
            }

            if showCheckinLocation {
                CheckinLocationSettingsSection()
            }
        }
    }
}

struct TimetableSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimetableSettingsContent()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .modifier(SettingsAnnouncementBlocker())
    }
}

struct TimetableSettingsContent: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draftWeek = 1
    @AppStorage("hideWeekend") private var hideWeekend = false

    private static let weekRange = TimetableDates.weeks

    var body: some View {
        Form {
            Section("显示") {
                Toggle("隐藏周末", isOn: $hideWeekend)
                if let fetchedAt = app.fetchedAt {
                    LabeledContent(
                        "上次更新",
                        value: fetchedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            if !app.isDemoMode {
                Section {
                    NavigationLink {
                        ReminderSettingsContent()
                    } label: {
                        Text("提醒")
                    }
                }
            }

            Section {
                Picker("现在实际是第几周", selection: $draftWeek) {
                    ForEach(Self.weekRange, id: \.self) { value in
                        Text("第 \(value) 周").tag(value)
                    }
                }
                Button("按这个周次校正") {
                    app.calibrate(currentWeek: draftWeek)
                    dismiss()
                }
            } header: {
                Text("周次校正")
            } footer: {
                Text("学校校历如果和默认的不一样，在这里改一次就行。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("课程表设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draftWeek = app.currentWeek
        }
    }
}

// 在导航容器上保留阻止标识，进入子页面时继续延后自动公告。
private struct SettingsAnnouncementBlocker: ViewModifier {
    @EnvironmentObject private var announcements: AnnouncementCenter
    @State private var blocker = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { announcements.presentationBlockers.insert(blocker) }
            .onDisappear { announcements.presentationBlockers.remove(blocker) }
    }
}
