import SwiftUI

/// 开发者选项：查看与修改 App 依赖的外部服务地址。
///
/// 只在「开发者模式」开启时从设置页进入，用于二次开发时把 App 指向自建后端，
/// 改完立即生效，不需要重新编译。
struct ServiceEndpointSettingsView: View {

    private enum Design {
        static let backgroundColor = Color(white: 0.04)
        static let cardColor = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255, opacity: 0.4)
        static let fieldBackground = Color.white.opacity(0.1)
        static let cardPadding: CGFloat = 20
        static let cornerRadius: CGFloat = 24
    }

    @State private var apiInput: String = ServiceEndpoints.shared.apiBaseURL
    @State private var staticInput: String = ServiceEndpoints.shared.staticBaseURL
    @State private var toast: String?
    @State private var toastIsError = false
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    /// 与 `AuthService` 共用同一个键，用于无登录态时调试自建后端
    @AppStorage("debug.bypassAuth") private var bypassAuth: Bool = false

    var body: some View {
        ZStack {
            Design.backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    endpointCard(
                        title: "业务 API 地址",
                        icon: "server.rack",
                        text: $apiInput,
                        effective: ServiceEndpoints.shared.apiBaseURL,
                        source: ServiceEndpoints.shared.apiBaseURLSource,
                        builtInDefault: ServiceEndpoints.defaultAPIBaseURL,
                        footer: "登录、AI 修图、灵感推荐、自动化分享都会走这个地址。"
                    )

                    endpointCard(
                        title: "静态资源地址",
                        icon: "globe",
                        text: $staticInput,
                        effective: ServiceEndpoints.shared.staticBaseURL,
                        source: ServiceEndpoints.shared.staticBaseURLSource,
                        builtInDefault: ServiceEndpoints.defaultStaticBaseURL,
                        footer: "用户协议、隐私政策等 Web 文档的托管地址。"
                    )

                    actionBar
                    connectionCard
                    debugCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("服务地址")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    // MARK: - 地址编辑卡片

    @ViewBuilder
    private func endpointCard(
        title: String,
        icon: String,
        text: Binding<String>,
        effective: String,
        source: ServiceEndpoints.Source,
        builtInDefault defaultValue: String,
        footer: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            GlassCard(cardColor: Design.cardColor, paddingValue: Design.cardPadding) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)

                        TextField(defaultValue, text: text)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Design.fieldBackground)
                            .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        infoLine(label: "生效值", value: effective)
                        infoLine(label: "来源", value: source.rawValue)
                        infoLine(label: "内置默认", value: defaultValue)
                    }

                    Text(footer)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    private func infoLine(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.gray)
                .frame(width: 56, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 操作区

    private var actionBar: some View {
        VStack(spacing: 12) {
            Button(action: save) {
                Text("保存并立即生效")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(14)
            }

            Button(action: reset) {
                Text("恢复默认地址")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(14)
            }

            if let toast {
                Text(toast)
                    .font(.system(size: 13))
                    .foregroundStyle(toastIsError ? Color(red: 1, green: 0.45, blue: 0.4) : Color(red: 0.4, green: 0.85, blue: 0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - 连通性自检

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("连通性自检")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            GlassCard(cardColor: Design.cardColor, paddingValue: Design.cardPadding) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("向当前 API 地址的 /api/user 发一个 GET 请求。只要拿到任何 HTTP 响应，就说明地址可达。")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)

                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isTesting ? "测试中…" : "测试连接")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(12)
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.system(size: 13))
                            .foregroundStyle(testSucceeded ? Color(red: 0.4, green: 0.85, blue: 0.6) : Color(red: 1, green: 0.45, blue: 0.4))
                    }
                }
            }
        }
    }

    // MARK: - 调试开关

    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("接口调试")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            GlassCard(cardColor: Design.cardColor, paddingValue: Design.cardPadding) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $bypassAuth) {
                        Text("跳过登录校验")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .tint(.accentColor)

                    Text("开启后，未登录时会用一个占位 Token 调用接口，用于在没有完整登录流程的情况下联调自建后端。仅供开发调试，正式使用请关闭。")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    // MARK: - 行为

    private func reload() {
        apiInput = ServiceEndpoints.shared.apiBaseURL
        staticInput = ServiceEndpoints.shared.staticBaseURL
    }

    private func save() {
        let apiOK = ServiceEndpoints.shared.setAPIBaseURL(apiInput)
        guard apiOK else {
            showToast("API 地址格式不正确，未保存", isError: true)
            return
        }

        let staticOK = ServiceEndpoints.shared.setStaticBaseURL(staticInput)
        guard staticOK else {
            showToast("静态资源地址格式不正确，未保存", isError: true)
            return
        }

        reload()
        showToast("已保存，后续请求立即使用新地址", isError: false)
    }

    private func reset() {
        ServiceEndpoints.shared.resetToDefaults()
        reload()
        showToast("已恢复为默认地址", isError: false)
    }

    private func showToast(_ message: String, isError: Bool) {
        toast = message
        toastIsError = isError
    }

    @MainActor
    private func runTest() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        guard let url = ServiceEndpoints.shared.apiURL("/api/user") else {
            testResult = "地址无效，无法构造请求"
            testSucceeded = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        if let token = AuthService.shared.effectiveAuthToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            testSucceeded = true
            testResult = "服务器可达 · HTTP \(code)\n\(url.absoluteString)"
        } catch {
            testSucceeded = false
            testResult = "连接失败 · \(error.localizedDescription)\n\(url.absoluteString)"
        }
    }
}
