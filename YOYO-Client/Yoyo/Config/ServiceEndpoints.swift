import Foundation

/// 集中管理 App 依赖的所有外部服务地址。
///
/// 在此之前，API 域名以字面量形式散落在 4 个 service 里，静态资源域名又散落在 2 个视图里，
/// 二次开发想换成自建后端时无从下手。现在统一从这里取。
///
/// 解析优先级（高 → 低）：
///   1. Xcode 运行环境变量 `API_BASE_URL` / `STATIC_BASE_URL`（仅从 Xcode 启动时存在，适合临时调试）
///   2. 本地自定义覆盖（设置 → 开发者模式 → 服务地址，保存后立即生效，无需重新编译）
///   3. Info.plist 构建期配置（`APIBaseURL` / `StaticBaseURL`，适合多环境打包）
///   4. 内置默认值（上游 Day1Labs 线上地址）
///
/// 新增网络请求时，请通过 `apiURL(_:)` / `staticURL(_:)` 构造地址，不要再硬编码域名。
final class ServiceEndpoints {

    static let shared = ServiceEndpoints()

    // MARK: - 内置默认值

    /// 业务 API 基地址（登录、AI 修图、灵感、自动化分享）
    static let defaultAPIBaseURL = "https://yoyo.day1-labs.com"

    /// 静态资源基地址（用户协议、隐私政策等法务文档）
    static let defaultStaticBaseURL = "https://static.day1-labs.com/yoyo"

    // MARK: - 键名

    private enum OverrideKey {
        static let api = "service.apiBaseURL"
        static let statics = "service.staticBaseURL"
    }

    private enum PlistKey {
        static let api = "APIBaseURL"
        static let statics = "StaticBaseURL"
    }

    private enum EnvKey {
        static let api = "API_BASE_URL"
        static let statics = "STATIC_BASE_URL"
    }

    /// 地址来源，用于在配置界面上标注当前值是从哪一层取到的
    enum Source: String {
        case environment = "Xcode 环境变量"
        case override = "本地自定义"
        case plist = "Info.plist"
        case builtIn = "内置默认"
    }

    /// `URL(string:)` 对本字面量不会失败，仅作为兜底，正常流程不会走到
    private static let fallbackURL = URL(string: "https://invalid.local")!

    private let defaults: UserDefaults

    private init() {
        defaults = .standard
    }

    // MARK: - 生效值

    /// 业务 API 基地址（已规范化：带 scheme、无结尾斜杠）
    var apiBaseURL: String {
        resolve(
            envKey: EnvKey.api,
            overrideKey: OverrideKey.api,
            plistKey: PlistKey.api,
            fallback: Self.defaultAPIBaseURL
        ).value
    }

    /// 静态资源基地址（已规范化）
    var staticBaseURL: String {
        resolve(
            envKey: EnvKey.statics,
            overrideKey: OverrideKey.statics,
            plistKey: PlistKey.statics,
            fallback: Self.defaultStaticBaseURL
        ).value
    }

    /// 当前 API 地址来自哪一层
    var apiBaseURLSource: Source {
        resolve(
            envKey: EnvKey.api,
            overrideKey: OverrideKey.api,
            plistKey: PlistKey.api,
            fallback: Self.defaultAPIBaseURL
        ).source
    }

    /// 当前静态资源地址来自哪一层
    var staticBaseURLSource: Source {
        resolve(
            envKey: EnvKey.statics,
            overrideKey: OverrideKey.statics,
            plistKey: PlistKey.statics,
            fallback: Self.defaultStaticBaseURL
        ).source
    }

    /// 是否存在本地自定义覆盖
    var isCustomized: Bool {
        defaults.string(forKey: OverrideKey.api) != nil
            || defaults.string(forKey: OverrideKey.statics) != nil
    }

    // MARK: - 写入自定义值

    /// 保存自定义 API 地址。传空字符串表示清除覆盖、回落到下一优先级。
    /// - Returns: 是否保存成功（地址非法时返回 false 且不写入）
    @discardableResult
    func setAPIBaseURL(_ raw: String) -> Bool {
        setOverride(raw, key: OverrideKey.api, fallback: Self.defaultAPIBaseURL)
    }

    /// 保存自定义静态资源地址。传空字符串表示清除覆盖。
    @discardableResult
    func setStaticBaseURL(_ raw: String) -> Bool {
        setOverride(raw, key: OverrideKey.statics, fallback: Self.defaultStaticBaseURL)
    }

    /// 清除全部本地覆盖，回到 Info.plist / 内置默认值
    func resetToDefaults() {
        defaults.removeObject(forKey: OverrideKey.api)
        defaults.removeObject(forKey: OverrideKey.statics)
    }

    // MARK: - URL 构造

    /// 拼接 API 地址，例如 `apiURL("/api/user")`
    func apiURL(_ path: String, query: [String: String] = [:]) -> URL? {
        Self.makeURL(base: apiBaseURL, path: path, query: query)
    }

    /// 拼接静态资源地址，例如 `staticURL("user-agreement", query: ["lang": "zh-Hans"])`
    func staticURL(_ path: String, query: [String: String] = [:]) -> URL {
        Self.makeURL(base: staticBaseURL, path: path, query: query) ?? Self.fallbackURL
    }

    /// 同上，返回字符串形式（给 WebView 之类只需要字符串的场景）
    func staticURLString(_ path: String, query: [String: String] = [:]) -> String {
        staticURL(path, query: query).absoluteString
    }

    // MARK: - 内部实现

    private func resolve(
        envKey: String,
        overrideKey: String,
        plistKey: String,
        fallback: String
    ) -> (value: String, source: Source) {
        if let value = Self.normalize(ProcessInfo.processInfo.environment[envKey]) {
            return (value, .environment)
        }
        if let value = Self.normalize(defaults.string(forKey: overrideKey)) {
            return (value, .override)
        }
        let plistValue = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String
        if let value = Self.normalize(plistValue) {
            return (value, .plist)
        }
        return (fallback, .builtIn)
    }

    @discardableResult
    private func setOverride(_ raw: String, key: String, fallback: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
            return true
        }
        guard let value = Self.normalize(trimmed) else { return false }
        // 与内置默认值相同时不写覆盖，保持来源标识清晰
        if value == fallback {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
        return true
    }

    /// 规范化用户输入：补 scheme、去结尾斜杠、校验 host。
    /// 局域网地址自动补 `http://`（本地后端通常没有证书），其余补 `https://`。
    static func normalize(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let lowercased = value.lowercased()
        if !lowercased.hasPrefix("http://"), !lowercased.hasPrefix("https://") {
            value = (isLikelyLocalHost(value) ? "http://" : "https://") + value
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else {
            return nil
        }

        return value
    }

    /// 判断是否像局域网 / 本机地址
    private static func isLikelyLocalHost(_ value: String) -> Bool {
        let hostPart = value.split(separator: "/").first.map(String.init) ?? value
        let host = hostPart.split(separator: ":").first.map(String.init) ?? hostPart
        let lower = host.lowercased()

        if lower == "localhost" || lower.hasSuffix(".local") { return true }
        if lower.hasPrefix("127.") { return true }
        if lower.hasPrefix("192.168.") || lower.hasPrefix("10.") { return true }
        if lower.hasPrefix("172.") {
            let second = lower.split(separator: ".").dropFirst().first.flatMap { Int($0) } ?? 0
            return (16...31).contains(second)
        }
        return false
    }

    private static func makeURL(base: String, path: String, query: [String: String]) -> URL? {
        var string = base
        if !path.isEmpty {
            string += path.hasPrefix("/") ? path : "/" + path
        }

        guard var components = URLComponents(string: string) else { return nil }

        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        return components.url
    }
}
