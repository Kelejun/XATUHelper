import SwiftUI

struct TimetableEditSheet: View {
    enum Mode {
        case add, move, remove
    }

    enum Operation: Identifiable {
        case add
        case move(CourseBlock)
        case remove(CourseBlock)

        var id: String {
            switch self {
            case .add: return "add"
            case .move(let block): return "move-\(block.id)"
            case .remove(let block): return "remove-\(block.id)"
            }
        }

        var mode: Mode {
            switch self {
            case .add: return .add
            case .move: return .move
            case .remove: return .remove
            }
        }

        var block: CourseBlock? {
            switch self {
            case .add: return nil
            case .move(let block), .remove(let block): return block
            }
        }
    }

    private enum RangeMode: String, CaseIterable {
        case once = "只上一次"
        case weeks = "按教学周"
        case dates = "按日期"
    }

    let operation: Operation
    let week: Int
    var onSaved: (() -> Void)?
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var teacher = ""
    @State private var room = ""
    @State private var days: Set<Int> = [1]
    @State private var day = 1
    @State private var start = 1
    @State private var end = 1
    @State private var rangeMode = RangeMode.once
    @State private var firstWeek = 1
    @State private var lastWeek = 1
    @State private var firstDate = Date()
    @State private var lastDate = Date()
    @State private var selectedWeeks: Set<Int> = []
    @State private var error: String?
    @State private var conflicts: [TimetableConflict] = []
    @State private var editID = UUID()
    @State private var scope: [String] = []
    @State private var initialized = false

    private let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    private var mode: Mode { operation.mode }

    private var title: String {
        switch mode {
        case .add: return "添加课程"
        case .move: return "修改课程"
        case .remove: return "移除课程"
        }
    }

    private var currentScope: [String] { [app.studentID, app.selectedSemesterID, app.kind.rawValue] }

    private var calendarRange: ClosedRange<Date> {
        let monday = app.semesterStartMonday
        return TimetableDates.date(week: 1, day: 1, monday: monday)
            ... TimetableDates.date(week: TimetableDates.weeks.upperBound, day: 7, monday: monday)
    }

    private var course: ManualCourse {
        let range: ManualCourse.Range
        switch rangeMode {
        case .once, .weeks: range = .weeks(firstWeek, rangeMode == .once ? firstWeek : lastWeek)
        case .dates: range = .dates(firstDate, lastDate)
        }
        return ManualCourse(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
                            room: room.trimmingCharacters(in: .whitespacesAndNewlines),
                            days: rangeMode == .once ? [day] : days, startPeriod: start,
                            endPeriod: end, range: range)
    }

    private var dates: [Date] {
        let course = course
        let monday = app.semesterStartMonday
        return course.days.flatMap { day in
            course.weeks(for: day, monday: monday).map { TimetableDates.date(week: $0, day: day, monday: monday) }
        }.sorted()
    }

    private var maximumStart: Int { max(1, app.unitCount - (operation.block?.span ?? 1) + 1) }
    private var trimmedRoom: String { room.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var changesTime: Bool {
        guard let block = operation.block else { return true }
        return block.day != day || block.startPeriod != start
    }

    private var valid: Bool {
        guard initialized, scope == currentScope, app.canEditTimetable else { return false }
        if mode == .add { return !course.name.isEmpty && !dates.isEmpty && start <= end }
        return !selectedWeeks.isEmpty && (mode == .remove || (
            start <= maximumStart && (changesTime || operation.block?.room != trimmedRoom)
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                if mode == .add {
                    addFields
                } else if let block = operation.block {
                    Section(block.name) {
                        LabeledContent("原时间", value: "周\(block.weekdayLabel) \(block.periodText)")
                    }
                    if mode == .move {
                        Section("课程安排") {
                            dayPicker
                            periodPicker("起始节次", selection: $start, range: 1...maximumStart)
                            LabeledContent("结束节次", value: "第 \(start + block.span - 1) 节")
                            TextField("教室（选填）", text: $room)
                        }
                    }
                    weekSelection(block)
                }
                if let error { Text(error).foregroundStyle(.red) }
                if !conflicts.isEmpty {
                    Section {
                        ForEach(conflicts) { conflict in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conflict.course.name)
                                Text(conflictDetails(conflict)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("仍然保存") { save(allowing: conflictSignature(conflicts)) }
                        Button("返回调整", role: .cancel) { clearConflicts() }
                    } header: {
                        Text("时间冲突")
                    } footer: {
                        Text("保留后，可以在课表中点开冲突查看每门课。")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .remove ? "确认移除" : "保存") { save() }
                        .disabled(!valid)
                }
            }
            .onAppear(perform: initialize)
            .onChange(of: draftKey) { _, _ in clearConflicts() }
        }
    }

    private var draftKey: [String] {
        [name, teacher, room, String(day), days.sorted().description, String(start), String(end),
         rangeMode.rawValue, String(firstWeek), String(lastWeek), firstDate.description,
         lastDate.description, selectedWeeks.sorted().description]
    }

    @ViewBuilder private var addFields: some View {
        Section("课程") {
            TextField("课程名", text: $name)
            TextField("教室（选填）", text: $room)
            TextField("教师（选填）", text: $teacher)
        }
        Section("节次") {
            periodPicker("起始节次", selection: $start, range: 1...max(1, app.unitCount))
            periodPicker("结束节次", selection: $end, range: start...max(start, app.unitCount))
                .onChange(of: start) { _, value in end = max(value, end) }
        }
        Section("重复规则") {
            Picker("范围", selection: $rangeMode) {
                ForEach(RangeMode.allCases.filter { $0 != .dates || app.canUseTimetableDates }, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            weekdayButtons

            switch rangeMode {
            case .once, .weeks:
                weekPicker(rangeMode == .once ? "上课周次" : "开始周", selection: $firstWeek, range: TimetableDates.weeks)
                if rangeMode == .weeks {
                    weekPicker("结束周", selection: $lastWeek, range: firstWeek...TimetableDates.weeks.upperBound)
                        .onChange(of: firstWeek) { _, value in lastWeek = max(value, lastWeek) }
                }
            case .dates:
                DatePicker("开始日期", selection: $firstDate, in: calendarRange, displayedComponents: .date)
                DatePicker("结束日期", selection: $lastDate, in: calendarRange, displayedComponents: .date)
                    .onChange(of: firstDate) { _, value in lastDate = max(value, lastDate) }
            }
        }
        Section("预览") {
            coursePreview
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
    }

    private var weekdayButtons: some View {
        let singleSelection = rangeMode == .once
        return HStack(spacing: 0) {
            ForEach([7, 1, 2, 3, 4, 5, 6], id: \.self) { value in
                let isSelected = singleSelection ? day == value : days.contains(value)
                let label = dayLabels[value - 1]
                Button {
                    if singleSelection {
                        day = value
                    } else if isSelected {
                        days.remove(value)
                    } else {
                        days.insert(value)
                    }
                } label: {
                    Text(label)
                        .font(.callout.weight(.semibold))
                        .minimumScaleFactor(0.7)
                        .frame(width: 34, height: 34)
                        .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
                        .background(isSelected ? Color.primary : Color(uiColor: .tertiarySystemFill), in: Circle())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("星期" + label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
    }

    private var coursePreview: some View {
        let draft = course
        let scheduledDates = dates
        let tint = CoursePalette.color(forCourseKey: "local-" + editID.uuidString)
        let weekdays = draft.days.sorted().map { dayLabels[$0 - 1] }.joined(separator: "、")
        let periods = start == end ? "第 \(start) 节" : "第 \(start)–\(end) 节"

        return VStack(alignment: .leading, spacing: 6) {
            Text(draft.name.isEmpty ? "课程名" : draft.name)
                .font(.headline)
                .foregroundStyle(draft.name.isEmpty ? .secondary : .primary)
            Text(weekdays.isEmpty ? periods : "周\(weekdays) · \(periods)")
                .font(.subheadline.weight(.medium))
            let details = [draft.room, draft.teacher].filter { !$0.isEmpty }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
            }
            if let first = scheduledDates.first, let last = scheduledDates.last {
                let firstLabel = first.formatted(date: .abbreviated, time: .omitted)
                let lastLabel = last.formatted(date: .abbreviated, time: .omitted)
                let dateLabel = first == last ? firstLabel : firstLabel + " – " + lastLabel
                let countLabel = "\(scheduledDates.count) 次"
                let summary = app.canUseTimetableDates
                    ? (first == last ? dateLabel : dateLabel + " · " + countLabel)
                    : countLabel
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "calendar")
                        .accessibilityHidden(true)
                    Text(summary)
                }
            } else {
                Text("所选范围内没有符合重复规则的日期。")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 14)
                .padding(.leading, 10)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var dayPicker: some View {
        Picker("星期", selection: $day) {
            ForEach(1...7, id: \.self) { Text("周" + dayLabels[$0 - 1]).tag($0) }
        }
    }

    private func periodPicker(_ title: String, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(range, id: \.self) { Text("第 \($0) 节").tag($0) }
        }
    }

    private func weekPicker(_ title: String, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(range, id: \.self) { Text("第 \($0) 周").tag($0) }
        }
    }

    private func weekSelection(_ block: CourseBlock) -> some View {
        let available = block.weeks.filter(TimetableDates.weeks.contains).sorted()
        let upcoming = available.filter { $0 >= week }
        return Section("影响周次") {
            Button("仅第 \(week) 周") { selectedWeeks = [week] }
            if available.count > 1 {
                Button("本周及后续上课周") { selectedWeeks = Set(upcoming) }
                    .disabled(upcoming.count <= 1)
                Button("选择全部上课周") { selectedWeeks = Set(available) }
            }
            ForEach(available, id: \.self) { value in
                let isSelected = selectedWeeks.contains(value)
                Button {
                    if isSelected { selectedWeeks.remove(value) } else { selectedWeeks.insert(value) }
                } label: {
                    HStack {
                        Text("第 \(value) 周")
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func initialize() {
        guard !initialized else { return }
        scope = currentScope
        firstWeek = min(max(week, 1), TimetableDates.weeks.upperBound)
        lastWeek = firstWeek
        selectedWeeks = [firstWeek]
        if let block = operation.block {
            day = block.day
            start = min(block.startPeriod, maximumStart)
            room = block.room
        } else {
            let calendar = TimetableDates.calendar
            let today = Date()
            if TimetableDates.week(of: today, monday: app.semesterStartMonday) == firstWeek {
                day = (calendar.component(.weekday, from: today) + 5) % 7 + 1
            }
            days = [day]
        }
        firstDate = TimetableDates.date(week: firstWeek, day: day, monday: app.semesterStartMonday)
        lastDate = firstDate
        initialized = true
    }

    private func clearConflicts() {
        conflicts = []
        error = nil
    }

    private func weekList(_ weeks: [Int]) -> String { weeks.map(String.init).joined(separator: "、") }

    private func conflictDetails(_ conflict: TimetableConflict) -> String {
        let time = "周\(conflict.course.weekdayLabel) \(conflict.course.periodText)"
        if mode == .add && rangeMode == .dates {
            let dates = conflict.weeks.map { week in
                TimetableDates.date(week: week, day: conflict.course.day, monday: app.semesterStartMonday)
                    .formatted(date: .abbreviated, time: .omitted)
            }
            return time + " · " + dates.joined(separator: "、")
        }
        return time + " · 第 \(weekList(conflict.weeks)) 周"
    }

    private func conflictSignature(_ conflicts: [TimetableConflict]) -> [String] {
        conflicts.map { "\($0.id):\(weekList($0.weeks))" }.sorted()
    }

    private func save(allowing accepted: [String] = []) {
        guard valid else { return }
        do {
            let change: TimetableEdit.Change
            if let block = operation.block {
                let source = TimetableEdit.Source(
                    ids: block.occurrenceIDs, name: block.name, courseKey: block.courseKey,
                    weeks: selectedWeeks.sorted().map { value in
                        block.usesFixedDates
                            ? .date(TimetableDates.date(week: value, day: block.day, monday: app.semesterStartMonday))
                            : .teachingWeek(value)
                    }
                )
                let roomOverride = trimmedRoom == block.room ? nil : trimmedRoom
                change = mode == .move ? .move(source, .init(day: day, startPeriod: start, room: roomOverride)) : .remove(source)
            } else {
                change = .add(course)
            }
            let edit = TimetableEdit(id: editID, change: change)
            let edits = app.timetableEdits + [edit]
            let result = app.editedTimetable(edits)
            guard result.pending[editID] == nil else { throw TimetableEditError.sourceChanged }
            let blocks = result.occurrences.courseBlocks()
            let added = blocks.filter { $0.id.hasPrefix(edit.prefix) }
            let found = changesTime
                ? TimetableConflict.find(added: added, among: blocks.filter { !$0.id.hasPrefix(edit.prefix) })
                : []
            if !found.isEmpty, accepted != conflictSignature(found) {
                conflicts = found
                return
            }
            try app.saveTimetableEdits(edits)
            dismiss()
            onSaved?()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
