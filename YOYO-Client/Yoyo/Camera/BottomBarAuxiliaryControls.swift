import SwiftUI

// MARK: - AI Composition Button

/// AI composition entry, placed in the upper row of the bottom control bar
/// (mirror of the filter thumbnail). Tapping it either hides the running
/// inspiration overlay or broadcasts `.prepareAIInspiration`, which the preview
/// view model turns into the two-step "confirm frame → generate" flow.
///
/// The button also reflects two non-gestural states:
///  - **Pro required** (UX-01): when the user is logged in but not Pro, a
///    small crown badge is overlaid so the user can see why the path is
///    gated before they tap.
///  - **Insufficient credits** (UX-04): when the user is Pro but has 0
///    credits, the icon is dimmed and the badge switches to a "low credit"
///    state. The actual pre-click gate still lives in
///    `InspirationManager.requestAIInspirations`; this is a visual hint.
struct AICompositionButton: View {
    @ObservedObject var inspirationManager: InspirationManager
    let rotation: Double
    let onTap: () -> Void

    private var size: CGFloat {
        CameraControlDesign.aiButtonSize
    }

    private var isActive: Bool {
        inspirationManager.isShowingInspirations
    }

    private var isLoggedIn: Bool {
        AuthService.shared.isLoggedIn
    }

    private var isPro: Bool {
        AuthService.shared.currentUser?.subscriptionStatus == 1
    }

    private var hasCredits: Bool {
        CreditCost.hasEnoughCredits(
            current: inspirationManager.credits,
            cost: CreditCost.aiInspiration
        )
    }

    /// Visual badge shown in the top-right corner. Order of priority:
    /// Pro-required > insufficient credits > (nothing).
    @ViewBuilder
    private var stateBadge: some View {
        if isLoggedIn, !isPro {
            // UX-01: signal "Pro" without breaking the design language —
            // small accent-tinted crown in the top-right of the circle.
            Image(systemName: "crown.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.black)
                .padding(4)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )
                .offset(x: size * 0.32, y: -size * 0.32)
                .accessibilityLabel(Text(String.cameraAiProRequired.localized))
        } else if isLoggedIn, isPro, !hasCredits {
            // UX-04: low-credits hint, also surfaced in the panel itself.
            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(4)
                .background(
                    Circle()
                        .fill(Color.orange)
                )
                .offset(x: size * 0.32, y: -size * 0.32)
                .accessibilityLabel(Text(String.aiDarkroomInsufficientCreditsHint.localized))
        }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)

                Circle()
                    .fill(isActive ? Color.white.opacity(0.92) : Color.white.opacity(0.14))

                Circle()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)

                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundColor(isActive ? .black : .white)
            }
            .frame(width: size, height: size)
            .overlay(stateBadge, alignment: .topTrailing)
            .rotationEffect(.degrees(rotation))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String.cameraAiComposition.localized))
    }
}

// MARK: - Capture Mode Pill

/// Text-based capture mode switch (video / photo) shown centred in the lower
/// row. Live Photo remains available from the "···" control panel; when the
/// current mode is `.livePhoto` the pill highlights "photo" since it belongs to
/// the still-photography family.
struct CaptureModePill: View {
    @ObservedObject var settingsState: CameraSettingsState

    private var isVideoSelected: Bool {
        settingsState.currentCaptureMode == .movie
    }

    var body: some View {
        HStack(spacing: 4) {
            segment(
                title: String.cameraCaptureModeVideo.localized,
                isSelected: isVideoSelected
            ) {
                select(.movie)
            }

            segment(
                title: String.cameraCaptureModePhoto.localized,
                isSelected: !isVideoSelected
            ) {
                select(.photo)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func segment(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: CameraControlDesign.modePillFontSize, weight: .medium))
                .foregroundColor(isSelected ? Color.black.opacity(0.85) : Color.white.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, CameraControlDesign.modePillSegmentHPadding)
                .frame(height: CameraControlDesign.modePillSegmentHeight)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func select(_ mode: CameraCaptureMode) {
        guard settingsState.currentCaptureMode != mode else { return }
        settingsState.setCaptureMode(mode)
        // Neutral tint: a mode is a choice, not an on/off state.
        let isVideo = mode == .movie
        CameraViewState.shared.showNeutralToast(
            isVideo ? String.stateToastVideoMode.localized : String.stateToastPhotoMode.localized,
            icon: isVideo ? "video.fill" : "camera.fill"
        )
        AnalyticsManager.shared.log(.settingsAction(action: "switch_mode_\(mode)"))
    }
}

// MARK: - Camera Flip Button

/// Front/back camera switch, placed in the lower row of the bottom control bar.
/// Mirrors the behaviour of the old panel-only rotate button.
struct CameraFlipButton: View {
    let sessionManager: CameraSessionManager
    @ObservedObject var settingsState: CameraSettingsState

    private var size: CGFloat {
        CameraControlDesign.sideButtonSize
    }

    var body: some View {
        Button {
            settingsState.generateHapticFeedback()
            sessionManager.switchCameraPosition()
            AnalyticsManager.shared.log(.settingsAction(action: "switch_camera"))
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)

                Circle()
                    .fill(Color.white.opacity(0.10))

                Circle()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String.cameraFlipCamera.localized))
    }
}
