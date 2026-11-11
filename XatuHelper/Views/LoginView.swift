import SwiftUI

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var showAbout = false
    @FocusState private var focused: Field?

    private enum Field { case username, password }

    private var canSubmit: Bool {
        !app.isLoading && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image("XATuneMark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("XATune")
                            .font(.title2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("学号", text: $username)
                            .textContentType(.username)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .username)
                            .accessibilityLabel("学号")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        SecureField("统一身份认证密码", text: $password)
                            .textContentType(.password)
                            .focused($focused, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .accessibilityLabel("统一身份认证密码")
                    }
                }
                .disabled(app.isLoading)

                Section {
                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if app.isLoading { ProgressView() }
                            Text(app.isLoading ? "登录中…" : "登录")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSubmit)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("密码安全保存在本机钥匙串")
                }

                Section {
                    Button("体验示例") {
                        focused = nil
                        app.showsDemoAccount = true
                    }
                    .disabled(app.isLoading)
                    PrivacyPolicyLink()
                } footer: {
                    Text("无需登录，可查看示例课表、考试、成绩和电费。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAbout = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                    .disabled(app.isLoading)
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutSheet()
            }
        }
        .onAppear {
            if username.isEmpty { username = app.studentID }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        Task { await app.login(student: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
    }
}

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("服务地址") {
                    LabeledContent("教务系统", value: "jwgl2018.xatu.edu.cn")
                    LabeledContent("统一认证", value: "authserver.xatu.edu.cn")
                }
                Section("关于") {
                    LabeledContent("版本", value: version)
                    PrivacyPolicyLink()
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct DemoAccountView: View {
    @StateObject private var demo = AppState(isDemo: true)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MainTabView()
            .environmentObject(demo)
            .onChange(of: demo.isLoggedIn) { _, loggedIn in
                if !loggedIn { dismiss() }
            }
    }
}
