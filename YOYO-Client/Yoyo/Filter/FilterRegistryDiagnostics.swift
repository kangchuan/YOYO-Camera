import Foundation
import UIKit

// MARK: - 滤镜注册完整性自检
//
// 目的：把「加一个内置滤镜时那些没写在文档里的隐性约定」变成可执行、会报错的检查。
//
// 使用方式：
//   1. 手动：App 内「设置 → 开发者模式 → 滤镜完整性自检」
//   2. 自动：DEBUG 构建启动时会在控制台打印一次（Release 完全不执行）
//
// 对应的扩展约定文档：`docs/FilterExtensionGuide.md`

enum FilterRegistryDiagnostics {

    // MARK: - 报告结构

    struct Issue: Identifiable {
        enum Severity: Equatable {
            case error // 一定会出问题：资源缺失、预设无效
            case warning // 可能不影响编译，但会让界面/功能不完整

            var label: String {
                switch self {
                case .error: return "错误"
                case .warning: return "警告"
                }
            }

            var rank: Int {
                switch self {
                case .error: return 0
                case .warning: return 1
                }
            }
        }

        let id = UUID()
        let severity: Severity
        /// 涉及的滤镜名（多个时以「、」分隔）
        let filters: String
        /// 检查项名称
        let check: String
        /// 具体说明与修复建议
        let detail: String
    }

    struct Report {
        /// 已注册的内置滤镜数量
        let filterCount: Int
        let issues: [Issue]

        var errorCount: Int { issues.filter { $0.severity == .error }.count }
        var warningCount: Int { issues.filter { $0.severity == .warning }.count }
        var isHealthy: Bool { issues.isEmpty }

        /// 排序后的检查项（错误在前）
        var sortedIssues: [Issue] {
            issues.sorted { lhs, rhs in
                if lhs.severity.rank != rhs.severity.rank {
                    return lhs.severity.rank < rhs.severity.rank
                }
                return lhs.filters < rhs.filters
            }
        }

        /// 纯文本报告，便于整段复制粘贴
        var plainText: String {
            var lines: [String] = []
            lines.append("内置滤镜数量：\(filterCount)")
            lines.append("错误 \(errorCount) 项 · 警告 \(warningCount) 项")
            lines.append("")

            if issues.isEmpty {
                lines.append("全部检查通过。")
            } else {
                for issue in sortedIssues {
                    lines.append("[\(issue.severity.label)] \(issue.filters) — \(issue.check)")
                    lines.append("    \(issue.detail)")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - 执行自检

    /// 全量自检。纯读操作，可在任意线程调用（会读取 Bundle 资源与 UserDefaults）。
    static func run() -> Report {
        let specs = BuiltinFilterCatalog.all
        let registered = BuiltinFilterRegistry.shared.allNames
        var issues: [Issue] = []

        // 检查 1：目录与注册表一致
        // 正常情况下注册表只由目录驱动，二者必然一致；不一致说明有人绕过目录手动注册。
        let catalogNames = specs.map(\.name)
        if catalogNames != registered {
            issues.append(Issue(
                severity: .error,
                filters: "-",
                check: "注册表与目录不一致",
                detail: "目录 \(catalogNames.count) 项，注册表 \(registered.count) 项。"
                    + "请确保所有滤镜都通过 BuiltinFilterCatalog 注册，不要直接调用 register(name:info:)。"
            ))
        }

        // 检查 2：滤镜名唯一
        var seen = Set<String>()
        var duplicates: [String] = []
        for spec in specs where !seen.insert(spec.name).inserted {
            duplicates.append(spec.name)
        }
        if !duplicates.isEmpty {
            issues.append(Issue(
                severity: .error,
                filters: duplicates.joined(separator: "、"),
                check: "滤镜名重复",
                detail: "同名滤镜会互相覆盖，后注册的生效，前一条的胶片参数被丢弃。"
            ))
        }

        let validPresetIDs = Set(FilmPreset.all.map(\.id))

        for spec in specs {
            // 检查 3：卡片背景图
            if UIImage(named: "\(spec.name)-bg") == nil {
                issues.append(Issue(
                    severity: .error,
                    filters: spec.name,
                    check: "缺少卡片背景图",
                    detail: "需要在 Assets.xcassets 里添加 \(spec.name)-bg.imageset，否则滤镜卡片上是一片空白。"
                ))
            }

            // 检查 4：LUT 数据集
            if spec.kind == .lut, NSDataAsset(name: spec.name) == nil {
                issues.append(Issue(
                    severity: .error,
                    filters: spec.name,
                    check: "缺少 LUT 数据集",
                    detail: "需要在 Assets.xcassets 里添加 \(spec.name).dataset（内含 .cube 文件），"
                        + "否则该滤镜选了也不生效。"
                ))
            }

            // 检查 5：描述文案
            let missingLanguages = ["en", "zh-Hans"].filter {
                localizedValue(for: spec.descriptionKey, language: $0) == nil
            }
            if !missingLanguages.isEmpty {
                issues.append(Issue(
                    severity: .warning,
                    filters: spec.name,
                    check: "描述文案缺失",
                    detail: "key「\(spec.descriptionKey)」在 \(missingLanguages.joined(separator: " / ")) 中不存在，"
                        + "界面上会显示空描述。补充后记得跑 scripts/generate_localized_strings.py。"
                ))
            }

            // 检查 6：胶片预设有效性
            let presetID = spec.filmEffects.filmPresetID
            if !presetID.isEmpty, !validPresetIDs.contains(presetID) {
                issues.append(Issue(
                    severity: .error,
                    filters: spec.name,
                    check: "胶片预设无效",
                    detail: "filmPresetID「\(presetID)」不在 FilmPreset.all 中，渲染会回落到默认预设，"
                        + "画面颜色与预期不符。"
                ))
            }

            // 检查 7：胶片模拟成员一致性
            // 这是一个纯约定：FilterInfo 里的 kind 与 FilterType.swift 的静态列表必须同步。
            let byKind = (spec.kind == .filmSimulation)
            let byList = FilterIdentifier.filmSimulationFilters.contains(.builtin(spec.name))
            if byKind != byList {
                issues.append(Issue(
                    severity: .error,
                    filters: spec.name,
                    check: "胶片模拟成员不一致",
                    detail: byKind
                        ? "目录里声明为 filmSimulation，但没有加进 FilterType.swift 的 "
                        + "FilterIdentifier.filmSimulationFilters，它会被当成普通滤镜显示在错误的分组里。"
                        : "它在 FilterIdentifier.filmSimulationFilters 中，但目录里声明的渲染方式是 LUT。"
                ))
            }
        }

        // 检查 8：历史偏好里引用了已不存在的滤镜
        let registeredSet = Set(registered)
        let stale = staleReferences(in: registeredSet)
        if !stale.isEmpty {
            issues.append(Issue(
                severity: .warning,
                filters: stale.joined(separator: "、"),
                check: "历史数据残留",
                detail: "这些名字还留在本机已保存的偏好（选中滤镜 / 收藏 / 隐藏 / 强度）里，但已不在注册表中。"
                    + "如果是有意改名，用户的滤镜选择、强度与收藏都会丢失，需要写迁移映射。"
            ))
        }

        return Report(filterCount: registered.count, issues: issues)
    }

    /// DEBUG 构建启动时打印一次自检结果；Release 下整个函数体为空，不产生任何开销。
    static func logOnLaunch() {
        #if DEBUG
            let report = run()
            if report.isHealthy {
                print("[FilterDiagnostics] ✅ \(report.filterCount) 个内置滤镜，全部检查通过")
            } else {
                print("[FilterDiagnostics] ⚠️ \(report.errorCount) 个错误 / \(report.warningCount) 个警告")
                print(report.plainText)
            }
        #endif
    }

    // MARK: - 内部工具

    /// 从指定语言的 .lproj 读取本地化值，缺失返回 nil
    private static func localizedValue(for key: String, language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return nil
        }
        let sentinel = "\u{0}__FILTER_DIAGNOSTICS_MISSING__"
        let value = bundle.localizedString(forKey: key, value: sentinel, table: nil)
        return value == sentinel ? nil : value
    }

    /// 收集本机已持久化、但已不在注册表中的内置滤镜名
    private static func staleReferences(in registered: Set<String>) -> [String] {
        var stale = Set<String>()

        for identifier in persistedFilterIdentifiers() {
            guard !identifier.isEmpty else { continue }

            if let colon = identifier.firstIndex(of: ":") {
                let category = String(identifier[identifier.startIndex ..< colon])
                let name = String(identifier[identifier.index(after: colon)...])
                // 只关心内置滤镜；custom: 与 none: 跳过
                guard category == "builtin", !registered.contains(name) else { continue }
                stale.insert(name)
            } else {
                // 兼容更早的裸名称格式；"Origin" 是 FC 的旧名，已由解析层重定向
                guard identifier != "Origin", !registered.contains(identifier) else { continue }
                stale.insert(identifier)
            }
        }

        return stale.sorted()
    }

    /// 读取所有可能存有滤镜标识的持久化字段（解析失败则跳过该字段）
    private static func persistedFilterIdentifiers() -> [String] {
        let defaults = UserDefaults.standard
        var result: [String] = []

        if let selected = defaults.string(forKey: "selectedFilter") {
            result.append(selected)
        }

        // favoriteFilters / hiddenFilters 存的是 JSON 数组；
        // filterCustomEffects / filterIntensities 存的是 JSON 字典（这里只取 key）。
        for key in ["favoriteFilters", "hiddenFilters", "filterCustomEffects", "filterIntensities"] {
            guard let raw = defaults.string(forKey: key),
                  let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
            else {
                continue
            }

            if let array = object as? [String] {
                result.append(contentsOf: array)
            } else if let dict = object as? [String: Any] {
                result.append(contentsOf: dict.keys)
            }
        }

        return result
    }
}
