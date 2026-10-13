import Foundation

// MARK: - 内置滤镜声明式目录
//
// 这里是「内置滤镜」的唯一事实来源（single source of truth）。
// 新增 / 修改一个内置滤镜，通常只需要在这个文件里加一条 `FilterSpec`。
//
// 完整约定与所需资源见 `docs/FilterExtensionGuide.md`。
// 资源是否齐备可在 App 内「设置 → 开发者模式 → 滤镜完整性自检」中验证。

/// 滤镜的渲染方式
enum FilterProcessingKind: Equatable {
    /// 胶片物理模拟：走 `FilmComputeEngine` + Metal 着色器，`chain` 为空（当前为 FC / LC / GR）
    case filmSimulation
    /// 颜色查找表：走 `Assets.xcassets/<滤镜名>.dataset` 内的 .cube 数据
    case lut

    /// 对应的渲染类型
    func processingType(name: String) -> FilterProcessingType {
        switch self {
        case .filmSimulation: return .builtin
        case .lut: return .lut(name)
        }
    }
}

/// 单个内置滤镜的声明式定义
struct FilterSpec {
    /// 滤镜唯一标识。同时决定三件事：
    /// 1. 卡片背景图资源名 = `"\(name)-bg"`（imageset）
    /// 2. LUT 数据集资源名 = `name`（dataset，仅 `.lut` 需要）
    /// 3. 持久化标识 `builtin:<name>`（改动此值会让用户已保存的选择失效）
    let name: String

    /// 色温标签，用于卡片角标与 AI 推荐
    let colorTemperature: FilterColorTemperature

    /// 强度档位，用于卡片角标与默认强度换算
    let intensity: FilterIntensity

    /// 本地化 key，必须同时存在于 `en.lproj/Localizable.strings` 与 `zh-Hans.lproj/Localizable.strings`
    let descriptionKey: String

    /// 灵感来源（如 "C200"、"Pro 400H"），显示在卡片上；无则不显示
    let inspired: String?

    /// 渲染方式
    let kind: FilterProcessingKind

    /// 附加 Core Image 滤镜链；空数组表示不加额外链（胶片模拟滤镜固定为空）
    let chain: [FilterChainStep]

    /// 该滤镜的默认胶片物理参数（仅 `.filmSimulation` 与 LUT 叠加部分生效）
    let filmEffects: FilterDefaultFilmEffects

    init(
        name: String,
        colorTemperature: FilterColorTemperature,
        intensity: FilterIntensity = .moderate,
        descriptionKey: String,
        inspired: String? = nil,
        kind: FilterProcessingKind,
        chain: [FilterChainStep] = [],
        filmEffects: FilterDefaultFilmEffects = .none
    ) {
        self.name = name
        self.colorTemperature = colorTemperature
        self.intensity = intensity
        self.descriptionKey = descriptionKey
        self.inspired = inspired
        self.kind = kind
        self.chain = chain
        self.filmEffects = filmEffects
    }

    /// 转换为注册表使用的 `FilterInfo`
    var info: FilterInfo {
        FilterInfo(
            colorTemperature: colorTemperature,
            intensity: intensity,
            descriptionKey: descriptionKey,
            inspired: inspired,
            processingType: kind.processingType(name: name),
            chain: chain,
            filmEffects: filmEffects
        )
    }
}

// MARK: - 胶片物理模拟滤镜
//
// 这三个走 `FilterProcessingKind.filmSimulation`：
// 只给出一组胶片物理参数，颜色由 Metal 端按预设（FilmPreset）算出，不使用 LUT。
// 它们的成员身份还硬编码在 `FilterType.swift` 的 `FilterIdentifier.filmSimulationFilters` 中，
// 新增同类滤镜时必须同步维护（自检会提示）。

/// 胶片感（FC / LC / GR）—— 品牌还原系列
enum FilmSimulationFilterCatalog {
    static let all: [FilterSpec] = [
        // FC — 富士风格
        FilterSpec(
            name: "FC",
            colorTemperature: .neutral,
            intensity: .moderate,
            descriptionKey: "filter_f_chrome_description",
            kind: .filmSimulation,
            filmEffects: FilterDefaultFilmEffects(
                cineToneIntensity: 1.0, // 拉满强度，让物理模型完全生效
                filmPresetID: FilmPreset.fujiEterna.id, // fujifilmClassicChrome
                vignetteIntensity: 0.15, // 0.35 -> 0.15：模拟相机直出，减弱过度压暗
                grainIntensity: 0.20 // 颗粒略多
            )
        ),
        // LC — 徕卡风格
        FilterSpec(
            name: "LC",
            colorTemperature: .warm,
            intensity: .strong,
            descriptionKey: "filter_l_classic_description",
            kind: .filmSimulation,
            filmEffects: FilterDefaultFilmEffects(
                cineToneIntensity: 1.0,
                filmPresetID: FilmPreset.agfaVista400.id, // leicaClassic
                vignetteIntensity: 0.25, // 0.35 -> 0.25：弱化暗角，提亮画面边缘
                grainIntensity: 0.12 // 微量有机颗粒，消除数码感
            )
        ),
        // GR — 理光风格
        FilterSpec(
            name: "GR",
            colorTemperature: .neutral, // 改为中性，主要靠预设的 printWarmth 偏色
            intensity: .strong,
            descriptionKey: "filter_gr_description",
            kind: .filmSimulation,
            filmEffects: FilterDefaultFilmEffects(
                cineToneIntensity: 1.0,
                filmPresetID: FilmPreset.kodak5219.id, // ricohGR
                halationIntensity: 0,
                vignetteIntensity: 0.30, // 0.35 -> 0.30：微调暗角
                grainIntensity: 0.25 // 0.30 -> 0.25：微调颗粒
            )
        ),
    ]
}

// MARK: - LUT 滤镜：通用风格系列

/// 通用风格（Silk / Breeze / Dusk / Pearl / Horizon / Haze / Dawn / Blossom / Frost / Petal / Oasis / 黑白）
enum ClassicFilterCatalog {
    static let all: [FilterSpec] = [
        FilterSpec(
            name: "Silk",
            colorTemperature: .neutral,
            descriptionKey: "filter_spring_description",
            inspired: "FP 100C",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakPortra400.id, // Portra 400 — FP 100C 的柔化肤色特性
                bloomIntensity: 0.15, // 柔光晕
                vignetteIntensity: 0.10,
                grainIntensity: 0.08
            )
        ),
        FilterSpec(
            name: "Breeze",
            colorTemperature: .warm,
            intensity: .subtle,
            descriptionKey: "filter_breeze_description",
            inspired: "C200",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakVision3.id, // Kodak Vision3 — C200 的暖调日常感
                halationIntensity: 0.10, // 暖光晕
                fogIntensity: 0.08,
                grainIntensity: 0.12
            )
        ),
        FilterSpec(
            name: "Dusk",
            colorTemperature: .neutral,
            descriptionKey: "filter_dusk_description",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodak5219.id, // Kodak 5219 — 黄昏时的高对比与深阴影
                halationIntensity: 0.08,
                vignetteIntensity: 0.20, // 中等暗角
                grainIntensity: 0.15
            )
        ),
        FilterSpec(
            name: "Pearl",
            colorTemperature: .neutral,
            intensity: .subtle,
            descriptionKey: "filter_kyoto_description",
            inspired: "Pro 160S",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakPortra400.id, // Portra 400 — Pro 160S 的细腻肤感
                bloomIntensity: 0.12,
                vignetteIntensity: 0.08,
                grainIntensity: 0.05
            )
        ),
        FilterSpec(
            name: "Horizon",
            colorTemperature: .cool,
            descriptionKey: "filter_horizon_description",
            inspired: "Provia 100F",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakEktar100.id, // Ektar 100 — Provia 的明亮色彩与细颗粒
                bloomIntensity: 0.08,
                vignetteIntensity: 0.12,
                grainIntensity: 0.06
            )
        ),
        FilterSpec(
            name: "Haze",
            colorTemperature: .neutral,
            descriptionKey: "filter_haze_description",
            inspired: "Film 3513",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.cinestill800T.id, // CineStill 800T — 电影胶片的独特辉光
                halationIntensity: 0.18, // 主效果：红色光晕
                fogIntensity: 0.20, // 中等雾感
                grainIntensity: 0.18
            )
        ),
        FilterSpec(
            name: "Dawn",
            colorTemperature: .warm,
            intensity: .subtle,
            descriptionKey: "filter_dawn_description",
            inspired: "Sensia 100",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakPortra400.id, // Portra 400 — Sensia 的柔和暖调
                bloomIntensity: 0.15, // 柔光晕
                grainIntensity: 0.08
            )
        ),
        FilterSpec(
            name: "Blossom",
            colorTemperature: .warm,
            intensity: .strong,
            descriptionKey: "filter_blossom_description",
            inspired: "Velvia 50",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.fujiVelvia50.id, // Velvia 50 — 高饱和与浓郁色彩
                // Velvia 以锐利著称，不应有光晕
                vignetteIntensity: 0.15,
                grainIntensity: 0.05 // 细颗粒
            )
        ),
        FilterSpec(
            name: "Frost",
            colorTemperature: .cool,
            descriptionKey: "filter_frost_description",
            inspired: "T64",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.fujiEterna.id, // Fuji Eterna — T64 的冷调钨丝灯特性
                halationIntensity: 0.15, // 冷光晕
                fogIntensity: 0.08,
                grainIntensity: 0.10
            )
        ),
        FilterSpec(
            name: "Petal",
            colorTemperature: .cool,
            intensity: .subtle,
            descriptionKey: "filter_petal_description",
            inspired: "Astia 100F",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.fujiPro400H.id, // Fuji Pro 400H — Astia 的柔和肤色与粉彩调
                bloomIntensity: 0.12,
                vignetteIntensity: 0.06,
                grainIntensity: 0.05
            )
        ),
        FilterSpec(
            name: "Oasis",
            colorTemperature: .cool,
            intensity: .subtle,
            descriptionKey: "filter_oasis_description",
            inspired: "Pro 400H",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.fujiPro400H.id, // Fuji Pro 400H — 通透柔和的高光
                bloomIntensity: 0.10, // 柔光晕
                fogIntensity: 0.15, // 空气感
                grainIntensity: 0.15
            )
        ),
        // 黑白
        FilterSpec(
            name: "Decisive",
            colorTemperature: .blackWhite,
            intensity: .strong,
            descriptionKey: "filter_decisive_description",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodak5219.id, // Kodak 5219 — 深黑高对比黑白
                halationIntensity: 0.08,
                vignetteIntensity: 0.25, // 中等暗角
                grainIntensity: 0.25 // 明显但不过分的颗粒
            )
        ),
        FilterSpec(
            name: "Fan",
            colorTemperature: .blackWhite,
            intensity: .strong,
            descriptionKey: "filter_fan_description",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakPortra400.id, // Portra 400 — 层次丰富的柔和黑白
                bloomIntensity: 0.15, // 柔光晕
                fogIntensity: 0.06,
                grainIntensity: 0.18
            )
        ),
    ]
}

// MARK: - LUT 滤镜：亚洲地域系列（中国 / 日本）

enum AsiaFilterCatalog {
    static let all: [FilterSpec] = [
        FilterSpec(
            name: "Xihu",
            colorTemperature: .cool,
            descriptionKey: "filter_xihu_description",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.fujiEterna.id, // Fuji Eterna — 西湖的冷调水墨意境
                bloomIntensity: 0.12,
                fogIntensity: 0.18, // 水墨雾感
                vignetteIntensity: 0.10,
                grainIntensity: 0.08
            )
        ),
        // 胶片怀旧、褪色哑光质感、暖肤色、降饱和的黄绿色
        FilterSpec(
            name: "Dali",
            colorTemperature: .warm,
            descriptionKey: "filter_dali_description",
            inspired: "Sensia 200",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakVision3.id, // Kodak Vision3 — 大理的暖阳与怀旧感
                halationIntensity: 0.12, // 暖光晕
                fogIntensity: 0.10,
                vignetteIntensity: 0.12,
                grainIntensity: 0.15
            )
        ),
        FilterSpec(
            name: "Fuji",
            colorTemperature: .neutral,
            descriptionKey: "filter_fuji_description",
            inspired: "Pro 160NC",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakPortra400.id, // Portra 400 — Pro 160NC 的自然色
                bloomIntensity: 0.08,
                vignetteIntensity: 0.10,
                grainIntensity: 0.10
            )
        ),
        FilterSpec(
            name: "Kamakura",
            colorTemperature: .neutral,
            descriptionKey: "filter_kamakura_description",
            inspired: "ProImage 100",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakVision3.id, // Kodak Vision3 — 日系清新
                bloomIntensity: 0.10,
                vignetteIntensity: 0.15,
                grainIntensity: 0.12
            )
        ),
    ]
}

// MARK: - LUT 滤镜：欧洲 / 美洲 / 非洲地域系列

enum RegionalFilterCatalog {
    static let all: [FilterSpec] = [
        FilterSpec(
            name: "Lisbon",
            colorTemperature: .warm,
            descriptionKey: "filter_lisbon_description",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.cinestill800T.id, // CineStill 800T — 里斯本的暖街与霓虹
                halationIntensity: 0.18, // CineStill 标志性红晕
                vignetteIntensity: 0.12,
                grainIntensity: 0.15
            )
        ),
        FilterSpec(
            name: "Faroe",
            colorTemperature: .cool,
            descriptionKey: "filter_faroe_description",
            inspired: "Pro 400H", // 低饱和空气感，环境色融入冷青蓝与薄荷绿，保留暖金色肤色，画面带柔和怀旧的哑光褪色质感
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.fujiPro400H.id, // Fuji Pro 400H — 法罗群岛的空气感与柔和褪色
                bloomIntensity: 0.10,
                fogIntensity: 0.20, // 空气雾感
                grainIntensity: 0.18
            )
        ),
        FilterSpec(
            name: "Marrakech",
            colorTemperature: .neutral,
            descriptionKey: "filter_marrakech_description",
            inspired: "2383", // 暖调复古电影感，渲染成黄金日落般的大气，阴影深青蓝、绿色干枯低饱和橄榄绿
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodak5219.id, // Kodak 5219 / 2383 — 马拉喀什的金色日落与电影感
                halationIntensity: 0.15, // 胶片光晕
                vignetteIntensity: 0.20,
                grainIntensity: 0.22
            )
        ),
        FilterSpec(
            name: "GoldenGate",
            colorTemperature: .neutral,
            descriptionKey: "filter_golden_gate_description",
            inspired: "Gold 200",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakGold200.id, // Gold 200 的暖金色调
                halationIntensity: 0.12, // 金色光晕
                vignetteIntensity: 0.12,
                grainIntensity: 0.15
            )
        ),
        FilterSpec(
            name: "Joshua",
            colorTemperature: .neutral,
            intensity: .subtle,
            descriptionKey: "filter_joshua_description",
            inspired: "Portra 400",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakPortra400.id, // Portra 400 — 约书亚树的柔和沙漠光
                bloomIntensity: 0.08,
                fogIntensity: 0.05,
                vignetteIntensity: 0.10,
                grainIntensity: 0.12
            )
        ),
        FilterSpec(
            name: "Havana",
            colorTemperature: .warm,
            descriptionKey: "filter_havana_description",
            // 电影胶片，"干燥、褪色、暖调、长期日晒后的陈旧感"。
            // 大幅抑制蓝色（天空变灰）并强化土色（黄/橙/棕），不适合以碧海蓝天著称的场景（如马尔代夫），
            // 但非常适合"尘感""岩石质感"或"怀旧年代感"的场景
            inspired: "5219",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodak5219.id, // Kodak 5219 — 哈瓦那的复古电影感与褪色质感
                halationIntensity: 0.15, // 复古光晕
                fogIntensity: 0.10,
                vignetteIntensity: 0.20,
                grainIntensity: 0.25
            )
        ),
        // 暖调高、冷色低饱和、奶油高光、复古绿
        FilterSpec(
            name: "Sahara",
            colorTemperature: .warm,
            descriptionKey: "filter_dune_description",
            kind: .lut,
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: FilmPreset.kodakVision3.id, // Kodak Vision3 — 撒哈拉的金色沙漠与暖光
                halationIntensity: 0.12, // 沙漠光晕
                fogIntensity: 0.12,
                vignetteIntensity: 0.15,
                grainIntensity: 0.18
            )
        ),
    ]
}

// MARK: - 总目录

enum BuiltinFilterCatalog {
    /// 全部已启用的内置滤镜，**数组顺序即 UI 中的展示顺序**
    static let all: [FilterSpec] =
        FilmSimulationFilterCatalog.all
            + ClassicFilterCatalog.all
            + AsiaFilterCatalog.all
            + RegionalFilterCatalog.all

    /// 仅供快速核对：按名称取定义
    static func spec(named name: String) -> FilterSpec? {
        all.first { $0.name == name }
    }

    // MARK: - 待启用滤镜（素材部分就位，需补齐后取消注释）
    //
    // 下面这些滤镜的名字来自上游仓库的注释代码。素材情况已实测标注：
    //   [bg-][ds-] Lijiang / Potala / Wuzhen / Taipei / Sagami / Shibuya / Vegas
    //               背景图与 .cube 数据集都有，**只差中英文描述文案**，补齐后可直接启用
    //   [bgx][ds-] Paris / London / Vienna / Alpine / Iceland / Santorini
    //              Hollywood / California / Texas / NewYork / Yosemite / Patagonia
    //               有 .cube 数据集，但缺 `<名称>-bg.imageset`，且缺描述文案
    //   [bg-][dsx] Vivid / H-Master
    //               只有背景图，没有 .cube 数据集（上游未完成）
    //
    // 启用步骤见 `docs/FilterExtensionGuide.md` 的「启用一个已有素材的新滤镜」。
    //
    // 中国：
    //   Lijiang  (cool, moderate, "filter_lijiang_description")
    //   Potala   (warm, strong,   "filter_potala_description", inspired: "Fortia SP")
    //   Wuzhen   (cool, moderate, "filter_wuzhen_description", inspired: "Provia 400X")
    //   Taipei   (warm, subtle,   "filter_taipei_description",   inspired: "C200")
    // 日本：
    //   Sagami   (cool, moderate, "filter_sagami_description")
    //   Shibuya  (cool, strong,   "filter_shibuya_description")
    // 欧洲：
    //   Paris    (warm, subtle,   "filter_paris_description",    inspired: "Pro 400H")
    //   London   (warm, moderate, "filter_london_description")
    //   Vienna   (neutral, moderate, "filter_vienna_description")
    //   Alpine   (cool, moderate, "filter_alpine_description")
    //   Iceland  (cool, strong,   "filter_iceland_description")
    //   Santorini(warm, subtle,   "filter_santorini_description", inspired: "Pro 400H")
    // 美洲：
    //   Hollywood(neutral, moderate, "filter_hollywood_description", inspired: "5294")
    //   California(warm, strong,  "filter_california_description",  inspired: "Ektar 100")
    //   Texas    (warm, moderate, "filter_texas_description",       inspired: "Gold Master")
    //   Vegas    (warm, moderate, "filter_vegas_description",       inspired: "UltraMax 400")
    //   NewYork  (cool, strong,   "filter_newyork_description")
    //   Yosemite (neutral, moderate, "filter_yosemite_description")
    //   Patagonia(cool, moderate, "filter_patagonia_description")
    // 素材不全：
    //   Vivid / H-Master（只有背景图）
}
