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

    static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let commit = BuildInfo.commit.isEmpty || BuildInfo.commit == "dev" ? build : BuildInfo.commit
        return "\(short)（\(commit)）"
    }

    var body: some View {
        Form {
            Section("账号") {
                LabeledContent("学号", value: app.studentID.isEmpty ? "—" : app.studentID)
                Button("退出登录", role: .destructive) {
                    app.logout()
                    dismiss()
                }
            }

            Section("通用") {
                NavigationLink {
                    GeneralSettingsContent()
                } label: {
                    Label("通用设置", systemImage: "gearshape")
                }
            }

            Section("课程表") {
                NavigationLink {
                    TimetableSettingsContent()
                } label: {
                    Label("课程表设置", systemImage: "calendar")
                }
            }

            Section("诊断") {
                NavigationLink {
                    DiagnosticsSettingsContent()
                } label: {
                    Label("诊断设置", systemImage: "stethoscope")
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
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SettingsAnnouncementBlocker())
    }
}

private struct GeneralSettingsContent: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var announcements: AnnouncementCenter
    @State private var selectedAnnouncement: ReceivedAnnouncement?

    var body: some View {
        Form {
            if !app.isDemoMode {
                Section {
                    NavigationLink {
                        Form {
                            ElectricityRefreshSettingsSection()
                        }
                        .formStyle(.grouped)
                        .navigationTitle("电费刷新")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("电费刷新", systemImage: "bolt")
                    }
                    NavigationLink {
                        Form {
                            ExamNotificationSection()
                        }
                        .formStyle(.grouped)
                        .navigationTitle("考试提醒")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("考试提醒", systemImage: "bell")
                    }
                }
            }

            AnnouncementSettingsSection { selectedAnnouncement = $0 }
        }
        .formStyle(.grouped)
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedAnnouncement) { record in
            AnnouncementDetailView(announcement: record.announcement, receivedAt: record.receivedAt) {
                announcements.acknowledge(record)
                selectedAnnouncement = nil
            }
        }
    }
}

private struct DiagnosticsSettingsContent: View {
    @AppStorage("showDiagnostics") private var showDiagnostics = false
    @AppStorage(CheckinLocationSettings.revealedKey) private var showCheckinLocation = false

    var body: some View {
        Form {
            Section {
                Toggle("显示诊断数据", isOn: $showDiagnostics)
                if showDiagnostics {
                    Button("复制诊断数据") {
                        UIPasteboard.general.string = EamsService.diagnosticDump
                    }
                }
            } header: {
                Text("诊断数据")
            } footer: {
                Text("如果出现解析问题，可复制诊断信息给开发者处理")
            }

            if showCheckinLocation {
                CheckinLocationSettingsSection()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
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
                ClassNotificationSection()
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
