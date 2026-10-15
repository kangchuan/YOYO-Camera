import SwiftUI

// MARK: - Capture Button Design Constants

private enum CaptureButtonDesign {
    /// Small-screen threshold (kept consistent with other camera controls)
    static let smallScreenThreshold: CGFloat = 390

    /// Whether the device has a small screen
    static var isSmallScreen: Bool {
        UIScreen.main.bounds.width < smallScreenThreshold
    }
}

/// Capture button
struct CaptureButton: View {
    /// Optimization: remove the unused `viewState` to avoid unnecessary refreshes
    @ObservedObject var settingsState: CameraSettingsState

    @State private var captureState: CaptureState = .idle

    private var isSmallScreen: Bool {
        CaptureButtonDesign.isSmallScreen
    }

    /// Base size constants (circular)
    private var outerWidth: CGFloat {
        isSmallScreen ? 68 : 76
    }

    private var outerHeight: CGFloat {
        outerWidth
    }

    private var innerWidth: CGFloat {
        isSmallScreen ? 60 : 68
    }

    private var innerHeight: CGFloat {
        innerWidth
    }

    // Optimization: adjust the stop button size for better visual balance inside the circular outer ring
    private let cancelWidth: CGFloat = 30
    private let cancelHeight: CGFloat = 24
    private let cancelCornerRadius: CGFloat = 4

    // Performance optimization: cache static gradients to avoid repeated calculations
    // Removed unused `outerRingGradient`

    // Removed unused `outerRingStyle`

    /// Computed property: inner button style with flat colors
    private var innerButtonStyle: Color {
        switch settingsState.currentCaptureMode {
        case .photo:
            return .white
        case .livePhoto:
            return .accentColor
        case .movie:
            return .red
        }
    }

    var action: (() -> Void)?

    /// UX-10: fired when the user starts a long-press on the shutter. The
    /// parent (typically `BottomControlBar`) uses this to enable the
    /// "preview original" bypass on `FilterManager`. Fired only on the
    /// press-down side, not on release.
    var onLongPressStarted: (() -> Void)?

    /// UX-10: fired when the long-press ends (finger lifted, gesture
    /// cancelled, or interrupted by a system alert). The parent uses
    /// this to clear the bypass and restore the live filter preview.
    var onLongPressEnded: (() -> Void)?

    /// UX-10: how long the finger must stay down before the bypass kicks
    /// in. Picked to be shorter than iOS's system "press-and-hold" camera
    /// gesture so the feature feels native.
    private let longPressDuration: Double = 0.35

    /// UX-10: how long after a long-press ends we keep swallowing the
    /// Button's release action. See `body`.
    private let releaseSuppressionWindow: TimeInterval = 0.25

    /// UX-10: reports whether the user is currently holding the shutter.
    /// `LongPressGesture` ends at the *threshold*, not on release, so it is
    /// sequenced into a zero-distance `DragGesture`, which ends when the
    /// finger actually leaves the screen. (There is no
    /// `LongPressGesture.onStarted`, so the press-down side is driven by
    /// `updating` instead.)
    @GestureState private var isPressing: Bool = false

    /// UX-10: when the last long-press ended.
    @State private var holdEndedAt: Date?

    var body: some View {
        Button(
            action: {
                // A long press also ends with a finger lift, which the
                // Button turns into a normal tap: holding the shutter to
                // peek at the original would otherwise *also* take a photo.
                //
                // Swallowed by time window rather than by a boolean flag,
                // because SwiftUI gives no ordering guarantee between the
                // button action and the gesture-end update — with a flag,
                // the wrong one running first costs us either an unwanted
                // photo or a permanently dead shutter.
                if let endedAt = holdEndedAt,
                   Date().timeIntervalSince(endedAt) < releaseSuppressionWindow {
                    holdEndedAt = nil
                    return
                }
                action?()
            }) {
                ZStack {
                    // 2. Outer ring - circular with a frosted-glass look
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: outerWidth, height: outerHeight)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.3)
                        )

                    // 3. Inner button
                    let isPressed = captureState.isWaiting || captureState.isCapturing
                    RoundedRectangle(cornerRadius: isPressed ? cancelCornerRadius : innerHeight / 2)
                        .fill(innerButtonStyle)
                        .frame(
                            width: isPressed ? cancelWidth : innerWidth,
                            height: isPressed ? cancelHeight : innerHeight
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)

                    // 4. Capture-in-progress indicator
                    if captureState.isCapturing, settingsState.currentCaptureMode != .movie {
                        LoadingIndicator()
                            .frame(width: outerWidth, height: outerHeight)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: outerWidth, height: outerHeight)
            .onReceive(NotificationCenter.default.publisher(for: .cameraCaptureStateChanged)) { notification in
                if let newState = notification.userInfo?[CameraNotificationKeys.captureState] as? CaptureState {
                    captureState = newState
                }
            }
            // UX-10: long-press = "see original". The tap keeps working
            // through the Button's own action, so VoiceOver / keyboard /
            // pointer activation still captures normally.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: longPressDuration)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($isPressing) { value, state, _ in
                        switch value {
                        case .first:
                            // Threshold not reached yet — still a tap.
                            state = false
                        case .second:
                            // Threshold reached; the trailing drag ends on
                            // release (or on cancel), at which point
                            // SwiftUI resets the gesture state for us.
                            state = true
                        }
                    }
            )
            .onChange(of: isPressing) { _, isNowPressing in
                if isNowPressing {
                    holdEndedAt = nil
                    onLongPressStarted?()
                } else {
                    holdEndedAt = Date()
                    onLongPressEnded?()
                }
            }
    }
}
