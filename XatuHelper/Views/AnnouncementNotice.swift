import SwiftUI

struct AnnouncementNotice: View {
    @ObservedObject var center: AnnouncementCenter
    var canPresent: Bool
    @State private var presented: Announcement?
    @State private var isDismissing = false

    private var eligibleID: String? {
        canPresent && center.presentationBlockers.isEmpty ? center.pending.first?.id : nil
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { presentNext() }
            .onChange(of: eligibleID) { _, _ in presentNext() }
            .sheet(item: $presented, onDismiss: {
                isDismissing = false
                presentNext()
            }) { announcement in
                AnnouncementDetailView(announcement: announcement) {
                    isDismissing = true
                    center.dismiss(announcement.id)
                    presented = nil
                }
            }
    }

    private func presentNext() {
        guard !isDismissing, presented == nil, eligibleID != nil else { return }
        presented = center.pending.first
    }
}

struct AnnouncementDetailView: View {
    let announcement: Announcement
    var receivedAt: Date? = nil
    var onAcknowledge: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let url = announcement.imageURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                            AnnouncementCoverView(url: url)
                                .accessibilityLabel("公告头图")
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            Text(announcement.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                            if let receivedAt {
                                Text("接收于 \(receivedAt.formatted(date: .numeric, time: .standard))")
                                    .font(.caption).foregroundStyle(Color.secondary)
                            }
                            AnnouncementMarkdownView(text: announcement.body)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, announcement.imageURL == nil ? 32 : 0)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                Button(action: onAcknowledge) {
                    Text("确认").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemBackground))
            .navigationTitle("公告")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
    }
}

struct AnnouncementSettingsSection: View {
    @EnvironmentObject private var center: AnnouncementCenter
    var onOpenLatest: (ReceivedAnnouncement) -> Void

    var body: some View {
        Section("公告") {
            if let latest = center.latest {
                Button { onOpenLatest(latest) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最新公告").font(.subheadline).foregroundStyle(Color(uiColor: .secondaryLabel))
                        Text(latest.announcement.title).foregroundStyle(Color.primary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LabeledContent("最新公告", value: "暂无公告")
            }
            NavigationLink {
                AnnouncementHistoryView()
            } label: {
                LabeledContent("历史公告", value: "\(center.history.count)")
            }
        }
    }
}

struct AnnouncementHistoryView: View {
    @EnvironmentObject private var center: AnnouncementCenter
    @State private var selected: ReceivedAnnouncement?
    @State private var confirmsClear = false
    @State private var blocker = UUID()

    var body: some View {
        List {
            if center.history.isEmpty {
                ContentUnavailableView("暂无历史公告", systemImage: "megaphone")
            } else {
                Section {
                    ForEach(center.history) { record in
                        Button { selected = record } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.announcement.title).foregroundStyle(Color.primary)
                                Text("接收于 \(record.receivedAt.formatted(date: .numeric, time: .standard))")
                                    .font(.caption).foregroundStyle(Color.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("删除", role: .destructive) {
                                Task { await center.deleteHistory(record) }
                            }
                        }
                    }
                }
                Section {
                    Button("清除本地所有公告", role: .destructive) { confirmsClear = true }
                }
            }
        }
        .navigationTitle("历史公告")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { center.presentationBlockers.insert(blocker) }
        .onDisappear { center.presentationBlockers.remove(blocker) }
        .alert("清空公告记录？", isPresented: $confirmsClear) {
            Button("暂不清除", role: .cancel) {}
            Button("清除", role: .destructive) { Task { await center.clearHistory() } }
        } message: {
            Text("将从这台设备移除 \(center.history.count) 条公告和已保存的封面。")
        }
        .sheet(item: $selected) { record in
            AnnouncementDetailView(announcement: record.announcement, receivedAt: record.receivedAt) {
                center.acknowledge(record)
                selected = nil
            }
        }
    }
}
