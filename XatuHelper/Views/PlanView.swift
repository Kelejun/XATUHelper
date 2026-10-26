import SwiftUI

/// 培养计划：拿「已修学分 / 要求学分」算毕业进度。
struct PlanView: View {
    @EnvironmentObject var app: AppState
    @State private var showWebPage = false

    var body: some View {
        Form {
            if app.planLoading && app.plan.rows.isEmpty {
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

            if !app.plan.rows.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(creditText)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        ProgressView(value: app.plan.totalProgress)
                            .tint(.blue)
                        Text("已修 \(short(app.plan.totalEarned)) / 要求 \(short(app.plan.totalRequired)) 学分")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("毕业学分")
                }

                Section {
                    ForEach(app.plan.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.module)
                                Spacer(minLength: 12)
                                Text("\(short(row.earned)) / \(short(row.required))")
                                    .font(.subheadline)
                                    .foregroundStyle(row.earned >= row.required ? .green : .secondary)
                            }
                            ProgressView(value: row.progress)
                                .tint(row.earned >= row.required ? .green : .blue)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("各模块")
                } footer: {
                    Text("数字是从教务的培养计划页面上读出来的，以学校页面为准。")
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
            WebSheet(title: "培养计划", urlString: "http://jwgl2018.xatu.edu.cn/eams/myPlanCompl.action")
        }
        .task {
            if app.plan.rows.isEmpty { await app.refreshPlan() }
        }
    }

    private var creditText: String {
        "\(short(app.plan.totalEarned))"
    }

    private func short(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
