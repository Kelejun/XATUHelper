import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) var app
    @Environment(\.colorScheme) var colorScheme
    @State var username = ""
    @State var password = ""
    @State var showAbout = false
    @FocusState var focused: Field?

    enum Field {
        case username
        case password
    }

    private var canSubmit: Bool {
        !app.isLoading && !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        AppIcon("building.columns", size: 40)
                            .frame(width: 80, height: 80)
                            .background(MD3Colors.scheme(colorScheme)["primaryContainer"], in: RoundedRectangle(cornerRadius: 28))
                        Text("校园生活，轻松掌握").font(MD3Type.headline)
                        Text("登录后查看课程、成绩和校园服务")
                            .font(MD3Type.body).foregroundStyle(.secondary)
                    }.padding(.vertical, 16)

                    VStack(alignment: .leading, spacing: 16) {
                        TextField("学号", text: $username)
                            .textContentType(.username)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .username)
                            .textFieldStyle(.roundedBorder)
                            .frame(minHeight: 56)
                        SecureField("统一身份认证密码", text: $password)
                            .textContentType(.password)
                            .focused($focused, equals: .password)
                            .textFieldStyle(.roundedBorder)
                            .frame(minHeight: 56)
                        Text("凭据保存在本机安全存储中，仅用于学校认证。")
                            .font(MD3Type.caption).foregroundStyle(.secondary)
                    }
                    if let message = app.errorMessage {
                        Text(message).font(MD3Type.bodyMedium)
                            .foregroundStyle(MD3Colors.scheme(colorScheme)["error"])
                            .accessibilityLabel("登录提示：\(message)")
                    }
                    Button {
                        focused = nil
                        Task { await app.login(student: username, password: password) }
                    } label: {
                        HStack(spacing: 8) {
                            if app.isLoading { ProgressView() }
                            Text(app.isLoading ? "登录中…" : "登录").font(MD3Type.label)
                        }.frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)

                    Button("需要验证码？用网页登录") {
                        focused = nil
                        app.showsWebLogin = true
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .buttonStyle(.bordered)
                    .font(MD3Type.label)
                    .disabled(app.isLoading)
                    Text("网页登录支持验证码与手机动态码。")
                        .font(MD3Type.bodyMedium).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .md3Screen()
            .navigationTitle("XATU Helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        ToolbarIcon("gearshape")
                    }
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutSheet()
            }
            .sheet(isPresented: $app.showsWebLogin) {
                CASWebLoginSheet()
            }
        }
        .onAppear {
            if username.isEmpty { username = app.studentID }
        }
    }
}


struct AboutSheet: View {
    @Environment(\.dismiss) var dismiss

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("服务地址") {
                    LabeledContent("教务系统", value: "jwgl2018.xatu.edu.cn").frame(minHeight: 40)
                    LabeledContent("统一认证", value: "authserver.xatu.edu.cn").frame(minHeight: 40)
                }

                Section {
                    Text("密码只存在本机钥匙串里，不会上传到任何地方。")
                        .font(MD3Type.bodyMedium)
                        .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("版本", value: version).frame(minHeight: 40)
                }
            }
            .md3List()
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
