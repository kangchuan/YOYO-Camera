import CoreGraphics
import CoreImage
import Foundation

/// Built-in filter registry (data-driven, extensible)
final class BuiltinFilterRegistry {
    static let shared = BuiltinFilterRegistry()

    private var filters: [String: FilterInfo] = [:]

    /// All built-in filter names (in order of registration)
    private(set) var allNames: [String] = []

    private init() {
        registerAllBuiltinFilters()
    }

    // MARK: - public method

    func info(for name: String) -> FilterInfo? {
        filters[name]
    }

    func contains(_ name: String) -> Bool {
        filters[name] != nil
    }

    // MARK: - Registration method

    private func register(name: String, info: FilterInfo) {
        filters[name] = info
        allNames.append(name)
    }

    // MARK: - Register all built-in filters

    /// 从声明式目录 `BuiltinFilterCatalog.all` 注册全部内置滤镜。
    ///
    /// 滤镜的定义（色温 / 强度 / 描述 / 渲染方式 / 胶片参数）不再写在这里，
    /// 而是集中在 `Filter/BuiltinFilterCatalog.swift`。新增滤镜请改那个文件。
    private func registerAllBuiltinFilters() {
        for spec in BuiltinFilterCatalog.all {
            register(name: spec.name, info: spec.info)
        }
    }
}

// MARK: - FilterIdentifier extension

extension FilterIdentifier {
    /// Get filter information
    var info: FilterInfo? {
        switch category {
        case .none:
            return FilterInfo(
                colorTemperature: .neutral,
                intensity: .subtle,
                descriptionKey: "filter_none_description",
                processingType: .builtin,
                chain: [],
                filmEffects: .originalCamera
            )
        case .builtin:
            return BuiltinFilterRegistry.shared.info(for: name)
        case .custom:
            return FilterInfo(
                colorTemperature: .neutral,
                intensity: .moderate,
                descriptionKey: "filter_custom_description",
                processingType: .custom
            )
        }
    }

    /// Color temperature type
    var colorTemperature: FilterColorTemperature {
        info?.colorTemperature ?? .neutral
    }

    /// filter strength
    var intensity: FilterIntensity {
        info?.intensity ?? .moderate
    }

    /// describe
    var description: String {
        info?.localizedDescription ?? ""
    }

    /// source of inspiration
    var inspired: String? {
        info?.inspired
    }

    /// display name
    var displayName: String {
        switch category {
        case .none:
            return String.filterNoneName.localized
        case .builtin:
            return name
        case .custom:
            return name
        }
    }
}

// MARK: - Search function

extension BuiltinFilterRegistry {
    /// Search filters based on keywords
    func search(keyword: String) -> [String] {
        let lowercaseKeyword = keyword.lowercased()

        return allNames.filter { name in
            guard let info = filters[name] else { return false }
            return name.lowercased().contains(lowercaseKeyword) ||
                info.localizedDescription.lowercased().contains(lowercaseKeyword) ||
                (info.inspired?.lowercased().contains(lowercaseKeyword) ?? false)
        }
    }
}
