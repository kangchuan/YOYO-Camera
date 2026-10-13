//
//  LutLoader.swift
//  Yoyo
//
//  LUT 资源加载与缓存。从 `FilterManager` 剥离而来（重构 P3）。
//
//  职责边界：
//  - 只做两段转换：`.cube` 资源 -> 原始 Data（含 LUT_3D_SIZE 解析）、
//    以及 `.cube` Data -> `CIColorCube` 所需的 RGBA float Data。
//  - 不持有任何渲染状态，不依赖 `FilterManager`，不触碰滤镜选择/强度逻辑。
//  - 三级缓存由本类自己维护（并发队列 + barrier 写入），生命周期与持有者一致。
//
//  原先这三块缓存和两个加载函数混在 1400 行的渲染管理器里，
//  现在集中到一处：既便于单独替换数据源，也便于补单元测试。
//

import CoreImage
import Foundation
import UIKit // NSDataAsset（.dataset 资源）定义在 UIKit

/// `.cube` LUT 的加载与缓存器。
///
/// 用法：由持有者创建一个实例（如 `FilterManager` 的 `lutLoader`），
/// 生命周期内复用即可 —— 三级缓存都挂在这个实例上。
final class LutLoader {

    // MARK: - Cache

    /// 串行化缓存访问：读走 `sync`，写走 `.barrier`，保证并发读安全。
    private let cacheQueue = DispatchQueue(
        label: "com.day1-labs.yoyo.filter.cache",
        attributes: .concurrent
    )

    /// `lutName -> .cube 原始数据`
    private var lutDataCache: [String: Data] = [:]

    /// `lutName -> LUT_3D_SIZE`
    private var lutSizeCache: [String: Int] = [:]

    /// `lutName -> CIColorCube 用 RGBA 数据`（解析成本高，必须缓存）
    private var cubeDataCache: [String: Data] = [:]

    // MARK: - Public API

    /// 按名称加载 LUT 原始数据与其维度。
    ///
    /// 查找顺序：`Assets.xcassets` 里的 `<lutName>.dataset`，失败后回退到 bundle 中的
    /// `<lutName>.cube` 文件。维度取自 `.cube` 头部的 `LUT_3D_SIZE`，缺省 33。
    ///
    /// - Parameter lutName: 数据集名 / 文件名（不带扩展名）
    /// - Returns: `(.cube 内容, 维度)`；资源缺失时返回 `(nil, 0)`
    func loadLutData(lutName: String) -> (Data?, Int) {
        // 1. 先尝试命中缓存（读锁）
        var cachedData: Data?
        var cachedSize: Int?

        cacheQueue.sync {
            cachedData = lutDataCache[lutName]
            cachedSize = lutSizeCache[lutName]
        }

        if let data = cachedData, let size = cachedSize {
            return (data, size)
        }

        // 2. 未命中则真正加载（可能耗时，期间不持锁）
        var loadedData: Data?
        var loadedSize = 33

        // 优先取 .dataset 里的 .cube 文件
        if let asset = NSDataAsset(name: lutName, bundle: Bundle.main) {
            loadedData = asset.data
            loadedSize = Self.parseCubeSize(from: asset.data) ?? 33
        } else if let url = Bundle.main.url(forResource: lutName, withExtension: "cube"),
                  let data = try? Data(contentsOf: url)
        {
            loadedData = data
            loadedSize = Self.parseCubeSize(from: data) ?? 33
        }

        guard let data = loadedData else {
            print("LUT asset not found for name: \(lutName)")
            return (nil, 0)
        }

        // 3. 回写缓存（写锁）
        cacheQueue.async(flags: .barrier) {
            self.lutDataCache[lutName] = data
            self.lutSizeCache[lutName] = loadedSize
        }

        return (data, loadedSize)
    }

    /// 把 `.cube` 原始数据转换成 `CIColorCube` 需要的 RGBA float 数据。
    ///
    /// `.cube` 每行是 `R G B` 三个分量；`CIColorCube` 要求每像素 RGBA 四分量，
    /// 因此这里按三补一（alpha 恒为 1.0）重排。
    ///
    /// - Parameters:
    ///   - cubeData: `.cube` 文件内容
    ///   - size: `LUT_3D_SIZE`，用于校验分量总数
    ///   - lutName: 传入则启用/回写缓存；传 nil 则每次都重新解析
    /// - Returns: RGBA float Data；解析失败或分量数不符时返回 nil
    func lutDataForCIColorCube(from cubeData: Data, size: Int, lutName: String? = nil) -> Data? {
        // 先查缓存
        if let name = lutName {
            var cached: Data?
            cacheQueue.sync {
                cached = cubeDataCache[name]
            }
            if let cached {
                return cached
            }
        }

        guard let cubeString = String(data: cubeData, encoding: .utf8) else {
            return nil
        }

        var cubeValues: [Float] = []
        for line in cubeString.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty
                || trimmed.hasPrefix("#")
                || trimmed.hasPrefix("TITLE")
                || trimmed.hasPrefix("LUT_3D_SIZE")
                || trimmed.hasPrefix("DOMAIN_MIN")
                || trimmed.hasPrefix("DOMAIN_MAX")
            {
                continue
            }
            let parts = trimmed.split(separator: " ").compactMap { Float($0) }
            if parts.count == 3 {
                cubeValues.append(contentsOf: parts)
            }
        }

        let expectedCount = size * size * size * 3
        guard cubeValues.count == expectedCount else {
            print("LUT data count mismatch: got \(cubeValues.count), expected \(expectedCount)")
            return nil
        }

        var rgba: [Float] = []
        rgba.reserveCapacity(cubeValues.count / 3 * 4)
        for i in stride(from: 0, to: cubeValues.count, by: 3) {
            rgba.append(cubeValues[i])
            rgba.append(cubeValues[i + 1])
            rgba.append(cubeValues[i + 2])
            rgba.append(1.0)
        }
        let result = Data(buffer: UnsafeBufferPointer(start: &rgba, count: rgba.count))

        // 回写缓存
        if let name = lutName {
            cacheQueue.async(flags: .barrier) {
                self.cubeDataCache[name] = result
            }
        }
        return result
    }

    // MARK: - Helpers

    /// 从 `.cube` 头部解析 `LUT_3D_SIZE`。
    private static func parseCubeSize(from data: Data) -> Int? {
        guard let cubeString = String(data: data, encoding: .utf8) else { return nil }
        guard let sizeLine = cubeString
            .components(separatedBy: .newlines)
            .first(where: { $0.contains("LUT_3D_SIZE") })
        else { return nil }
        let comps = sizeLine.components(separatedBy: .whitespaces).compactMap { Int($0) }
        return comps.last
    }
}
