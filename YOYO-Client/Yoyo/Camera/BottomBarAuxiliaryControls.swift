import SwiftUI

// MARK: - AI Composition Button

/// AI composition entry, placed in the upper row of the bottom control bar
/// (mirror of the filter thumbnail). Tapping it either hides the running
/// inspiration overlay or broadcasts `.prepareAIInspiration`, which the preview
/// view model turns into the two-step "confirm frame → generate" flow.
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
