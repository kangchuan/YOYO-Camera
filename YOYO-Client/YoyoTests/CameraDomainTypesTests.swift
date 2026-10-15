import CoreGraphics
import Testing
@testable import Yoyo

/// A-11: locks down the domain vocabulary that A-09 moved out of
/// `CameraSettingsState`.
///
/// A move like that is exactly the kind of change that compiles, passes QA and
/// still quietly breaks something: a raw value that feeds a file naming
/// template, a pixel count that decides the resolution menu, a display name
/// that a user reads. These are cheap tests over pure data, and they are the
/// reason the extraction could be done without touching a single call site.
struct CameraDomainTypesTests {

    // MARK: - Aspect ratio

    @Test func aspectRatioRawValuesMatchTheirNames() {
        // The raw value is what gets written to UserDefaults and what the
        // camera layer compares against, so it must stay exactly these values.
        #expect(CameraDomainTypes.AspectRatioPreset.square.rawValue == 1.0)
        #expect(CameraDomainTypes.AspectRatioPreset.portrait.rawValue == 0.8)
        #expect(CameraDomainTypes.AspectRatioPreset.traditional.rawValue == 0.75)
        #expect(abs(CameraDomainTypes.AspectRatioPreset.photo.rawValue - 0.6667) < 0.001)
        #expect(CameraDomainTypes.AspectRatioPreset.story.rawValue == 0.5625)
    }

    @Test func aspectRatioDisplayNamesAreRatioLabels() {
        #expect(CameraDomainTypes.AspectRatioPreset.allCases.allSatisfy { !$0.displayName.isEmpty })
        #expect(CameraDomainTypes.AspectRatioPreset.story.displayName == "9:16")
        #expect(CameraDomainTypes.AspectRatioPreset.square.displayName == "1:1")
    }

    // MARK: - ISO / shutter presets

    @Test func isoPresetThresholdsAreAscending() {
        // `maxISO` is what the auto-exposure logic clamps against. If the order
        // ever breaks, the "cleanest" preset could be noisier than "extreme".
        let thresholds = CameraDomainTypes.ISOPreset.allCases.map(\.maxISO)
        #expect(thresholds == thresholds.sorted())
        #expect(thresholds.count == 4)
    }

    @Test func isoPresetAlwaysHasBothStrings() {
        for preset in CameraDomainTypes.ISOPreset.allCases {
            #expect(!preset.displayName.isEmpty)
            #expect(!preset.description.isEmpty)
        }
    }

    @Test func shutterPresetMinimumSpeedsAscend() {
        // The preset is a *minimum* shutter speed, so handheld is the fastest
        // (smallest 1/N) and long exposure the slowest. If this order ever
        // breaks, "handheld" would quietly require a tripod.
        let speeds = CameraDomainTypes.ShutterSpeedPreset.allCases.map(\.minShutterSpeed)
        #expect(speeds == speeds.sorted())
        #expect(CameraDomainTypes.ShutterSpeedPreset.handheld.minShutterSpeed == 1.0 / 60.0)
        #expect(CameraDomainTypes.ShutterSpeedPreset.longExposure.minShutterSpeed == 1.0 / 4.0)
        #expect(CameraDomainTypes.ShutterSpeedPreset.handheld.minShutterSpeed
                < CameraDomainTypes.ShutterSpeedPreset.longExposure.minShutterSpeed)
    }

    // MARK: - Video

    @Test func videoResolutionsHavePixelOrderedDimensions() {
        let resolutions = CameraDomainTypes.VideoResolution.allCases
        let counts = resolutions.map(\.pixelCount)
        #expect(counts == counts.sorted())
        #expect(CameraDomainTypes.VideoResolution.hd720.dimensions == CGSize(width: 1280, height: 720))
        #expect(CameraDomainTypes.VideoResolution.hd4k.pixelCount == 3840 * 2160)
    }

    @Test func videoResolutionRawValuesAreStableIdentifiers() {
        // These strings are persisted in @AppStorage, so changing one silently
        // resets a user's video quality choice.
        #expect(CameraDomainTypes.VideoResolution.hd720.rawValue == "720p")
        #expect(CameraDomainTypes.VideoResolution.hd1080.rawValue == "HD")
        #expect(CameraDomainTypes.VideoResolution.hd4k.rawValue == "4K")
    }

    @Test func frameRateValuesMatchTheirCases() {
        for rate in CameraDomainTypes.VideoFrameRate.allCases {
            let expected = Double(rate.rawValue)
            #expect(rate.value == expected)
            #expect(rate.displayName == rate.rawValue)
        }
    }

    // MARK: - File naming

    @Test func fileNamingTemplatesOnlyUseKnownVariables() {
        // A typo in a template is invisible until a photo lands in the library
        // with a literal "{yearm}" in its name. This checks every shipped
        // template against the variables `FileNameGenerator` actually fills.
        let known: Set<String> = [
            "{prefix}", "{timestamp}", "{date}", "{time}",
            "{year}", "{month}", "{day}", "{hour}", "{minute}", "{second}",
            "{type}", "{format}", "{uuid}", "{index}",
        ]
        for format in CameraDomainTypes.FileNamingFormat.allCases {
            #expect(!format.displayName.isEmpty)
            guard !format.template.isEmpty else { continue }   // custom = user typed
            var remainder = format.template
            for variable in known {
                remainder = remainder.replacingOccurrences(of: variable, with: "")
            }
            #expect(!remainder.contains("{"), "\(format) uses a variable the generator does not fill → \(remainder)")
        }
        #expect(CameraDomainTypes.FileNamingFormat.classic.template == "{type}_{index}")
        #expect(CameraDomainTypes.FileNamingFormat.daily.template == "{year}{month}{day}_{index}")
    }

    @Test func customFileNamingHasNoPresetTemplate() {
        // Custom means "the user typed it" — a non-empty template here would
        // silently override their setting.
        #expect(CameraDomainTypes.FileNamingFormat.custom.template.isEmpty)
    }

    // MARK: - Misc

    @Test func timerSecondsMapToTheirValues() {
        #expect(CameraDomainTypes.TimerSeconds.five.rawValue == 5)
        #expect(CameraDomainTypes.TimerSeconds.ten.rawValue == 10)
        #expect(CameraDomainTypes.TimerSeconds.thirty.rawValue == 30)
        #expect(CameraDomainTypes.TimerSeconds.allCases.map(\.displayName) == ["5s", "10s", "30s"])
    }

    @Test func captureQualityReportsWhetherItIsRaw() {
        #expect(CameraDomainTypes.CaptureQuality.proRaw.isRaw)
        #expect(!CameraDomainTypes.CaptureQuality.standard.isRaw)
    }

    @Test func everyGuidelineHasAnIcon() {
        // A guideline with no icon renders as an invisible, unselectable cell.
        for guideline in CameraDomainTypes.GuidelinesType.allCases {
            #expect(!guideline.systemIcon.isEmpty)
        }
    }

    @Test func audioPatternsAreDistinct() {
        let patterns = Set(CameraDomainTypes.AudioPickupPattern.allCases.map(\.polarPattern))
        #expect(patterns.count == CameraDomainTypes.AudioPickupPattern.allCases.count)
        for pattern in CameraDomainTypes.AudioPickupPattern.allCases {
            #expect(!pattern.displayName.isEmpty)
            #expect(!pattern.systemIcon.isEmpty)
        }
    }
}