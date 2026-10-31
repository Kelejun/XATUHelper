import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) var app
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
            Form {
                Section {
                    TextField("学号", text: $username)
                        .textContentType(.username)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .username)

                    SecureField("统一身份认证密码", text: $password)
                        .textContentType(.password)
                        .focused($focused, equals: .password)
                } footer: {
                    Text("密码只保存在本机的钥匙串里，不会上传到任何地方。")
                }

                Section {
                    Button {
                        focused = nil
                        Task { await app.login(student: username, password: password) }
                    } label: {
                        HStack {
                            Spacer()
                            if app.isLoading {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(app.isLoading ? "登录中…" : "登录")
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }

                if let message = app.errorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("需要验证码？用网页登录") {
                        focused = nil
                        app.showsWebLogin = true
                    }
                    .disabled(app.isLoading)
                } footer: {
                    Text("网页里可以输验证码，也可以用手机动态码。")
                }

            }
            .navigationTitle("XATU Helper")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "gearshape")
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
                    LabeledContent("教务系统", value: "jwgl2018.xatu.edu.cn")
                    LabeledContent("统一认证", value: "authserver.xatu.edu.cn")
                }

                Section {
                    Text("密码只存在本机钥匙串里，不会上传到任何地方。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("版本", value: version)
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
