import CoreImage
import Metal
import Testing
@testable import Yoyo

/// A-12: the film passes are pure `CIImage` in, `CIImage` out, so they can be
/// verified without a camera and without anyone looking at a screen.
///
/// That matters here: the simulator has no camera, so "the preview still looks
/// right" is not something this machine can answer. Pixel assertions can.
///
/// What these tests protect:
/// - The pooled implementation produces the same image as an unwarmed one, i.e.
///   recycling did not hand back a texture that something else was still using.
/// - Once warm, passes stop allocating — the entire point of the pool.
/// - The result texture, whose contents escape to the caller, is never recycled
///   and stays valid after the next pass has run.
@Suite(.serialized)
@MainActor
struct FilmComputeEngineTests {
    /// Whether the compute kernels are actually reachable from this host.
    ///
    /// In the simulator's unit-test host the app's `default.metallib` is *not*
    /// visible to `MTLCreateSystemDefaultDevice().makeDefaultLibrary()` (nor
    /// via an explicit load from `Bundle.main`), so the passes return nil.
    /// Rather than failing — which would be a false alarm about the code under
    /// test — the pixel tests below are **skipped** in that case, and the pool
    /// accounting lives in `ScratchTexturePoolTests`, which needs no kernels and
    /// therefore always runs.
    ///
    /// Run these on a real device (or a host that can see the metallib) to get
    /// the pixel-equivalence guarantee.
    nonisolated private static var kernelsAvailable: Bool {
        FilmComputeEngine.shared?.isAvailable == true
    }

    // MARK: - Fixtures

    /// A deterministic, high-contrast pattern: gradients catch clamping bugs,
    /// isolated bright spots exercise the highlight threshold.
    private func makeTestImage(width: Int, height: Int, seed: Int = 0) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8((x * 3 + seed * 17) % 256)
                bytes[offset + 1] = UInt8((y * 5 + seed * 31) % 256)
                bytes[offset + 2] = UInt8(((x + y) * 2 + seed * 7) % 256)
                bytes[offset + 3] = 255
            }
        }

        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            Issue.record("could not build the test image")
            return CIImage(color: .gray)
        }
        return CIImage(cgImage: cgImage)
    }

    private func pixels(of image: CIImage, width: Int, height: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return buffer }
        let context = CIContext(options: [.workingColorSpace: colorSpace])
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(
                image,
                toBitmap: base,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return buffer
    }

    private func firstDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int? {
        guard lhs.count == rhs.count else { return nil }
        for (index, pair) in zip(lhs, rhs).enumerated() where pair.0 != pair.1 {
            return index
        }
        return nil
    }

    private func maximumDelta(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        zip(lhs, rhs).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    // MARK: - Output correctness

    @Test(.enabled(if: FilmComputeEngineTests.kernelsAvailable))
    func bloomIsDeterministicAcrossRuns() {
        guard let engine = FilmComputeEngine.shared, engine.isAvailable else { return }
        let input = makeTestImage(width: 128, height: 128)

        let first = engine.generateBloomLayer(from: input, intensity: 0.8, threshold: 0.6, spread: 0.4)
        let second = engine.generateBloomLayer(from: input, intensity: 0.8, threshold: 0.6, spread: 0.4)
        guard let first, let second else {
            Issue.record("bloom pass returned nil")
            return
        }
        let a = pixels(of: first, width: 128, height: 128)
        let b = pixels(of: second, width: 128, height: 128)

        // With a recycled pool, the second run writes into textures the first
        // run used. Any use-after-free shows up here as differing pixels.
        #expect(maximumDelta(a, b) <= 1, "bloom output changed between two identical runs")
    }

    @Test(.enabled(if: FilmComputeEngineTests.kernelsAvailable))
    func halationIsDeterministicAcrossRuns() {
        guard let engine = FilmComputeEngine.shared, engine.isAvailable else { return }
        let input = makeTestImage(width: 128, height: 128, seed: 3)

        let first = engine.generateHalationLayer(from: input, intensity: 0.9, threshold: 0.5, spread: 0.6, warmth: 0.5)
        let second = engine.generateHalationLayer(from: input, intensity: 0.9, threshold: 0.5, spread: 0.6, warmth: 0.5)
        guard let first, let second else {
            Issue.record("bloom pass returned nil")
            return
        }
        let a = pixels(of: first, width: 128, height: 128)
        let b = pixels(of: second, width: 128, height: 128)

        #expect(maximumDelta(a, b) <= 1, "halation output changed between two identical runs")
    }

    @Test(.enabled(if: FilmComputeEngineTests.kernelsAvailable))
    func resultFromAPreviousPassSurvivesTheNextOne() {
        guard let engine = FilmComputeEngine.shared, engine.isAvailable else { return }
        let inputA = makeTestImage(width: 128, height: 128, seed: 1)
        let inputB = makeTestImage(width: 128, height: 128, seed: 9)

        guard let resultA = engine.generateBloomLayer(from: inputA, intensity: 0.7, threshold: 0.5, spread: 0.3) else {
            Issue.record("bloom pass returned nil")
            return
        }
        let snapshot = pixels(of: resultA, width: 128, height: 128)

        // A completely different frame runs in between. If the *result* texture
        // (the one that escapes through the returned CIImage) had been recycled
        // into the pool, the snapshot taken above would no longer match.
        _ = engine.generateBloomLayer(from: inputB, intensity: 0.7, threshold: 0.5, spread: 0.3)
        _ = engine.generateHalationLayer(from: inputB, intensity: 0.7, threshold: 0.5, spread: 0.3, warmth: 0.5)

        let after = pixels(of: resultA, width: 128, height: 128)
        #expect(firstDifference(snapshot, after) == nil, "an earlier pass's result was overwritten")
    }

    // MARK: - The pool itself

    @Test(.enabled(if: FilmComputeEngineTests.kernelsAvailable))
    func passesStopAllocatingOnceThePoolIsWarm() {
        guard let engine = FilmComputeEngine.shared, engine.isAvailable else { return }
        let input = makeTestImage(width: 160, height: 120)

        // One pass to fill the buckets for this size...
        _ = engine.generateBloomLayer(from: input, intensity: 0.5, threshold: 0.5, spread: 0.5)
        let afterWarmup = engine.scratchDiagnostics.created

        // ...then several more, which should all hit the pool.
        for _ in 0..<5 {
            _ = engine.generateBloomLayer(from: input, intensity: 0.5, threshold: 0.5, spread: 0.5)
            _ = engine.generateHalationLayer(from: input, intensity: 0.5, threshold: 0.5, spread: 0.5, warmth: 0.5)
        }
        let afterLoops = engine.scratchDiagnostics.created

        #expect(afterLoops == afterWarmup,
                "pool kept allocating: \(afterWarmup) → \(afterLoops)")
        #expect(engine.scratchDiagnostics.pooled > 0, "nothing was parked for reuse")
    }

    @Test(.enabled(if: FilmComputeEngineTests.kernelsAvailable))
    func passesWithDifferentSizesEachGetTheirOwnBucket() {
        guard let engine = FilmComputeEngine.shared, engine.isAvailable else { return }
        _ = engine.generateBloomLayer(from: makeTestImage(width: 128, height: 128), intensity: 0.5, threshold: 0.5, spread: 0.5)
        let afterFirst = engine.scratchDiagnostics.pooled

        // Rotating the device changes the preview size; the new sizes must not
        // steal the old ones' textures.
        _ = engine.generateBloomLayer(from: makeTestImage(width: 96, height: 160), intensity: 0.5, threshold: 0.5, spread: 0.5)
        let afterSecond = engine.scratchDiagnostics.pooled

        #expect(afterSecond > afterFirst, "second size should have added its own buckets")
    }

    @Test func poolIgnoresDegenerateSizes() {
        // `MTLDevice` is a protocol, so there is no dummy to pass — but the
        // guard runs before the device is touched, and this pins that order:
        // a zero or negative size must never reach `makeTexture`.
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let pool = ScratchTexturePool()
        #expect(pool.borrow(width: 0, height: 100, device: device) == nil)
        #expect(pool.borrow(width: 100, height: -1, device: device) == nil)
        #expect(pool.createdTextures == 0, "a rejected size must not count as an allocation")
    }
}
