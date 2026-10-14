import SwiftUI

// MARK: - Design Constants

private enum CameraControlPanelDesign {
    static let buttonColor = Color.white.opacity(0.12)
    static let buttonActiveColor = Color.white
    static let iconActiveColor = Color.black
    /// All four corners are rounded — the panel floats above the control bar
    /// and no longer sits flush against the screen bottom.
    static let cornerRadius: CGFloat = 38
    static let buttonSize: CGFloat = 56
    static let expandedButtonWidth: CGFloat = 142
    static let iconSize: CGFloat = 24
    static let labelSize: CGFloat = 13

    // MARK: - Aspect-ratio button glyph (2026-10, round 4)

    /// Outer size of the viewfinder-corner glyph. Kept close to the 24pt optical
    /// size of the SF Symbol icons so the ratio button does not outweigh them.
    /// 28pt (rather than 26pt) leaves room for the widest caption, "9:16".
    static let aspectFrameSize: CGFloat = 28
    static let aspectFrameLineWidth: CGFloat = 1.8
    static let aspectFrameArmLength: CGFloat = 7
    static let aspectDigitsSize: CGFloat = 11

    /// One column is a quarter of the content width. The second row of buttons
    /// reuses the same width so both rows share a single rhythm.
    static var columnWidth: CGFloat {
        let available = UIScreen.main.bounds.width
            - outerHorizontalInset * 2
            - contentHorizontalPadding * 2
        return max(buttonSize, available / 4)
    }

    // MARK: - Floating layout (2026-10 redesign, round 3)

    /// Gap between the panel and the left/right screen edges
    static let outerHorizontalInset: CGFloat = 10

    /// Gap between the panel and the screen bottom edge. Needed because the
    /// panel now rounds all four corners — sitting flush would expose the
    /// control bar through the bottom corner cut-outs.
    static let outerBottomGap: CGFloat = 16

    /// Vertical gap between an icon circle and its caption
    static let labelSpacing: CGFloat = 6

    /// Vertical gap between the two button rows
    static let rowSpacing: CGFloat = 16

    /// Padding between the panel edge and its buttons
    static var contentHorizontalPadding: CGFloat {
        CameraControlDesign.isSmallScreen ? 20 : 30
    }

    static let contentTopPadding: CGFloat = 18

    /// Symmetric with the top inset now that the panel is no longer flush
    static let contentBottomPadding: CGFloat = 18
}

// MARK: - CameraControlPanel

struct CameraControlPanel: View {
    @ObservedObject var settingsState: CameraSettingsState
    let viewState: CameraViewState
    let sessionManager: CameraSessionManager
    let automationManager: CameraAutomationManager?
    @EnvironmentObject var permissionManager: PermissionManager
    let orientationManager: OrientationManager

    @State private var showingControlPanel = false

    var body: some View {
        Button {
            showingControlPanel = true
        } label: {
            SixDotsMenuGlyph()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // The 44pt hit area sits flush against the right screen edge so the
        // glyph center lands 22pt from the edge (iOS camera convention). The
        // row itself carries 16pt horizontal padding — this cancels it for
        // this button only.
        .padding(.trailing, -16)
        .fullScreenCover(isPresented: $showingControlPanel) {
            CameraControlPanelOverlay(
                settingsState: settingsState,
                viewState: viewState,
                sessionManager: sessionManager,
                permissionManager: permissionManager,
                isPresented: $showingControlPanel
            )
            .presentationBackground(.clear)
            .statusBarHidden(true)
            .transaction { $0.disablesAnimations = true }
        }
        .transaction { $0.disablesAnimations = true }
    }
}

// MARK: - Control Panel Overlay

private struct CameraControlPanelOverlay: View {
    @ObservedObject var settingsState: CameraSettingsState
    @ObservedObject var viewState: CameraViewState
    let sessionManager: CameraSessionManager
    let permissionManager: PermissionManager
    @Binding var isPresented: Bool

    @State private var isVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Transparent background; tap to dismiss
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissPanel()
                }

            // Control panel — floats above the bottom control bar with all four
            // corners rounded (2026-10 redesign; it used to anchor top-trailing)
            if isVisible {
                CameraControlPanelContent(
                    settingsState: settingsState,
                    viewState: viewState,
                    sessionManager: sessionManager,
                    permissionManager: permissionManager,
                    dismissAction: { dismissPanel() },
                    openSettings: {
                        dismissPanel()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewState.showingSettings = true
                        }
                    }
                )
                .trackScreen(name: "CameraControlPanel")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.01)) // Almost transparent but still tappable
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                isVisible = true
            }
        }
    }

    private func dismissPanel() {
        withAnimation(.easeOut(duration: 0.15)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }
}

// MARK: - Control Panel View

private struct CameraControlPanelContent: View {
    @ObservedObject var settingsState: CameraSettingsState
    @ObservedObject var viewState: CameraViewState
    let sessionManager: CameraSessionManager
    let permissionManager: PermissionManager
    let dismissAction: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: CameraControlPanelDesign.rowSpacing) {
            // Capture-mode switch and front/back flip moved to the bottom
            // control bar (2026-10 redesign); this panel keeps the
            // secondary toggles only.

            // First row: flash, timer, Live Photo/stabilization, aspect ratio
            HStack(spacing: 0) {
                FlashTorchButton(settingsState: settingsState)
                    .frame(width: CameraControlPanelDesign.columnWidth)
                TimerCycleButton(settingsState: settingsState)
                    .frame(width: CameraControlPanelDesign.columnWidth)
                LivePhotoStabButton(settingsState: settingsState)
                    .frame(width: CameraControlPanelDesign.columnWidth)
                AspectRatioButton(settingsState: settingsState)
                    .frame(width: CameraControlPanelDesign.columnWidth)
            }
            .frame(maxWidth: .infinity)

            // Second row: GPS, save original, and settings — three buttons in the
            // same column width as the first row, centred as a group.
            HStack(spacing: 0) {
                // GPS button
                CameraControlPanelButton(
                    icon: "location.fill",
                    label: String.cameraPanelLocation.localized,
                    isActive: settingsState.saveGPSEnabled
                ) {
                    settingsState.toggleGPSSetting()
                    AnalyticsManager.shared.log(.settingsAction(action: "toggle_gps_\(settingsState.saveGPSEnabled)"))
                }
                .frame(width: CameraControlPanelDesign.columnWidth)

                // Save-original button
                CameraControlPanelButton(
                    icon: "rectangle.on.rectangle.fill",
                    label: String.cameraPanelOriginal.localized,
                    isActive: settingsState.saveOriginalEnabled
                ) {
                    settingsState.toggleSetting(\.saveOriginalEnabled)
                    AnalyticsManager.shared.log(.settingsAction(action: "toggle_save_original_\(settingsState.saveOriginalEnabled)"))
                }
                .frame(width: CameraControlPanelDesign.columnWidth)

                // More-settings button
                CameraControlPanelButton(
                    icon: "gearshape.fill",
                    label: String.cameraPanelSettings.localized,
                    isActive: false
                ) {
                    settingsState.generateHapticFeedback()
                    openSettings()
                }
                .frame(width: CameraControlPanelDesign.columnWidth)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, CameraControlPanelDesign.contentHorizontalPadding)
        .padding(.top, CameraControlPanelDesign.contentTopPadding)
        .padding(.bottom, CameraControlPanelDesign.contentBottomPadding)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: CameraControlPanelDesign.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: -8)
        }
        .padding(.horizontal, CameraControlPanelDesign.outerHorizontalInset)
        .padding(.bottom, CameraControlPanelDesign.outerBottomGap)
    }
}

// MARK: - Flash & Torch Button

private struct FlashTorchButton: View {
    @ObservedObject var settingsState: CameraSettingsState

    private var flashIcon: String {
        if settingsState.currentCaptureMode == .movie {
            return "flashlight.on.fill"
        }
        return "bolt.fill"
    }

    private var isActive: Bool {
        if settingsState.currentCaptureMode == .movie {
            return settingsState.torchEnabled
        }
        return settingsState.flashMode == .on
    }

    var body: some View {
        CameraControlPanelButton(
            icon: flashIcon,
            label: String.cameraPanelFlash.localized,
            isActive: isActive
        ) {
            settingsState.generateHapticFeedback()
            if settingsState.currentCaptureMode == .movie {
                settingsState.torchEnabled.toggle()
                CameraDeviceManager.shared.setTorch(enabled: settingsState.torchEnabled)
            } else {
                settingsState.flashMode = (settingsState.flashMode == .on) ? .off : .on
            }
            AnalyticsManager.shared.log(.settingsAction(action: "toggle_flash_torch_\(isActive)"))
        }
    }
}

// MARK: - LivePhoto & Stabilization Button

private struct LivePhotoStabButton: View {
    @ObservedObject var settingsState: CameraSettingsState

    private var icon: String {
        if settingsState.currentCaptureMode == .movie {
            return "water.waves"
        }
        return "livephoto"
    }

    private var isActive: Bool {
        if settingsState.currentCaptureMode == .movie {
            return settingsState.stabilizationEnabled
        }
        return settingsState.currentCaptureMode == .livePhoto
    }

    /// Caption follows the mode: the same slot means Live Photo in photo mode
    /// and video stabilization in movie mode.
    private var label: String {
        settingsState.currentCaptureMode == .movie
            ? String.cameraPanelStabilization.localized
            : String.cameraPanelLive.localized
    }

    var body: some View {
        CameraControlPanelButton(icon: icon, label: label, isActive: isActive) {
            settingsState.generateHapticFeedback()
            if settingsState.currentCaptureMode == .movie {
                settingsState.stabilizationEnabled.toggle()
            } else {
                if settingsState.currentCaptureMode == .livePhoto {
                    settingsState.currentCaptureMode = .photo
                } else {
                    settingsState.currentCaptureMode = .livePhoto
                }
            }
            AnalyticsManager.shared.log(.settingsAction(action: "toggle_live_stab_\(isActive)"))
        }
    }
}

// MARK: - Panel Button Shell

/// Shared layout for every panel button: a circular 56pt well with the glyph
/// centred inside, plus a caption underneath. Callers supply the glyph.
private struct PanelButtonShell<Center: View>: View {
    let label: String
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void
    let center: () -> Center

    init(
        label: String,
        isActive: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder center: @escaping () -> Center
    ) {
        self.label = label
        self.isActive = isActive
        self.isEnabled = isEnabled
        self.action = action
        self.center = center
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: CameraControlPanelDesign.labelSpacing) {
                center()
                    .frame(width: CameraControlPanelDesign.buttonSize, height: CameraControlPanelDesign.buttonSize)
                    .background(isActive ? CameraControlPanelDesign.buttonActiveColor : CameraControlPanelDesign.buttonColor)
                    .clipShape(Circle())

                Text(label)
                    .font(.system(size: CameraControlPanelDesign.labelSize,
                                  weight: isActive ? .medium : .regular))
                    .foregroundColor(.white.opacity(isActive ? 1 : 0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // Equal-width columns so the buttons stay evenly distributed
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            // Greyed out when the underlying setting cannot take effect
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Control Panel Button (SF Symbol)

private struct CameraControlPanelButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        PanelButtonShell(label: label, isActive: isActive, action: action) {
            Image(systemName: icon)
                .font(.system(size: CameraControlPanelDesign.iconSize, weight: .medium))
                .foregroundColor(isActive ? CameraControlPanelDesign.iconActiveColor : .white)
        }
    }
}

// MARK: - Aspect Ratio Button

/// Cycles through the aspect-ratio presets. The glyph shows the current preset
/// as text framed by viewfinder corners, sized to match the SF Symbol icons.
private struct AspectRatioButton: View {
    @ObservedObject var settingsState: CameraSettingsState

    /// Video capture pins the aspect ratio to 9:16 inside the capture pipeline,
    /// so the control has no effect there — show it greyed out and untappable.
    private var isEnabled: Bool {
        settingsState.currentCaptureMode != .movie
    }

    var body: some View {
        PanelButtonShell(
            label: String.cameraSettingsAspectRatio.localized,
            isActive: false,
            isEnabled: isEnabled,
            action: cycleAspectRatio
        ) {
            ZStack {
                ViewfinderCorners()

                Text(settingsState.currentAspectRatioPreset.displayName)
                    .font(.system(size: CameraControlPanelDesign.aspectDigitsSize,
                                  weight: .medium,
                                  design: .monospaced))
                    .kerning(-0.5)
                    .foregroundColor(.white)
                    .fixedSize()
            }
        }
    }

    private func cycleAspectRatio() {
        let allPresets = CameraSettingsState.AspectRatioPreset.allCases
        let currentIndex = allPresets.firstIndex(of: settingsState.currentAspectRatioPreset) ?? 0
        let next = allPresets[(currentIndex + 1) % allPresets.count]
        // setAspectRatio(_:) already fires the haptic feedback
        settingsState.setAspectRatio(next)
        AnalyticsManager.shared.log(.settingsAction(action: "cycle_aspect_ratio_\(next.displayName)"))
    }
}

// MARK: - Viewfinder Corners Glyph

/// Four corner brackets forming a small viewfinder mark around the ratio text.
private struct ViewfinderCorners: View {
    var body: some View {
        Path { path in
            let size = CameraControlPanelDesign.aspectFrameSize
            let inset = CameraControlPanelDesign.aspectFrameLineWidth / 2
            let arm = CameraControlPanelDesign.aspectFrameArmLength
            let minX = inset
            let minY = inset
            let maxX = size - inset
            let maxY = size - inset

            // Top left
            path.move(to: CGPoint(x: minX, y: minY + arm))
            path.addLine(to: CGPoint(x: minX, y: minY))
            path.addLine(to: CGPoint(x: minX + arm, y: minY))

            // Top right
            path.move(to: CGPoint(x: maxX - arm, y: minY))
            path.addLine(to: CGPoint(x: maxX, y: minY))
            path.addLine(to: CGPoint(x: maxX, y: minY + arm))

            // Bottom right
            path.move(to: CGPoint(x: maxX, y: maxY - arm))
            path.addLine(to: CGPoint(x: maxX, y: maxY))
            path.addLine(to: CGPoint(x: maxX - arm, y: maxY))

            // Bottom left
            path.move(to: CGPoint(x: minX + arm, y: maxY))
            path.addLine(to: CGPoint(x: minX, y: maxY))
            path.addLine(to: CGPoint(x: minX, y: maxY - arm))
        }
        .stroke(
            Color.white,
            style: StrokeStyle(
                lineWidth: CameraControlPanelDesign.aspectFrameLineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
        .frame(width: CameraControlPanelDesign.aspectFrameSize,
               height: CameraControlPanelDesign.aspectFrameSize)
    }
}

// MARK: - Timer Cycle Button (Cycle Through Timer Options)

private struct TimerCycleButton: View {
    @ObservedObject var settingsState: CameraSettingsState

    private var timerIcon: String {
        if !settingsState.timerCaptureEnabled {
            return "timer"
        }
        switch settingsState.timerCaptureSeconds {
        case 5: return "gobackward.5"
        case 10: return "gobackward.10"
        case 30: return "gobackward.30"
        default: return "timer"
        }
    }

    var body: some View {
        CameraControlPanelButton(
            icon: timerIcon,
            label: String.cameraPanelTimer.localized,
            isActive: settingsState.timerCaptureEnabled,
            action: cycleTimer
        )
    }

    private func cycleTimer() {
        settingsState.generateHapticFeedback()

        if !settingsState.timerCaptureEnabled {
            // Off -> 5s
            settingsState.timerCaptureEnabled = true
            settingsState.timerCaptureSeconds = 5
        } else {
            switch settingsState.timerCaptureSeconds {
            case 5:
                settingsState.timerCaptureSeconds = 10
            case 10:
                settingsState.timerCaptureSeconds = 30
            case 30:
                // 30s -> Off
                settingsState.timerCaptureEnabled = false
            default:
                settingsState.timerCaptureEnabled = false
            }
        }

        let timerValue = settingsState.timerCaptureEnabled ? settingsState.timerCaptureSeconds : 0
        AnalyticsManager.shared.log(.settingsAction(action: "cycle_timer_\(timerValue)"))
    }
}

// MARK: - Preview

#Preview {
    let settingsState = CameraSettingsState.shared
    let viewState = CameraViewState()
    let permissionManager = PermissionManager.shared
    let orientationManager = OrientationManager.shared
    let sessionManager = CameraSessionManager.shared

    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            HStack {
                Spacer()
                CameraControlPanel(
                    settingsState: settingsState,
                    viewState: viewState,
                    sessionManager: sessionManager,
                    automationManager: nil,
                    orientationManager: orientationManager
                )
                .environmentObject(permissionManager)
                .padding()
            }
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

// MARK: - Six-Dots Menu Glyph

/// Six-dot grid menu glyph (2 rows x 3 columns) for the camera panel trigger.
/// Drawn by hand: no SF Symbol matches this look (`ellipsis` is only 3 dots),
/// following the same approach as `ViewfinderCorners`.
private struct SixDotsMenuGlyph: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = 1.6
            let pitch: CGFloat = 6.4
            for dy in [-pitch / 2, pitch / 2] {
                for dx in [-pitch, 0, pitch] {
                    let rect = CGRect(
                        x: center.x + dx - radius,
                        y: center.y + dy - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(0.9))
                    )
                }
            }
        }
        .frame(width: 20, height: 12)
        .accessibilityHidden(true)
    }
}
