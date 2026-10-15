import Metal
import Testing
@testable import Yoyo

/// A-12: the recycling pool on its own.
///
/// These tests deliberately do *not* go through `FilmComputeEngine`: the engine
/// needs the app's `.metal` kernels, which a simulator unit-test host cannot
/// see, so anything asserted through it would silently skip. The pool is a
/// separate type precisely so its behaviour can be verified anywhere a Metal
/// device exists.
///
/// The pixel-level proof that a warm pool does not corrupt output lives in
/// `FilmComputeEngineTests` and needs a host with the kernels.
struct ScratchTexturePoolTests {

    /// A device is required to allocate, but no compute pipeline is needed.
    private func makeDevice() -> MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }

    /// `MTLTexture` is a protocol, so it has no `objectID`; go through
    /// AnyObject — every implementation is an Objective-C object.
    private func id(_ texture: MTLTexture) -> ObjectIdentifier {
        ObjectIdentifier(texture as AnyObject)
    }

    @Test func stopsCreatingOnceWarm() {
        guard let device = makeDevice() else { return }
        let pool = ScratchTexturePool()

        // Mimic one film pass: thirteen scratch textures, all the same size.
        for _ in 0..<5 {
            var borrowed: [MTLTexture] = []
            for _ in 0..<13 {
                if let texture = pool.borrow(width: 512, height: 512, device: device) {
                    borrowed.append(texture)
                }
            }
            pool.recycle(borrowed)
        }

        #expect(pool.createdTextures == 13, "should create the first pass's textures and no more")
        #expect(pool.pooledTextures == 13)
    }

    @Test func handsBackTheSameTextureItGaveOut() {
        guard let device = makeDevice() else { return }
        let pool = ScratchTexturePool()

        let first = pool.borrow(width: 256, height: 128, device: device)
        let second = pool.borrow(width: 256, height: 128, device: device)
        let firstID = first.map(id) ?? ObjectIdentifier(NSObject())
        let secondID = second.map(id) ?? ObjectIdentifier(NSObject())
        #expect(firstID != secondID, "two live borrows must not share one texture")

        pool.recycle([first!])
        let reused = pool.borrow(width: 256, height: 128, device: device)
        #expect(reused.map(id) == firstID, "expected the recycled texture back")
        // Keep the second borrow alive for the duration of the test.
        withExtendedLifetime(second) {}
    }

    @Test func keepsDifferentSizesApart() {
        guard let device = makeDevice() else { return }
        let pool = ScratchTexturePool()

        let square = pool.borrow(width: 512, height: 512, device: device)
        let wide = pool.borrow(width: 512, height: 256, device: device)
        // Both go back: the point of the buckets is that a later borrow of one
        // size must find its own texture, not the other size's.
        pool.recycle([square!, wide!])

        let nextSquare = pool.borrow(width: 512, height: 512, device: device)
        let nextWide = pool.borrow(width: 512, height: 256, device: device)

        #expect(nextSquare.map(id) == square.map(id))
        #expect(nextWide.map(id) == wide.map(id))
        #expect(nextWide.map(id) != nextSquare.map(id))
        #expect(pool.createdTextures == 2, "two sizes, two textures — no re-allocation")
    }

    @Test func doesNotInventAReuseForAnUnrecycledTexture() {
        // A texture that was borrowed and never handed back is simply gone: the
        // next borrow of that size must allocate rather than pretend.
        guard let device = makeDevice() else { return }
        let pool = ScratchTexturePool()

        let borrowed = pool.borrow(width: 256, height: 256, device: device)
        let next = pool.borrow(width: 256, height: 256, device: device)

        #expect(next.map(id) != borrowed.map(id))
        #expect(pool.createdTextures == 2)
    }

    @Test func poolsTexturesWhileAnyAreStillBorrowed() {
        // Two passes running at once (the render thread and a thumbnail job)
        // must never be handed the same texture.
        guard let device = makeDevice() else { return }
        let pool = ScratchTexturePool()

        var firstPass: [MTLTexture] = []
        var secondPass: [MTLTexture] = []
        for _ in 0..<6 {
            if let t = pool.borrow(width: 128, height: 128, device: device) { firstPass.append(t) }
            if let t = pool.borrow(width: 128, height: 128, device: device) { secondPass.append(t) }
        }

        let firstIDs = Set(firstPass.map(id))
        let secondIDs = Set(secondPass.map(id))
        #expect(firstIDs.isDisjoint(with: secondIDs), "live borrows overlapped")
        #expect(firstPass.count == 6 && secondPass.count == 6)
    }

    @Test func poolIgnoresDegenerateSizes() {
        // `MTLDevice` is a protocol, so there is no dummy to hand — the guard
        // runs before the device is touched, and this pins that ordering: a
        // zero or negative size must never reach `makeTexture`.
        guard let device = makeDevice() else { return }
        let pool = ScratchTexturePool()
        #expect(pool.borrow(width: 0, height: 100, device: device) == nil)
        #expect(pool.borrow(width: 100, height: -1, device: device) == nil)
        #expect(pool.createdTextures == 0, "a rejected size must not count as an allocation")
    }

    @Test func recyclingNothingIsHarmless() {
        let pool = ScratchTexturePool()
        pool.recycle([])
        #expect(pool.pooledTextures == 0)
    }
}