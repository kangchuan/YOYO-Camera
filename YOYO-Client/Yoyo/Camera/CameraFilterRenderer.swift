import CoreImage
import Metal
import UIKit

final class CameraFilterRenderer {
    static let shared = CameraFilterRenderer()

    private let metalDevice: MTLDevice?
    private let ciContext: CIContext
    private var commandQueue: MTLCommandQueue?
    /// Use the Display P3 wide color gamut for preview rendering to fully leverage iPhone display colors
    private let renderColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    private let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()

    // Cached properties
    private var lastDrawableSize: CGSize = .zero
    private var lastImageExtent: CGRect = .zero
    private var cachedTransform: CGAffineTransform?
    /// 上一次预览处理尺寸，仅用于避免重复打印诊断日志
    private var lastPreparedExtent: CGRect = .zero

    private init() {
        metalDevice = MTLCreateSystemDefaultDevice()
        if let device = metalDevice {
            ciContext = CIContext(mtlDevice: device, options: [
                .workingColorSpace: workingColorSpace,
                .outputColorSpace: renderColorSpace,
                .cacheIntermediates: true, // Avoid temporary volatile textures
            ])
            commandQueue = device.makeCommandQueue()
            commandQueue?.label = "com.day1-labs.yoyo.camera.filter.render"
        } else {
            ciContext = CIContext(options: [
                .workingColorSpace: workingColorSpace,
                .outputColorSpace: renderColorSpace,
                .cacheIntermediates: true,
            ])
        }
    }

    @discardableResult
    func renderPreview(to metalLayer: CAMetalLayer, with sourceImage: CIImage) -> MTLCommandBuffer? {
        autoreleasepool {
            guard let commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let drawable = metalLayer.nextDrawable()
            else {
                return nil
            }

            let drawableSize = metalLayer.drawableSize

            // 预览只需要覆盖 Metal Layer 的可见像素：先把源帧裁到目标宽高比、再缩到 drawable 尺寸，
            // 然后才进滤镜链。否则胶片模拟核会在整帧（.photo 预设下可达 10MP 以上）上运行，
            // 单帧渲染耗时远超 1/30s，表现为取景画面掉帧 + 持续发热。
            let previewSource = preparePreviewSource(sourceImage, matching: drawableSize)

            let filteredImage = applyFilter(to: previewSource)
            let destinationTexture = drawable.texture
            let imageExtent = filteredImage.extent

            // Check the cache
            let transform: CGAffineTransform
            if drawableSize == lastDrawableSize, imageExtent == lastImageExtent, let cached = cachedTransform {
                transform = cached
            } else {
                // Recompute
                let scaleX = drawableSize.width / imageExtent.width
                let scaleY = drawableSize.height / imageExtent.height
                let scale = max(scaleX, scaleY)
                let tx = (drawableSize.width - imageExtent.width * scale) / 2 - imageExtent.origin.x * scale
                let ty = (drawableSize.height - imageExtent.height * scale) / 2 - imageExtent.origin.y * scale

                transform = CGAffineTransform(scaleX: scale, y: scale)
                    .concatenating(CGAffineTransform(translationX: tx, y: ty))

                // Update the cache
                lastDrawableSize = drawableSize
                lastImageExtent = imageExtent
                cachedTransform = transform
            }

            let finalImageToRender = filteredImage.transformed(by: transform)

            ciContext.render(
                finalImageToRender,
                to: destinationTexture,
                commandBuffer: commandBuffer,
                bounds: CGRect(origin: .zero, size: drawableSize),
                colorSpace: renderColorSpace
            )

            commandBuffer.present(drawable)
            return commandBuffer
        }
    }

    /// 把预览源帧整理成「屏幕上真正会显示的那部分像素」。
    ///
    /// - 按目标宽高比居中裁剪：与拍照链路 `ImageProcessor.cropImage` 的处理一致，
    ///   这样滤镜的暗角 / 光晕 / 颗粒都以同一画面的尺寸为基准计算，预览与成片观感一致。
    /// - 按 drawable 像素尺寸等比缩小（只缩不放）：CPU/GPU 在多出来的像素上做的全是无用功。
    ///
    /// 该函数只在渲染队列上调用，`lastPreparedExtent` 不需要额外加锁。
    private func preparePreviewSource(_ image: CIImage, matching drawableSize: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.isFinite, !extent.isEmpty, extent.width > 0, extent.height > 0,
              drawableSize.width > 0, drawableSize.height > 0
        else {
            return image
        }

        let targetAspect = drawableSize.width / drawableSize.height
        let sourceAspect = extent.width / extent.height

        // 1. 居中裁剪到目标宽高比
        var cropRect = extent
        if abs(sourceAspect - targetAspect) > 0.01 {
            if sourceAspect > targetAspect {
                // 源图偏宽：裁掉左右，保留居中部分
                let width = (extent.height * targetAspect).rounded(.down)
                cropRect = CGRect(
                    x: extent.origin.x + ((extent.width - width) / 2).rounded(.down),
                    y: extent.origin.y,
                    width: width,
                    height: extent.height
                )
            } else {
                // 源图偏高：裁掉上下
                let height = (extent.width / targetAspect).rounded(.down)
                cropRect = CGRect(
                    x: extent.origin.x,
                    y: extent.origin.y + ((extent.height - height) / 2).rounded(.down),
                    width: extent.width,
                    height: height
                )
            }
        }

        guard cropRect.isFinite, !cropRect.isEmpty,
              cropRect.width > 0, cropRect.height > 0
        else {
            return image
        }

        // 2. 只缩不放，并把原点归一化到 (0, 0)
        let scale = min(1.0, min(drawableSize.width / cropRect.width,
                                 drawableSize.height / cropRect.height))
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(
                translationX: -cropRect.origin.x * scale,
                y: -cropRect.origin.y * scale
            ))

        let prepared = image.cropped(to: cropRect).transformed(by: transform)

        // 仅在尺寸变化时打印一次，便于排查预览渲染耗时问题
        if lastPreparedExtent != prepared.extent {
            lastPreparedExtent = prepared.extent
            debugLog("🖼️ [PreviewRender] 预览处理尺寸: \(Int(prepared.extent.width))×\(Int(prepared.extent.height)) (源 \(Int(extent.width))×\(Int(extent.height)), drawable \(Int(drawableSize.width))×\(Int(drawableSize.height)))")
        }

        return prepared
    }

    func applyFilter(to image: CIImage) -> CIImage {
        // UX-05: thermal tier 3. Under sustained thermal pressure we drop
        // the whole colour-grading chain for the preview. Drawing the
        // untouched frame still costs one blit, but it removes the
        // multi-pass LUT / grain work, which is the dominant GPU cost.
        //
        // Read from `ProcessInfo` directly rather than through
        // `CameraAutomationManager`: this runs on the render queue, and
        // hopping to the main actor (let alone through an ObservableObject)
        // once per frame is both a Swift 6 isolation violation and a
        // pointless per-frame cost. `ProcessInfo` is thread-safe and cheap.
        //
        // Trade-off, deliberate: while the device is hot the viewfinder
        // shows the un-graded frame even though the photo is still written
        // with the user's look. The toast says so explicitly.
        if ProcessInfo.processInfo.thermalState == .serious {
            return image
        }
        return FilterManager.shared.applyFilter(to: image, quality: .preview)
    }
}
