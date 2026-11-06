import SwiftUI

struct TimetableHistorySheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEdit: TimetableEdit?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if app.timetableEdits.isEmpty {
                    ContentUnavailableView("暂无课表修改", systemImage: "calendar")
                }
                ForEach(app.timetableEdits.reversed()) { edit in
                    Button {
                        selectedEdit = edit
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(edit.title).foregroundStyle(.primary)
                            if let weeks = app.pendingTimetableEdits[edit.id] {
                                Text("待确认 · 第 \(weeks.map(String.init).joined(separator: "、")) 周")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if let edit = app.timetableEdits.last {
                    Button("撤销上一次修改") {
                        do {
                            try app.saveTimetableEdits(app.timetableEdits.filter { $0.id != edit.id })
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("我的课表修改")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .sheet(item: $selectedEdit) { edit in
                TimetableHistoryDetail(editID: edit.id)
            }
        }
    }
}

private struct TimetableHistoryDetail: View {
    let editID: UUID
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmUndo = false
    @State private var replacement: Replacement?

    private struct Replacement: Identifiable {
        var edit: TimetableEdit
        var conflicts: [TimetableConflict]
        var id: UUID { edit.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if let edit = app.timetableEdits.first(where: { $0.id == editID }) {
                    Section {
                        Text(edit.title)
                        if let source = edit.source {
                            let weeks = source.weeks.map { $0.resolve(monday: app.semesterStartMonday) }
                            LabeledContent("影响周次", value: weeks.map(String.init).joined(separator: "、"))
                        }
                    }
                    if let source = edit.source, let weeks = app.pendingTimetableEdits[edit.id] {
                        pendingSections(edit: edit, source: source, weeks: weeks)
                    }
                    Section {
                        Button(edit.source?.courseKey.hasPrefix("local-") == false ? "恢复教务安排" : "撤销这项修改",
                               role: .destructive) { confirmUndo = true }
                    } footer: {
                        Text("后续针对同一次课程的修改可能也需要重新确认。")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("修改详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .confirmationDialog("撤销这项修改？", isPresented: $confirmUndo, titleVisibility: .visible) {
                Button("撤销修改", role: .destructive) {
                    save(app.timetableEdits.filter { $0.id != editID })
                }
            }
            .alert("重新应用后有课程冲突", isPresented: Binding(
                get: { replacement != nil },
                set: { if !$0 { replacement = nil } }
            ), presenting: replacement) { value in
                Button("仍然保存") {
                    save(app.timetableEdits.map { $0.id == editID ? value.edit : $0 }, dismissAfter: false)
                }
                Button("返回", role: .cancel) {}
            } message: { value in
                Text(value.conflicts.map { "\($0.course.name) · 第 \($0.weeks.map(String.init).joined(separator: "、")) 周" }
                    .joined(separator: "\n"))
            }
        }
    }

    @ViewBuilder
    private func pendingSections(edit: TimetableEdit, source: TimetableEdit.Source, weeks: [Int]) -> some View {
        let earlier = Array(app.timetableEdits.prefix { $0.id != edit.id })
        let blocks = app.editedTimetable(earlier).occurrences.courseBlocks()
        ForEach(weeks, id: \.self) { week in
            let candidates = blocks.filter {
                $0.courseKey == source.courseKey && $0.weeks.contains(week) && $0.span == source.ids.count
            }
            Section {
                if candidates.isEmpty {
                    Text("当前课表里没有可重新应用的安排。").foregroundStyle(.secondary)
                }
                ForEach(candidates) { block in
                    Button {
                        reapply(edit: edit, source: source, week: week, block: block)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("应用到周\(block.weekdayLabel) \(block.periodText)")
                            if !block.room.isEmpty || !block.teacher.isEmpty {
                                Text([block.room, block.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("第 \(week) 周待确认")
            } footer: {
                Text("请选择这项修改要对应的最新课程安排。")
            }
        }
    }

    private func reapply(edit: TimetableEdit, source: TimetableEdit.Source, week: Int, block: CourseBlock) {
        guard let index = source.weeks.firstIndex(where: { $0.resolve(monday: app.semesterStartMonday) == week }) else { return }
        var updated = source
        updated.replacements[index] = block.occurrenceIDs
        let newEdit = edit.replacingSource(updated)
        let edits = app.timetableEdits.map { $0.id == edit.id ? newEdit : $0 }
        let result = app.editedTimetable(edits)
        guard result.pending[edit.id]?.contains(week) != true else {
            error = TimetableEditError.sourceChanged.localizedDescription
            return
        }
        let blocks = result.occurrences.courseBlocks().filter { $0.weeks.contains(week) }.map { block in
            var copy = block
            copy.weeks = [week]
            return copy
        }
        let added = blocks.filter { $0.id.hasPrefix(edit.prefix) }
        let conflicts = TimetableConflict.find(added: added, among: blocks.filter { !$0.id.hasPrefix(edit.prefix) })
        if conflicts.isEmpty {
            save(edits, dismissAfter: false)
        } else {
            replacement = Replacement(edit: newEdit, conflicts: conflicts)
        }
    }

    private func save(_ edits: [TimetableEdit], dismissAfter: Bool = true) {
        do {
            try app.saveTimetableEdits(edits)
            if dismissAfter { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
