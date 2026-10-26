import SwiftUI

/// 培养计划：拿「要求学分 / 实修学分」算毕业进度。
struct PlanView: View {
    @EnvironmentObject var app: AppState
    @State private var showWebPage = false
    @State private var searchText = ""

    var body: some View {
        Form {
            if app.planLoading && app.plan.sections.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读培养计划…").foregroundStyle(.secondary)
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
                    ForEach(app.plan.sections) { section in
                        moduleSection(section)
                    }
                } else {
                    searchResults
                }
            }
        }
        .navigationTitle("培养计划")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索课程名称")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await app.refreshPlanCatalogIfNeeded(force: true)
                        await app.refreshPlan()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(app.planLoading)
            }
        }
        .sheet(isPresented: $showWebPage) {
            WebSheet(title: "计划完成情况", urlString: "http://jwgl2018.xatu.edu.cn/eams/myPlanCompl.action")
        }
        .task {
            if app.plan.sections.isEmpty { await app.refreshPlan() }
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
                PlanSectionContent(section: section, number: number)
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
                    .font(.footnote.monospacedDigit())
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
                .font(.caption.monospacedDigit())
                .foregroundStyle(course.passed ? Color.secondary : Color.orange)
        }
    }

    private struct Match {
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

    private func detailText(_ info: PlanCourseInfo) -> String {
        var parts: [String] = []
        if !info.term.isEmpty { parts.append(info.term.contains("学期") || info.term.contains("第") ? info.term : "\(info.term) 学期") }
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
private struct PlanSectionContent: View {
    let section: PlanSection
    let number: (Double) -> String

    var body: some View {
        ForEach(section.children) { child in
            DisclosureGroup {
                PlanSectionContent(section: child, number: number)
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
                .font(.footnote.monospacedDigit())
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
            }
            Spacer(minLength: 8)
            Text("\(number(course.earned)) / \(number(course.required))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(course.passed ? Color.secondary : Color.orange)
        }
    }
}
