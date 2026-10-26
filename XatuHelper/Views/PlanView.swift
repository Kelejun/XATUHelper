import SwiftUI

/// 培养计划：拿「要求学分 / 实修学分」算毕业进度。
struct PlanView: View {
    @EnvironmentObject var app: AppState
    @State private var showWebPage = false

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
                    Button("在网页里打开") { showWebPage = true }
                } header: {
                    Text("没读出来")
                }
            }

            if !app.plan.sections.isEmpty {
                overview
                ForEach(app.plan.sections) { section in
                    moduleSection(section)
                }
            }
        }
        .navigationTitle("培养计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await app.refreshPlan() }
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

    private func moduleSection(_ section: PlanSection) -> some View {
        Section {
            sectionRow(section, showBar: true)

            if !section.courses.isEmpty {
                DisclosureGroup("课程 \(section.courses.count) 门") {
                    ForEach(section.courses) { course in
                        courseRow(course)
                    }
                }
                .font(.subheadline)
            }

            ForEach(section.children) { child in
                DisclosureGroup {
                    ForEach(child.courses) { course in
                        courseRow(course)
                    }
                    if child.courses.isEmpty {
                        Text("这下面没有课").font(.footnote).foregroundStyle(.secondary)
                    }
                } label: {
                    sectionRow(child, showBar: true)
                }
                .font(.subheadline)
            }
        } header: {
            Text(section.title)
        }
    }

    private func sectionRow(_ section: PlanSection, showBar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Text("\(number(section.earned)) / \(number(section.required))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(section.shortfall <= 0 ? Color.green : Color.secondary)
            }
            if showBar && section.required > 0 {
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
            }
            Spacer(minLength: 8)
            Text("\(number(course.earned)) / \(number(course.required))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(course.passed ? Color.secondary : Color.orange)
        }
    }

    private func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}
