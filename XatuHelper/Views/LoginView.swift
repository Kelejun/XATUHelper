import SwiftUI

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var username = ""
    @State private var password = ""
    @State private var showAbout = false
    @State private var appeared = false
    @FocusState private var focused: Field?

    private enum Field { case username, password }

    private var canSubmit: Bool {
        !app.isLoading && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 18)

                        VStack(alignment: .leading, spacing: 14) {
                            credentialsCard
                            submitButton
                            securityNote
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)

                        demoCard
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 28)

                        Spacer(minLength: 20)

                        footerLinks
                            .opacity(appeared ? 1 : 0)
                    }
                    .padding(.horizontal, proxy.size.width >= 600 ? 28 : 20)
                    .padding(.top, proxy.size.height < 640 ? 20 : 56)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 460, minHeight: proxy.size.height, alignment: .top)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                    loginBackground
                }
                .ignoresSafeArea()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAbout = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                    .disabled(app.isLoading)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focused == .username {
                        Button("下一步") { focused = .password }
                    }
                    Spacer()
                    Button("完成") { focused = nil }
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutSheet()
            }
        }
        .onAppear {
            if username.isEmpty { username = app.studentID }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.smooth(duration: 0.6)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - 顶部品牌区

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            brandMark
            VStack(alignment: .leading, spacing: 6) {
                Text("XATune")
                    .font(.largeTitle.bold())
                Text("使用校园统一身份认证登录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var brandMark: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.14, green: 0.44, blue: 0.96), Color(red: 0.06, green: 0.30, blue: 0.78)]
                    : [Color(red: 0.08, green: 0.44, blue: 0.96), Color(red: 0.01, green: 0.33, blue: 0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image("XATuneMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(.white)
        }
        .frame(width: 56, height: 56)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.25), lineWidth: 0.5)
        }
        .shadow(color: Color(red: 0.01, green: 0.35, blue: 0.85).opacity(colorScheme == .dark ? 0.32 : 0.22), radius: 12, y: 6)
        .accessibilityHidden(true)
    }

    // MARK: - 账号密码卡片

    private var credentialsCard: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                fieldIcon("person.fill", active: focused == .username)
                TextField("学号", text: $username)
                    .textContentType(.username)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .username)
                    .accessibilityLabel("学号")
                if !username.isEmpty && !app.isLoading {
                    Button {
                        username = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空学号")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .padding(.leading, 60)

            HStack(spacing: 12) {
                fieldIcon("lock.fill", active: focused == .password)
                SecureField("统一身份认证密码", text: $password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .accessibilityLabel("统一身份认证密码")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.secondarySystemGroupedBackground), in: shape)
        .disabled(app.isLoading)
    }

    private func fieldIcon(_ systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .frame(width: 32, height: 32)
            .background(
                (active ? Color.accentColor : Color.secondary).opacity(active ? 0.14 : 0.10),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .animation(.easeInOut(duration: 0.18), value: active)
            .accessibilityHidden(true)
    }

    // MARK: - 登录按钮与提示

    private var submitButton: some View {
        Button(action: submit) {
            ZStack {
                Text("登录")
                    .font(.headline)
                    .opacity(app.isLoading ? 0 : 1)
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("登录中…")
                        .font(.headline)
                }
                .opacity(app.isLoading ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(app.isLoading ? "登录中…" : "登录")
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .controlSize(.large)
        .disabled(!canSubmit)
    }

    private var securityNote: some View {
        Label("密码安全保存在本机钥匙串", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: - 次要入口

    private var demoCard: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            focused = nil
            app.showsDemoAccount = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 38, height: 38)
                    .background(Color.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("体验示例")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("无需登录，可查看示例课表、考试、成绩和电费")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .contentShape(.interaction, shape)
        }
        .buttonStyle(.plain)
        .disabled(app.isLoading)
    }

    private var footerLinks: some View {
        HStack {
            Spacer()
            PrivacyPolicyLink()
                .font(.footnote)
                .foregroundStyle(.blue)
            Spacer()
        }
    }

    // MARK: - 顶部渐变背景

    private var loginBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.16, green: 0.44, blue: 0.94).opacity(0.34), location: 0),
                .init(color: Color(red: 0.40, green: 0.66, blue: 0.98).opacity(0.16), location: 0.55),
                .init(color: Color(.systemGroupedBackground).opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        Task { await app.login(student: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
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
                    LabeledContent("备案号", value: "粤ICP备2026181989号-1A")
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
