import SwiftUI

/// 考试安排。数据来自教务「我的考试」，按日期分组排。
struct ExamView: View {
    @EnvironmentObject var app: AppState

    private var groups: [(key: String, items: [ExamRecord])] {
        let grouped = Dictionary(grouping: app.exams) { $0.dateKey }
        return grouped
            .map { (key: $0.key, items: $0.value.sorted { $0.time < $1.time }) }
            .sorted { lhs, rhs in
                // 认不出日期的排最后
                switch (lhs.key.isEmpty, rhs.key.isEmpty) {
                case (false, false): return lhs.key < rhs.key
                case (false, true): return true
                case (true, false): return false
                default: return false
                }
            }
    }

    var body: some View {
        List {
            if let error = app.examsError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if app.exams.isEmpty {
                if app.examsLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在查考试安排…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if app.examsError == nil {
                    Section {
                        ContentUnavailableView(
                            "还没有考试安排",
                            systemImage: "calendar.badge.clock",
                            description: Text("学校排考后会出现在这里")
                        )
                    }
                }
            } else {
                ForEach(groups, id: \.key) { group in
                    Section {
                        ForEach(group.items) { exam in
                            row(exam)
                        }
                    } header: {
                        Text(headerText(for: group.key, count: group.items.count))
                    }
                }
            }
        }
        .navigationTitle("考试安排")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.refreshExams() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await app.refreshExams() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(app.examsLoading)
            }
        }
        .task {
            if app.exams.isEmpty { await app.refreshExams() }
        }
    }

    private func row(_ exam: ExamRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exam.course.isEmpty ? (exam.name.isEmpty ? "考试" : exam.name) : exam.course)
                .font(.body.weight(.medium))

            if !exam.name.isEmpty && exam.name != exam.course {
                Text(exam.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !exam.time.isEmpty {
                    Label(exam.time, systemImage: "clock")
                }
                if !exam.room.isEmpty {
                    Label(exam.room, systemImage: "mappin.and.ellipse")
                }
                if !exam.seat.isEmpty {
                    Label("座位 \(exam.seat)", systemImage: "chair.lounge")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !exam.note.isEmpty {
                Text(exam.note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func headerText(for key: String, count: Int) -> String {
        guard !key.isEmpty else { return "待定（\(count)）" }
        guard let date = ExamView.parser.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        ExamView()
            .environmentObject(AppState())
    }
}
