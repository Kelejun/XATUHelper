import SwiftUI

/// 学业完成情况：拿「要求学分 / 实修学分」算毕业进度。
struct PlanView: View {
    @Environment(AppState.self) var app
    @State var showWebPage = false
    @State var searchText = ""
    /// nil 表示不筛选
    @State var termFilter: String?

    var body: some View {
        Form {
            if app.planLoading && app.plan.sections.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读学业完成情况…").foregroundStyle(.secondary)
                    }
                }
            }

            if let error = app.planError, !app.planLoading {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("重新读一次") { Task { await app.refreshPlan() } }
                    if app.planNeedsLogin {
                        Button("重新登录") { Task { await app.reloginNow() } }
                    }
                    Button("在网页里打开") { showWebPage = true }
                } header: {
                    Text("没读出来")
                }
            }

            if !app.plan.sections.isEmpty {
                if searchText.isEmpty {
                    overview
                    ForEach(filteredSections) { section in
                        moduleSection(section)
                    }
                } else {
                    searchResults
                }
            }
        }
        .navigationTitle("学业完成情况")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索课程名称")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        termFilter = nil
                    } label: {
                        if termFilter == nil {
                            Label("全部学期", systemImage: "checkmark")
                        } else {
                            Text("全部学期")
                        }
                    }
                    Divider()
                    ForEach(availableTerms, id: \.self) { term in
                        Button {
                            termFilter = term
                        } label: {
                            if termFilter == term {
                                Label("学期 \(term)", systemImage: "checkmark")
                            } else {
                                Text("学期 \(term)")
                            }
                        }
                    }
                } label: {
                    Image(systemName: termFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .disabled(availableTerms.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await app.refreshPlanCatalogIfNeeded(force: true)
                        await app.refreshPlan()
                    }
                } label: {
                    if app.planLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(app.planLoading)
            }
        }
        .sheet(isPresented: $showWebPage) {
            WebSheet(title: "计划完成情况", urlString: "http://jwgl2018.xatu.edu.cn/eams/myPlanCompl.action")
        }
        .task {
            if app.isStale(.plan) { await app.refreshPlan() }
            await app.refreshPlanCatalogIfNeeded()
        }
    }

    private var overview: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(number(app.plan.totalEarned))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text("/ \(number(app.plan.totalRequired)) 学分")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: app.plan.progress)
                    .tint(.blue)
                HStack(spacing: 12) {
                    if !app.plan.major.isEmpty {
                        Text(app.plan.major).lineLimit(1)
                    }
                    if !app.plan.gpa.isEmpty {
                        Text("GPA \(app.plan.gpa)")
                    }
                    if app.plan.shortfall > 0 {
                        Text("还差 \(number(app.plan.shortfall)) 学分")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("毕业学分")
        }
    }

    private var searchResults: some View {
        let found = searchMatches
        return Section {
            if found.isEmpty {
                Text("没搜到这门课").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(found, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        courseRow(item.course)
                        Text(item.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("搜到 \(found.count) 门课")
        }
    }

    private func moduleSection(_ section: PlanSection) -> some View {
        Section {
            DisclosureGroup {
                PlanSectionContent(section: section, number: number, detail: detailFor)
            } label: {
                sectionRow(section)
            }
            .font(.subheadline)
        } header: {
            Text(section.title)
        }
    }

    private func sectionRow(_ section: PlanSection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Text("\(number(section.earned)) / \(number(section.required))")
                    .font(.footnote)
                    .foregroundStyle(section.shortfall <= 0 ? Color.green : Color.secondary)
            }
            if section.required > 0 {
                ProgressView(value: section.progress)
                    .tint(section.shortfall <= 0 ? Color.green : Color.blue)
            }
        }
        .padding(.vertical, 2)
    }

    private func courseRow(_ course: PlanCourse) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(course.code)
                    if !course.score.isEmpty, course.score != "--" {
                        Text(course.score)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if let info = app.courseInfo(for: course) {
                    Text(detailText(info))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text("\(number(course.earned)) / \(number(course.required))")
                .font(.caption)
                .foregroundStyle(course.passed ? Color.secondary : Color.orange)
        }
    }

    struct Match {
        let id: String
        let course: PlanCourse
        let path: String
    }

    private var searchMatches: [Match] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return [] }
        var result: [Match] = []
        func walk(_ section: PlanSection, path: [String]) {
            let here = path + [section.title]
            for course in section.courses where course.name.contains(keyword) || course.code.contains(keyword) {
                result.append(Match(id: course.id, course: course, path: here.joined(separator: " › ")))
            }
            for child in section.children {
                walk(child, path: here)
            }
        }
        for section in app.plan.sections {
            walk(section, path: [])
        }
        return result
    }

    /// 所有出现在教学计划里的开课学期，按数字排序
    private var availableTerms: [String] {
        var all: Set<String> = []
        func walk(_ section: PlanSection) {
            for course in section.courses {
                guard let info = app.courseInfo(for: course) else { continue }
                for part in info.term.split(separator: ",") {
                    let term = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !term.isEmpty { all.insert(term) }
                }
            }
            section.children.forEach(walk)
        }
        app.plan.sections.forEach(walk)
        return all.sorted { (Int($0) ?? 999) < (Int($1) ?? 999) }
    }

    private func matchesTerm(_ course: PlanCourse) -> Bool {
        guard let filter = termFilter else { return true }
        guard let info = app.courseInfo(for: course) else { return false }
        return info.term
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(filter)
    }

    /// 按学期筛掉不匹配的课程，顺带去掉空模块
    private var filteredSections: [PlanSection] {
        guard termFilter != nil else { return app.plan.sections }
        func prune(_ section: PlanSection) -> PlanSection? {
            var copy = section
            copy.courses = section.courses.filter(matchesTerm)
            copy.children = section.children.compactMap(prune)
            guard !copy.courses.isEmpty || !copy.children.isEmpty else { return nil }
            return copy
        }
        return app.plan.sections.compactMap(prune)
    }

    private func detailFor(_ course: PlanCourse) -> String? {
        guard let info = app.courseInfo(for: course) else { return nil }
        return detailText(info)
    }

    private func detailText(_ info: PlanCourseInfo) -> String {
        var parts: [String] = []
        if !info.term.isEmpty {
            parts.append(info.term.contains("学期") ? info.term : "学期 \(info.term)")
        }
        if !info.hours.isEmpty { parts.append("\(info.hours) 学时") }
        if !info.nature.isEmpty { parts.append(info.nature) }
        return parts.joined(separator: " · ")
    }

    private func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

/// 递归展开：点某一层，直接看到它下面的分组和课程。
struct PlanSectionContent: View {
    let section: PlanSection
    let number: (Double) -> String
    let detail: (PlanCourse) -> String?

    var body: some View {
        ForEach(section.children) { child in
            DisclosureGroup {
                PlanSectionContent(section: child, number: number, detail: detail)
            } label: {
                label(child)
            }
        }
        ForEach(section.courses) { course in
            row(course)
        }
    }

    private func label(_ section: PlanSection) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(section.title)
                .lineLimit(2)
            Spacer(minLength: 12)
            Text("\(number(section.earned)) / \(number(section.required))")
                .font(.footnote)
                .foregroundStyle(section.shortfall <= 0 ? Color.green : Color.secondary)
        }
    }

    private func row(_ course: PlanCourse) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(course.code)
                    if !course.score.isEmpty, course.score != "--" {
                        Text(course.score)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if let detail = detail(course) {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text("\(number(course.earned)) / \(number(course.required))")
                .font(.caption)
                .foregroundStyle(course.passed ? Color.secondary : Color.orange)
        }
    }
}
