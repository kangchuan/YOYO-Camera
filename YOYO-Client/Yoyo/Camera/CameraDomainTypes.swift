import AVFoundation
import CoreGraphics
import Foundation

/// A-09: pure camera domain vocabulary — ISO / shutter presets / aspect ratio /
/// resolution / file naming / audio pattern and so on.
///
/// These used to be nested inside `CameraSettingsState`, which quietly made
/// the state manager the home of basic types: any module that needed
/// `AspectRatioPreset` had to depend on the whole Settings layer, while that
/// layer reached back into Device — the cycle described in A-10.
///
/// The rule for this file: it must stay pure. No managers, no singletons, no
/// UI, no dependency on anything else in the app. That is what makes it safe
/// for every layer to import.
enum CameraDomainTypes {
        // MARK: - Composition guide line type
        enum GuidelinesType: String, CaseIterable {
            case off // Turn off auxiliary lines
            case ruleOfThirds // Rule of thirds
            case ruleOfThirdsWithDiagonal // 3x3 + diagonal
            case goldenRatio // Golden ratio
            case grid6x4 // 6x4 grid

            var systemIcon: String {
                switch self {
                case .off: return "nosign"
                case .ruleOfThirds: return "rectangle.split.3x3"
                case .ruleOfThirdsWithDiagonal: return "grid.circle"
                case .goldenRatio: return "rectangle.split.3x1"
                case .grid6x4: return "grid"
                }
            }
        }

        // MARK: - ISO/Shutter presets
        enum ISOPreset: String, CaseIterable {
            case lowNoise // Low noise priority (ISO <= 800)
            case balanced // Balanced (ISO <= 1600)
            case highISO // High ISO (ISO <= 3200)
            case extreme // Limit (ISO <= 6400)

            var displayName: String {
                switch self {
                case .lowNoise: return String.isoPresetLowNoise.localized
                case .balanced: return String.isoPresetBalanced.localized
                case .highISO: return String.isoPresetHigh.localized
                case .extreme: return String.isoPresetExtreme.localized
                }
            }

            var description: String {
                switch self {
                case .lowNoise: return String.isoPresetLowNoiseDesc.localized
                case .balanced: return String.isoPresetBalancedDesc.localized
                case .highISO: return String.isoPresetHighDesc.localized
                case .extreme: return String.isoPresetExtremeDesc.localized
                }
            }

            var maxISO: Double {
                switch self {
                case .lowNoise: return 800.0
                case .balanced: return 1600.0
                case .highISO: return 3200.0
                case .extreme: return 6400.0
                }
            }
        }

        enum ShutterSpeedPreset: String, CaseIterable {
            case handheld // Handheld shooting (>= 1/60s)
            case stable // Stable support (>= 1/30s)
            case tripod // Tripod (>= 1/15s)
            case longExposure // Long exposure (>= 1/4s)

            var displayName: String {
                switch self {
                case .handheld: return String.shutterPresetHandheld.localized
                case .stable: return String.shutterPresetStable.localized
                case .tripod: return String.shutterPresetTripod.localized
                case .longExposure: return String.shutterPresetLongExposure.localized
                }
            }

            var description: String {
                switch self {
                case .handheld: return String.shutterPresetHandheldDesc.localized
                case .stable: return String.shutterPresetStableDesc.localized
                case .tripod: return String.shutterPresetTripodDesc.localized
                case .longExposure: return String.shutterPresetLongExposureDesc.localized
                }
            }

            var minShutterSpeed: Double {
                switch self {
                case .handheld: return 1.0 / 60.0
                case .stable: return 1.0 / 30.0
                case .tripod: return 1.0 / 15.0
                case .longExposure: return 1.0 / 4.0
                }
            }
        }

        // MARK: - Countdown options
        enum TimerSeconds: Int, CaseIterable {
            case five = 5
            case ten = 10
            case thirty = 30

            var displayName: String {
                switch self {
                case .five: return "5s"
                case .ten: return "10s"
                case .thirty: return "30s"
                }
            }
        }

        // MARK: - Aspect Ratio Preset
        enum AspectRatioPreset: Double, CaseIterable {
            case square = 1.0
            case portrait = 0.8 // 4:5
            case traditional = 0.75 // 3:4
            case photo = 0.6667 // 2:3
            case story = 0.5625 // 9:16

            var displayName: String {
                switch self {
                case .square: return "1:1"
                case .portrait: return "4:5"
                case .traditional: return "3:4"
                case .photo: return "2:3"
                case .story: return "9:16"
                }
            }
        }

        // MARK: - Shooting format options
        enum CaptureQuality: String, CaseIterable {
            case standard // Processed
            case proRaw // Apple ProRaw

            var isRaw: Bool {
                self == .proRaw
            }
        }

        enum ImageFileFormat: String, CaseIterable {
            case jpeg // Standard JPEG format
            case heic // HEIC format
        }

        // MARK: - Video resolution enumeration
        enum VideoResolution: String, CaseIterable {
            case hd720 = "720p" // 720p HD (1280x720)
            case hd1080 = "HD" // 1080p Full HD (1920x1080)
            case hd4k = "4K" // 4K UHD (3840x2160)

            var displayName: String {
                switch self {
                case .hd720: return "720p"
                case .hd1080: return "HD"
                case .hd4k: return "4K"
                }
            }

            var dimensions: CGSize {
                switch self {
                case .hd720: return CGSize(width: 1280, height: 720)
                case .hd1080: return CGSize(width: 1920, height: 1080)
                case .hd4k: return CGSize(width: 3840, height: 2160)
                }
            }

            var pixelCount: Int {
                Int(dimensions.width * dimensions.height)
            }
        }

        // MARK: - Video frame rate enumeration
        enum VideoFrameRate: String, CaseIterable {
            case fps24 = "24" // 24 fps
            case fps30 = "30" // 30 fps
            case fps60 = "60" // 60 fps
            case fps120 = "120" // 120 fps

            var displayName: String {
                switch self {
                case .fps24: return "24"
                case .fps30: return "30"
                case .fps60: return "60"
                case .fps120: return "120"
                }
            }

            var value: Double {
                switch self {
                case .fps24: return 24.0
                case .fps30: return 30.0
                case .fps60: return 60.0
                case .fps120: return 120.0
                }
            }
        }

        // MARK: - File naming format enum
        enum FileNamingFormat: String, CaseIterable {
            case standard // 20241029_143022
            case classic // 出片相机_0001
            case daily // 20241029_0001
            case pro // Photo_20241029_143022
            case custom // Custom format

            var displayName: String {
                switch self {
                case .standard: return .fileNamingStandard.localized
                case .classic: return .fileNamingClassic.localized
                case .daily: return .fileNamingDaily.localized
                case .pro: return .fileNamingPro.localized
                case .custom: return .fileNamingCustom.localized
                }
            }

            var description: String {
                switch self {
                case .standard: return "20241029_143022"
                case .classic: return "Photo_0001"
                case .daily: return "20241029_0001"
                case .pro: return "Photo_20241029_143022"
                case .custom: return .fileNamingCustomDesc.localized
                }
            }

            var template: String {
                switch self {
                case .standard: return "{year}{month}{day}_{hour}{minute}{second}"
                case .classic: return "{type}_{index}"
                case .daily: return "{year}{month}{day}_{index}"
                case .pro: return "{type}_{year}{month}{day}_{hour}{minute}{second}"
                case .custom: return "" // Use custom format
                }
            }
        }

        // MARK: - Video save format enumeration
        enum VideoSaveFormat: String, CaseIterable {
            case mov // MOV format
            case mp4 // MP4 format

            var displayName: String {
                switch self {
                case .mov: return "MOV"
                case .mp4: return "MP4"
                }
            }

            var fileType: AVFileType {
                switch self {
                case .mov: return .mov
                case .mp4: return .mp4
                }
            }
        }

        // MARK: - Audio radio mode enumeration
        enum AudioPickupPattern: String, CaseIterable {
            case ambient // Environment (omnidirectional)
            case voice // Vocal (cardioid pointing)
            case voiceEnhanced // Vocal enhancement (subcardioid pattern)

            var displayName: String {
                switch self {
                case .ambient: return .audioPickupAmbient.localized
                case .voice: return .audioPickupVoice.localized
                case .voiceEnhanced: return .audioPickupVoiceEnhanced.localized
                }
            }

            var description: String {
                switch self {
                case .ambient: return .audioPickupAmbientDesc.localized
                case .voice: return .audioPickupVoiceDesc.localized
                case .voiceEnhanced: return .audioPickupVoiceEnhancedDesc.localized
                }
            }

            var polarPattern: AVAudioSession.PolarPattern {
                switch self {
                case .ambient: return .omnidirectional
                case .voice: return .cardioid
                case .voiceEnhanced: return .subcardioid
                }
            }

            var systemIcon: String {
                switch self {
                case .ambient: return "dot.radiowaves.left.and.right"
                case .voice: return "person.wave.2"
                case .voiceEnhanced: return "waveform.and.person.filled"
                }
            }
        }
}
