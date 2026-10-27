//
//  StorageBootstrap.swift
//  Yoyo
//
//  SwiftData 容器的建立与降级。
//
//  背景：原来 `YoyoApp` 里直接
//
//      do { return try ModelContainer(...) }
//      catch { fatalError("Could not create ModelContainer: \(error)") }
//
//  `ModelContainer(for:)` 会在磁盘满、store 文件损坏、schema 迁移失败时抛错，
//  而这个 App 把相册索引（`PhotoAsset`）存在 SwiftData 里。于是「更新后点开就
//  闪退，只能重装」——重装同时意味着索引全丢。对一个相机 App，这等于用户以为
//  照片没了。
//
//  这里的取舍：相册索引是**可以从系统相册重建的缓存**（真正的照片在
//  `PHPhotoLibrary` 里），所以打不开时不值得崩。降级到内存库后：
//    - 拍摄、滤镜、保存到系统相册全部照常，不受影响；
//    - 应用内索引不落盘，本次运行期间相册页是空的（系统相册里照片都在）；
//    - 下次启动会重新尝试磁盘库，磁盘问题解决了就自动恢复。
//
//  不做的两件事：
//    1. 不删除坏掉的 store。删了就是真丢索引，而且用户可能只是磁盘暂时满。
//    2. 不加 `VersionedSchema`。现在只有一个 `@Model`，版本化迁移属于过度设计，
//       等真的要改 schema 时再补。
//

import Foundation
import SwiftData

/// 启动时 SwiftData 容器的建立结果。
struct StorageBootstrap {

    /// 降级原因。
    ///
    /// 现在只有一种，留成 enum 是为了将来区分「磁盘满」和「文件损坏」——
    /// 这两种情况该给用户的建议不同（清空间 vs 重启/重装）。
    enum DegradeReason: Equatable {
        /// 磁盘上的 store 无法打开（损坏 / 磁盘满 / 迁移失败）
        case storeUnreadable(message: String)
    }

    /// 实际交给 `.modelContainer(_:)` 的容器
    let container: ModelContainer

    /// 非 nil 表示本次运行使用内存库，索引不会持久化
    let degraded: DegradeReason?

    var isDegraded: Bool { degraded != nil }

    /// 建立容器：优先磁盘库，失败则降级为内存库。
    ///
    /// 只应调用一次（由 `YoyoApp` 的存储属性保证）。每次 SwiftUI body 求值都调
    /// 会重复建库，代价很高。
    static func make() -> StorageBootstrap {
        let schema = Schema([PhotoAsset.self])

        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return StorageBootstrap(container: container, degraded: nil)
        } catch {
            let message = error.localizedDescription
            debugLog("❌ [Storage] 磁盘 store 打开失败，降级为内存库：\(message)")

            do {
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: schema, configurations: [configuration])
                return StorageBootstrap(
                    container: container,
                    degraded: .storeUnreadable(message: message)
                )
            } catch {
                // 连内存库都建不起来，说明 schema/模型定义本身有问题。这是开发者
                // 错误（例如两个同名实体、关系配置成环），带着坏模型继续跑只会把
                // 问题推到更难定位的地方，这里崩比之后崩更清楚。
                fatalError("SwiftData schema is invalid: \(error)")
            }
        }
    }
}
