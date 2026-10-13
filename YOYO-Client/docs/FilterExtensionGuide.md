# 滤镜扩展指南（内置滤镜）

> 目标：让「加一个内置滤镜」从**靠猜**变成**照做**。
>
> 相关文件：
> - 滤镜定义（唯一事实来源）：`Yoyo/Filter/BuiltinFilterCatalog.swift`
> - 注册表：`Yoyo/Filter/BuiltinFilterRegistry.swift`
> - 完整性自检：`Yoyo/Filter/FilterRegistryDiagnostics.swift`
> - 资源目录：`Yoyo/Assets.xcassets/`

---

## 0. 先跑一次自检，建立基线

两种方式任选：

| 方式 | 位置 |
|---|---|
| 手动 | App → 设置 → 开发者模式 → **滤镜完整性自检** |
| 自动 | DEBUG 构建启动时控制台会打印 `[FilterDiagnostics] …` |

报告里的每一条都是可直接执行的修复指令。改动滤镜相关代码后**务必再跑一次**。

---

## 1. 三种滤镜，改的东西不一样

| 类型 | `kind` | 渲染路径 | 需要 `.cube` 数据集 | 现有成员 |
|---|---|---|---|---|
| 胶片物理模拟 | `.filmSimulation` | `FilmComputeEngine` + Metal 着色器，颜色由 `FilmPreset` 算出 | ❌ 不需要 | FC / LC / GR |
| LUT 滤镜 | `.lut` | `Assets.xcassets/<名称>.dataset` 里的 `.cube` | ✅ 需要 | 其余 24 个 |

> LUT 数据集的资源名**必须等于滤镜名**。`FilterIdentifier+Config.swift` 里 `imageName = name + "-bg"`、
> `processingType` 对 LUT 用滤镜名兜底，这两个约定是隐式的，写错了不会有编译错误。

---

## 2. 触点清单

| # | 要改的东西 | 什么时候要改 | 漏了会怎样 |
|---|---|---|---|
| 1 | `Filter/BuiltinFilterCatalog.swift` 加一条 `FilterSpec` | **必改** | 滤镜不存在 |
| 2 | `en.lproj/Localizable.strings` + `zh-Hans.lproj/Localizable.strings` 加 `descriptionKey` | **必改** | 卡片描述空白（不报错） |
| 3 | 跑 `python3 scripts/generate_localized_strings.py` | **必改** | `AGENTS.md` 明令禁止留下「改了 strings 但没重新生成」的 diff |
| 4 | `Assets.xcassets/<名称>-bg.imageset`（卡片背景图） | **必改** | 卡片一片空白 |
| 5 | `Assets.xcassets/<名称>.dataset`（内含 `<名称>.cube`） | 仅 `.lut` | 选了滤镜但画面没变化 |
| 6 | `Filter/FilterType.swift` 的 `filmSimulationFilters` | 仅 `.filmSimulation` | 被分到错误的展示分组（「胶片」组 vs 普通组） |

**不需要改的**（读目录自动生效）：

- `Filter/FilterConfigManager.swift` — 从 `allNames` 遍历生成配置
- `Filter/FilterIdentifier+Config.swift` — 从 `FilterInfo` 推导卡片样式
- `Filter/FilterGalleryView.swift` — 从 `allVisibleFilters` 取列表
- `FilterManager.allVisibleFilters` — 顺序就是目录里数组的顺序
- `FilterManager.swift` 的 `applyFilter` 分发 — 只认 `processingType`

---

## 3. 示例 A：新增一个全新的 LUT 滤镜

假设要加一个叫 `Kyoto` 的滤镜。

### 3.1 写定义

在 `BuiltinFilterCatalog.swift` 的 `ClassicFilterCatalog.all` 里追加（**位置决定展示顺序**）：

```swift
FilterSpec(
    name: "Kyoto",
    colorTemperature: .cool,
    intensity: .subtle,
    descriptionKey: "filter_kyoto_night_description",
    inspired: "Pro 400H",
    kind: .lut,
    filmEffects: FilterDefaultFilmEffects(
        filmPresetID: FilmPreset.fujiPro400H.id,
        bloomIntensity: 0.10,
        grainIntensity: 0.08
    )
),
```

`FilmDefaultFilmEffects` 的字段（未写的按 0，`filmPresetID` 未写则取 `FilmPreset.all.first`）：
`cineToneIntensity` / `halationIntensity` / `bloomIntensity` / `fogIntensity` /
`vignetteIntensity` / `grainIntensity` / `lightLeakIntensity`。

### 3.2 补文案

两个 strings 文件都要加（key 保持一致）：

```
// en.lproj/Localizable.strings
"filter_kyoto_night_description" = "Cool night tones with soft city glow";

// zh-Hans.lproj/Localizable.strings
"filter_kyoto_night_description" = "清冷夜色，柔和城市光晕";
```

然后：

```bash
cd Yoyo.xcodeproj 的上一级目录
python3 scripts/generate_localized_strings.py
```

### 3.3 放资源

1. `Assets.xcassets` 新建 `Kyoto-bg.imageset`，塞一张卡面图（参考现有 `Sahara-bg.imageset` 的 `Contents.json` 结构）。
2. `Assets.xcassets` 新建 `Kyoto.dataset`，里面：
   - `Kyoto.cube`（LUT 数据）
   - `Contents.json`：

```json
{
  "data" : [ { "filename" : "Kyoto.cube", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

### 3.4 验证

设置里跑「滤镜完整性自检」→ 应该 0 错误 0 警告 → 进相机划到新滤镜，确认有画面变化、卡片有图、描述有字。

---

## 4. 示例 B：新增一个胶片模拟滤镜

在 `FilmSimulationFilterCatalog.all` 里加，`kind` 用 `.filmSimulation`，**不要**放 `.dataset`：

```swift
FilterSpec(
    name: "Noir",
    colorTemperature: .blackWhite,
    intensity: .strong,
    descriptionKey: "filter_noir_description",
    kind: .filmSimulation,
    filmEffects: FilterDefaultFilmEffects(
        cineToneIntensity: 1.0,          // 物理模型要拉满才完全生效
        filmPresetID: FilmPreset.kodakTriX400.id,
        vignetteIntensity: 0.20,
        grainIntensity: 0.30
    )
),
```

**别忘了第 6 个触点** —— `Filter/FilterType.swift`：

```swift
static let filmSimulationFilters: [FilterIdentifier] = [.fChrome, .lClassic, .gr, .noir]
```

同时加一个静态成员：

```swift
static let noir = FilterIdentifier.builtin("Noir")
```

漏了这一步，自检会报「胶片模拟成员不一致」，界面会把它放进错误的展示分组。

---

## 5. 示例 C：启用一个已有素材的滤镜

`BuiltinFilterCatalog.swift` 文件末尾的注释块列了 19 个上游写好但被注释掉的滤镜，并标了素材齐备情况：

| 素材状态 | 滤镜 | 还差什么 |
|---|---|---|
| 背景图 + `.cube` 都有 | Lijiang / Potala / Wuzhen / Taipei / Sagami / Shibuya / Vegas | **只差中英文描述文案** |
| 只有 `.cube` | Paris / London / Vienna / Alpine / Iceland / Santorini / Hollywood / California / Texas / NewYork / Yosemite / Patagonia | 还差 `<名称>-bg.imageset` 与描述文案 |
| 只有背景图 | Vivid / H-Master | 还差 `.cube` 数据集 |

步骤：补文案 → 补缺的资源 → 在对应分组的数组里加 `FilterSpec` → 跑自检。

---

## 6. 硬性约定（踩过的坑）

1. **`name` 是持久化标识**。它是 `builtin:<name>` 的组成部分，用户已保存的选中滤镜、强度、收藏、隐藏状态都按它索引。
   改名 = 用户配置丢失。真要改，需要写一次迁移，自检里的「历史数据残留」就是为这个报警的。
2. **顺序 = 目录里数组的顺序**，不是字母序，也不是注册顺序。想调展示顺序，挪数组元素即可。
3. **LUT 数据集名必须等于滤镜名**，`-bg` 后缀是卡片图的硬编码约定。
4. **不要直接在 `BuiltinFilterRegistry` 里调 `register(name:info:)`**，它现在只由目录驱动；
   绕过目录会让自检的第 1 项（注册表与目录一致）报错。
5. **不要手改 `Yoyo/Generated/String+Localized.swift`**，它由脚本生成（见 `AGENTS.md`）。
6. **`.cube` 是 3D LUT**，解析在 `FilterManager.loadLutData` / `lutDataForCIColorCube`
   （读 `NSDataAsset`，支持 `.cube` 文本格式并带缓存），输出尺寸不合法时会静默失败。

---

## 7. 一次改完的检查清单

- [ ] `BuiltinFilterCatalog.swift` 加了 `FilterSpec`，位置符合期望的展示顺序
- [ ] `en.lproj` / `zh-Hans.lproj` 都加了 `descriptionKey`
- [ ] 跑过 `scripts/generate_localized_strings.py`
- [ ] `<名称>-bg.imageset` 已存在
- [ ] `.lut` 时 `<名称>.dataset`（内含 `<名称>.cube`）已存在
- [ ] `.filmSimulation` 时 `FilterType.swift` 的 `filmSimulationFilters` 已同步
- [ ] `filmPresetID` 是 `FilmPreset.all` 里的有效 id
- [ ] 自检 0 错误 0 警告
- [ ] 真机划一遍：卡片有图 / 有描述 / 有画面变化
