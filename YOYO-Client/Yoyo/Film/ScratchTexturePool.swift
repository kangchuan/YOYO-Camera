import CoreImage
import Foundation
import Metal

/// A-12: a recycling pool for the scratch textures the film passes allocate.
///
/// `FilmComputeEngine` used to ask Metal for a fresh `MTLTexture` on every
/// call — thirteen per pass, two passes per preview frame — and then throw
/// them away. Allocating GPU memory that often is the expensive part; the
/// shading itself is not. The sizes are fixed fractions of the frame
/// (1/2, 1/4, 1/8, 1/16, plus full size), so a handful of buckets serves
/// every frame and reuse hits almost every time.
///
/// ## Why reuse is safe here, and what would break it
///
/// Every scratch texture's last use is inside the single command buffer that
/// the pass commits and then **waits** on before returning. Once that wait is
/// done the GPU is finished with all of them, so handing them back is safe.
///
/// **If you ever remove the `waitUntilCompleted()` in FilmComputeEngine, this
/// pool becomes a use-after-free.** Making the passes asynchronous requires an
/// explicit dependency (an `MTLEvent`, or completion handlers the consumer
/// respects) *before* pooling can stay.
///
/// Only `.private` scratch textures belong in here. The pass's result texture
/// is `.shared` and escapes through the returned `CIImage`, so it must stay a
/// fresh allocation every time — recycling it would corrupt a value the caller
/// still owns.
final class ScratchTexturePool {
    private struct Key: Hashable {
        let width: Int
        let height: Int
    }

    /// Caps on recycled textures. Rotating the device changes the preview size,
    /// which adds new buckets; without a ceiling those would accumulate for the
    /// lifetime of the process.
    private static let maxPerBucket = 16
    private static let maxTotal = 96

    private var buckets: [Key: [MTLTexture]] = [:]
    private var totalPooled = 0
    private var createdCount = 0
    private let lock = NSLock()

    /// How many textures this pool has actually created. Tests assert that this
    /// stops growing once the pool is warm — the whole point of the pool.
    var createdTextures: Int {
        lock.lock()
        defer { lock.unlock() }
        return createdCount
    }

    /// How many textures are currently sitting in the pool, ready to reuse.
    var pooledTextures: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalPooled
    }

    /// Returns a texture of the requested size, reusing a pooled one when
    /// possible. The caller owns it until it passes it back.
    func borrow(width: Int, height: Int, device: MTLDevice) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let key = Key(width: width, height: height)

        lock.lock()
        if var bucket = buckets[key], let reused = bucket.popLast() {
            buckets[key] = bucket
            totalPooled -= 1
            lock.unlock()
            return reused
        }
        createdCount += 1
        lock.unlock()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    /// Hands textures back. Safe to call with textures from a pass that ended
    /// early (never committed, so the GPU never touched them).
    func recycle(_ textures: [MTLTexture]) {
        guard !textures.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        for texture in textures where texture.width > 0 && texture.height > 0 {
            let key = Key(width: texture.width, height: texture.height)
            var bucket = buckets[key, default: []]
            guard bucket.count < Self.maxPerBucket, totalPooled < Self.maxTotal else { continue }
            bucket.append(texture)
            buckets[key] = bucket
            totalPooled += 1
        }
    }

    /// Drops everything. Only used by tests that want a cold pool.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        buckets.removeAll()
        totalPooled = 0
    }
}

/// One pass's worth of borrowed textures.
///
/// Recycling happens in `deinit`, which means every early `return nil` in the
/// middle of a pass gives its textures back too — no path can leak them by
/// forgetting.
final class ScratchFrame {
    private let pool: ScratchTexturePool
    private let device: MTLDevice
    private let ciContext: CIContext
    private let colorSpace: CGColorSpace
    private var borrowed: [MTLTexture] = []

    init(pool: ScratchTexturePool, device: MTLDevice, ciContext: CIContext, colorSpace: CGColorSpace) {
        self.pool = pool
        self.device = device
        self.ciContext = ciContext
        self.colorSpace = colorSpace
    }

    deinit {
        pool.recycle(borrowed)
    }

    func texture(width: Int, height: Int) -> MTLTexture? {
        guard let texture = pool.borrow(width: width, height: height, device: device) else { return nil }
        borrowed.append(texture)
        return texture
    }

    /// Renders an image into a borrowed texture. The render is synchronous (no
    /// command buffer), so the texture is safe to hand straight to the GPU.
    func texture(from image: CIImage) -> MTLTexture? {
        let extent = image.extent
        guard let texture = texture(width: Int(extent.width), height: Int(extent.height)) else { return nil }
        ciContext.render(image, to: texture, commandBuffer: nil, bounds: extent, colorSpace: colorSpace)
        return texture
    }
}