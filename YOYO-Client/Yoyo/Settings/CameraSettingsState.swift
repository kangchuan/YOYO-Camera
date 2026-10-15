import AVFoundation
import Foundation
import SwiftUI

// MARK: - Camera shooting mode enumeration
enum CameraCaptureMode: String, CaseIterable {
    case photo = "Photo"
    case livePhoto = "LivePhoto"
    case movie = "Movie"
}

// MARK: - Camera settings status manager
@MainActor
final class CameraSettingsState: ObservableObject {
    static let shared = CameraSettingsState()

    @Published var torchEnabled = false

    // MARK: - Persistence settings
    @AppStorage("flashModeRaw") var flashModeRaw = AVCaptureDevice.FlashMode.off.rawValue

    var flashMode: AVCaptureDevice.FlashMode {
        get { AVCaptureDevice.FlashMode(rawValue: flashModeRaw) ?? .off }
        set {
            flashModeRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    @AppStorage("automationEnabled") var automationEnabled = true {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("saveOriginalEnabled") var saveOriginalEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("currentCaptureMode") var captureModeRaw: String = CameraCaptureMode.photo.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("guidelinesType") private var guidelinesTypeRaw: String = GuidelinesType.off.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("histogramEnabled") var histogramEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("hdrEnabled") var hdrEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("saveGPSEnabled") var saveGPSEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("copyrightEnabled") var copyrightEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("copyrightText") var copyrightText = "" {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage(
        "volumeButtonCaptureEnabled"
    ) var volumeButtonCaptureEnabled = false { // Volume button camera switch
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage(
        "timerCaptureEnabled"
    ) var timerCaptureEnabled = false { // Countdown photo switch
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("timerCaptureSeconds") var timerCaptureSeconds = 5 { // Countdown seconds
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("aspectRatio") var aspectRatio: Double = 2.0 / 3.0 {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("previewLatestPhoto") var previewLatestPhoto: Bool = true {
        didSet {
            objectWillChange.send()
        }
    }

    // MARK: - Video settings
    @AppStorage("videoResolution") private var videoResolutionRaw: String = VideoResolution.hd1080.rawValue {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .videoResolutionDidChange, object: nil)
        }
    }

    @AppStorage("videoFrameRate") private var videoFrameRateRaw: String = VideoFrameRate.fps30.rawValue {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .videoFrameRateDidChange, object: nil)
        }
    }

    @AppStorage("videoSaveFormat") private var videoSaveFormatRaw: String = VideoSaveFormat.mov.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("stabilizationEnabled") var stabilizationEnabled = false {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .videoStabilizationDidChange, object: nil)
        }
    }

    // MARK: - Audio settings
    @AppStorage("audioNoiseReductionEnabled") var audioNoiseReductionEnabled = true {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .audioSettingsDidChange, object: nil)
        }
    }

    @AppStorage("audioPickupPattern") private var audioPickupPatternRaw: String = AudioPickupPattern.voice.rawValue {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .audioSettingsDidChange, object: nil)
        }
    }

    // MARK: - File naming format settings
    @AppStorage("fileNamingFormat") private var fileNamingFormatRaw: String = FileNamingFormat.standard.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("customFileNamingFormat") var customFileNamingFormat: String = "{timestamp}_{type}_{uuid}" {
        didSet {
            objectWillChange.send()
        }
    }

    /// UX-06: the default file-name prefix is the user-visible brand, so it has
    /// to follow the display language ("出片相机_0001" / "Snapout_0001").
    /// Only used when the user has never changed it — an existing stored
    /// value always wins, so nobody's existing filenames change.
    @AppStorage("fileNamingPrefix") var fileNamingPrefix: String = String.brandName.localized {
        didSet {
            objectWillChange.send()
        }
    }

    // MARK: - Injected capabilities (A-10)

    /// Location access, handed over by the composition root
    /// (`CameraManagersContainer`).
    ///
    /// A-10: this used to be `PermissionManager.shared`, called inline. That
    /// made Settings depend on the Permission layer while the permission
    /// flow depends on Settings, i.e. a cycle. Settings now states what it
    /// needs; the root decides who provides it. Injecting a stub here is also
    /// what makes the GPS toggle testable without a real permission prompt.
    var locationPermissions: LocationPermissionProviding?

    // MARK: - Runtime state (non-persistent)
    @Published var isCaptureSessionActive = false // Whether the camera capture session is active (replaces the original isPhotoCaptureActive)
    // MARK: - Shooting mode (Published + AppStorage two-way synchronization)
    @Published var currentCaptureMode: CameraCaptureMode = .photo {
        didSet {
            captureModeRaw = currentCaptureMode.rawValue
        }
    }

    // MARK: - initialization
    /// A-11: internal rather than private so tests can build an isolated
    /// instance and exercise the injected-capability path (see
    /// `LocationPermissionToggleTests`). Production code must keep using
    /// `.shared` — a second live instance would be a second `@AppStorage`
    /// view of the same world.
    init() {
        // Load the initial value from AppStorage into the Published property.
        if let mode = CameraCaptureMode(rawValue: captureModeRaw) {
            _currentCaptureMode = Published(initialValue: mode)
        }
    }

    // MARK: - Automation settings
    /// Filter Control
    @AppStorage("AutomationSettings.autoSelectFilter")
    var autoSelectFilter: Bool = true

    /// Focus Control
    @AppStorage("AutomationSettings.autoAdjustFocus")
    var autoAdjustFocus: Bool = true

    /// Exposure Control
    @AppStorage("AutomationSettings.autoAdjustExposure")
    var autoAdjustExposure: Bool = true

    @AppStorage("AutomationSettings.maxExposureBias")
    var maxExposureBias: Double = 10.0

    /// Manual Exposure Control (ISO & Shutter Speed)
    @AppStorage("AutomationSettings.autoAdjustISO")
    var autoAdjustISO: Bool = true

    @AppStorage("AutomationSettings.isoPreset")
    private var isoPresetRaw: String = ISOPreset.balanced.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("AutomationSettings.autoAdjustShutterSpeed")
    var autoAdjustShutterSpeed: Bool = true

    @AppStorage("AutomationSettings.shutterSpeedPreset")
    private var shutterSpeedPresetRaw: String = ShutterSpeedPreset.handheld.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    /// White Balance Control
    @AppStorage("AutomationSettings.autoAdjustWhiteBalance")
    var autoAdjustWhiteBalance: Bool = true

    // MARK: - Domain types (A-09)
    //
    // 这些枚举原本嵌套在 CameraSettingsState 里，让一个「状态管理器」顺带成了
    // 基础类型的宿主：任何模块想用 ISO / 快门 / 宽高比这类相机类型，都得反向依赖
    // Settings（见 CameraDeviceManager、PhotoAlbumManager 对本类的反向引用）。
    //
    // 定义已搬到 CameraDomainTypes（无任何依赖的纯类型文件）；这里的 typealias
    // 保证全项目已有的 `CameraSettingsState.XXX` 引用一行都不用改。
    typealias GuidelinesType = CameraDomainTypes.GuidelinesType
    typealias ISOPreset = CameraDomainTypes.ISOPreset
    typealias ShutterSpeedPreset = CameraDomainTypes.ShutterSpeedPreset
    typealias TimerSeconds = CameraDomainTypes.TimerSeconds
    typealias AspectRatioPreset = CameraDomainTypes.AspectRatioPreset
    typealias CaptureQuality = CameraDomainTypes.CaptureQuality
    typealias ImageFileFormat = CameraDomainTypes.ImageFileFormat
    typealias VideoResolution = CameraDomainTypes.VideoResolution
    typealias VideoFrameRate = CameraDomainTypes.VideoFrameRate
    typealias FileNamingFormat = CameraDomainTypes.FileNamingFormat
    typealias VideoSaveFormat = CameraDomainTypes.VideoSaveFormat
    typealias AudioPickupPattern = CameraDomainTypes.AudioPickupPattern


    // MARK: - Computed properties
    /// Actual effective aspect ratio: video mode is fixed at 9:16, other modes use user settings.
    var effectiveAspectRatio: Double {
        if currentCaptureMode == .movie {
            return AspectRatioPreset.story.rawValue // 9:16
        }
        return aspectRatio
    }

    var currentAspectRatioPreset: AspectRatioPreset {
        AspectRatioPreset.allCases
            .first { abs($0.rawValue - aspectRatio) < 0.001 } ?? .photo
    }

    var currentTimerSeconds: TimerSeconds {
        get { TimerSeconds(rawValue: timerCaptureSeconds) ?? .five }
        set { timerCaptureSeconds = newValue.rawValue }
    }

    var captureQuality: CaptureQuality {
        // RAW capture is temporarily disabled until the related flow is stabilized.
        //
        // A-10: if you are un-commenting this, do NOT call
        // FilterManager / CameraSessionManager / CameraDeviceManager from
        // here. Those calls are exactly the Settings → Device edges that used
        // to form a dependency cycle with the Device layer. Introduce a
        // capability protocol in CameraCapabilities.swift, implement it on the
        // device side, and inject it from CameraManagersContainer instead.
        /*
         if FilterManager.shared.selectedFilter.isFilmSimulation {
             let output = CameraSessionManager.shared.getStillImageOutput()
             // Check ProRAW first.
             if CameraDeviceManager.shared.isProRawCaptureSupported(photoOutput: output) {
                 return .proRaw
             }
         }
         */
        .standard
    }

    var imageFileFormat: ImageFileFormat {
        // Default to HEIC and extend later if scenario-specific selection is needed.
        .heic
    }

    // MARK: - Video settings computed properties
    var videoResolution: VideoResolution {
        get { VideoResolution(rawValue: videoResolutionRaw) ?? .hd1080 }
        set { videoResolutionRaw = newValue.rawValue }
    }

    var videoFrameRate: VideoFrameRate {
        get { VideoFrameRate(rawValue: videoFrameRateRaw) ?? .fps30 }
        set { videoFrameRateRaw = newValue.rawValue }
    }

    var videoSaveFormat: VideoSaveFormat {
        get { VideoSaveFormat(rawValue: videoSaveFormatRaw) ?? .mov }
        set { videoSaveFormatRaw = newValue.rawValue }
    }

    // MARK: - Audio settings computed properties
    var audioPickupPattern: AudioPickupPattern {
        get { AudioPickupPattern(rawValue: audioPickupPatternRaw) ?? .voice }
        set { audioPickupPatternRaw = newValue.rawValue }
    }

    // MARK: - File naming format computed properties
    var fileNamingFormat: FileNamingFormat {
        get { FileNamingFormat(rawValue: fileNamingFormatRaw) ?? .standard }
        set { fileNamingFormatRaw = newValue.rawValue }
    }

    var effectiveFileNamingTemplate: String {
        switch fileNamingFormat {
        case .custom:
            return customFileNamingFormat.isEmpty ? FileNamingFormat.standard.template : customFileNamingFormat
        default:
            return fileNamingFormat.template
        }
    }

    var guidelinesType: GuidelinesType {
        get {
            GuidelinesType(rawValue: guidelinesTypeRaw) ?? .off
        }
        set {
            guidelinesTypeRaw = newValue.rawValue
        }
    }

    var isoPreset: ISOPreset {
        get { ISOPreset(rawValue: isoPresetRaw) ?? .balanced }
        set { isoPresetRaw = newValue.rawValue }
    }

    var shutterSpeedPreset: ShutterSpeedPreset {
        get { ShutterSpeedPreset(rawValue: shutterSpeedPresetRaw) ?? .handheld }
        set { shutterSpeedPresetRaw = newValue.rawValue }
    }

    /// Convenient accessor.
    var maxISO: Double {
        isoPreset.maxISO
    }

    var minShutterSpeed: Double {
        shutterSpeedPreset.minShutterSpeed
    }

    // MARK: - method
    func setCaptureMode(_ mode: CameraCaptureMode) {
        currentCaptureMode = mode
        generateHapticFeedback()
    }

    func setAspectRatio(_ preset: AspectRatioPreset) {
        aspectRatio = preset.rawValue
        generateHapticFeedback()
    }

    func setTimerSeconds(_ timer: TimerSeconds) {
        timerCaptureSeconds = timer.rawValue
        generateHapticFeedback()
    }

    // MARK: - Video setting method
    func setVideoResolution(_ resolution: VideoResolution) {
        videoResolution = resolution
        generateHapticFeedback()
    }

    func setVideoFrameRate(_ frameRate: VideoFrameRate) {
        videoFrameRate = frameRate
        generateHapticFeedback()
    }

    func setVideoSaveFormat(_ format: VideoSaveFormat) {
        videoSaveFormat = format
        generateHapticFeedback()
    }

    // MARK: - How to set file naming format
    func setFileNamingFormat(_ format: FileNamingFormat) {
        fileNamingFormat = format
        generateHapticFeedback()
    }

    func setCustomFileNamingFormat(_ template: String) {
        customFileNamingFormat = template
        generateHapticFeedback()
    }

    func setFileNamingPrefix(_ prefix: String) {
        fileNamingPrefix = prefix
        generateHapticFeedback()
    }

    func setGuidelinesType(_ type: GuidelinesType) {
        guidelinesType = type
        generateHapticFeedback()
    }

    // MARK: - Audio setting method
    func setAudioNoiseReduction(_ enabled: Bool) {
        audioNoiseReductionEnabled = enabled
        generateHapticFeedback()
    }

    func setAudioPickupPattern(_ pattern: AudioPickupPattern) {
        audioPickupPattern = pattern
        generateHapticFeedback()
    }

    func toggleSetting<T>(_ keyPath: ReferenceWritableKeyPath<CameraSettingsState, T>) where T: Equatable {
        if T.self == Bool.self {
            let currentValue = self[keyPath: keyPath] as! Bool
            self[keyPath: keyPath] = !currentValue as! T
            generateHapticFeedback()
        }
    }

    /// Special handling for GPS settings.
    func toggleGPSSetting() {
        if saveGPSEnabled {
            // If it is currently on, close it directly.
            saveGPSEnabled = false
            generateHapticFeedback()
            return
        }

        // Turning it on needs location access. A-10: the provider is injected
        // by the composition root; if nothing wired it up (a unit test, a
        // preview, a future second entry point) we leave the switch off rather
        // than silently tagging photos without permission.
        guard let permissions = locationPermissions else {
            debugLog("📍 未注入位置权限提供者，GPS 开关保持关闭")
            return
        }

        if permissions.hasLocationPermission {
            // Already have permission, enable it directly.
            saveGPSEnabled = true
            generateHapticFeedback()
        } else {
            // No permission yet, request it.
            permissions.requestLocationPermission()
            _pendingGPSEnable = true
        }
    }

    /// Tracks whether GPS should be enabled after permission is granted.
    private var _pendingGPSEnable = false

    /// Called after location permission is granted.
    func onLocationPermissionGranted() {
        if _pendingGPSEnable {
            saveGPSEnabled = true
            _pendingGPSEnable = false
            generateHapticFeedback()
        }
    }

    // MARK: - Automation convenience methods
    // The collection logic related to filtering is managed by FilterManager and is not maintained in the setting state.
    func generateHapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// MARK: - notification extension
extension Notification.Name {
    static let videoResolutionDidChange = Notification.Name("videoResolutionDidChange")
    static let videoFrameRateDidChange = Notification.Name("videoFrameRateDidChange")
    static let videoStabilizationDidChange = Notification.Name("videoStabilizationDidChange")
    static let audioSettingsDidChange = Notification.Name("audioSettingsDidChange")
}
