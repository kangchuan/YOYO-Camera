import Combine
import SwiftUI

// MARK: - Bottom Control Bar

/// Bottom control bar — two-row, three-column layout:
///
/// Row 1: filter thumbnail · shutter (centred) · AI composition
/// Row 2: album · capture mode pill · front/back flip
struct BottomControlBar: View {
    let latestPhoto: PhotoAsset?
    let managers: CameraManagersContainer

    // Helper properties for easier access
    private var viewState: CameraViewState { managers.viewState }
    private var settingsState: CameraSettingsState { managers.settingsState }

    var body: some View {
        VStack(spacing: CameraControlDesign.rowSpacing) {
            upperRow
            lowerRow
        }
        .frame(maxWidth: .infinity)
        // UX-11: the bottom bar lives in a fixed 210pt band with hard-coded
        // control heights, so an unbounded Dynamic Type size would push the
        // rows out of the band (labels clipped, rows overlapping). Cap it at
        // xxxLarge — large-text users still get real scaling, and the layout
        // stays intact. Everything that is *not* inside this band (sheets,
        // settings, gallery) keeps scaling all the way.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: - Row 1: filter · shutter · AI composition

    private var upperRow: some View {
        ZStack {
            // Shutter — always centred on screen
            CaptureButton(
                settingsState: settingsState,
                action: { managers.captureService.triggerShutterAction() },
                onLongPressStarted: {
                    // UX-10: long-press the shutter to peek at the raw
                    // sensor output. We disable the colour-grading layer
                    // here and restore it on release.
                    triggerLightImpact()
                    FilterManager.shared.previewBypass = true
                },
                onLongPressEnded: {
                    FilterManager.shared.previewBypass = false
                }
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .zIndex(1)

            HStack(spacing: 0) {
                // Filter thumbnail — left side
                FilterGalleryButton(
                    viewState: viewState,
                    rotation: 0 // Rotation is handled by `rotationEffect`
                )
                .rotationEffect(.degrees(viewState.rotation))
                .animation(.easeInOut(duration: 0.3), value: viewState.rotation)

                Spacer()

                // AI composition — right side
                AICompositionButton(
                    inspirationManager: managers.inspirationManager,
                    rotation: viewState.rotation,
                    onTap: { handleAICompositionTap() }
                )
            }
            .padding(.horizontal, CameraControlDesign.horizontalPadding)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Row 2: album · mode pill · flip

    private var lowerRow: some View {
        HStack(spacing: 0) {
            // Gallery — left side
            PhotoGalleryButton(
                latestPhoto: latestPhoto,
                rotation: 0, // Rotation is handled by `rotationEffect`
                isCircular: true,
                onTap: {
                    triggerLightImpact()
                    viewState.showingPhotoGallery = true
                }
            )
            .equatable()
            .rotationEffect(.degrees(viewState.rotation))
            .animation(.easeInOut(duration: 0.3), value: viewState.rotation)

            Spacer(minLength: 8)

            // Shooting mode — centred
            CaptureModePill(settingsState: settingsState)

            Spacer(minLength: 8)

            // Front/back camera — right side
            CameraFlipButton(
                sessionManager: managers.sessionManager,
                settingsState: settingsState
            )
            .rotationEffect(.degrees(viewState.rotation))
            .animation(.easeInOut(duration: 0.3), value: viewState.rotation)
        }
        .padding(.horizontal, CameraControlDesign.horizontalPadding)
    }

    /// Two-step AI flow: tapping again while the inspiration overlay is visible
    /// hides it; otherwise broadcast so the preview VM captures the current frame.
    private func handleAICompositionTap() {
        triggerLightImpact()
        if managers.inspirationManager.isShowingInspirations {
            managers.inspirationManager.clearInspirations()
        } else {
            viewState.sendAction(.prepareAIInspiration)
        }
    }

    @MainActor
    private func triggerLightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Filter Switch Button

/// Filter switch button
struct FilterGalleryButton: View {
    @ObservedObject var filterManager: FilterManager = .shared
    let viewState: CameraViewState
    let rotation: Double

    private var buttonHeight: CGFloat {
        CameraControlDesign.filterThumbnailSize
    }

    private var buttonWidth: CGFloat {
        CameraControlDesign.filterThumbnailSize
    }

    private var cardScale: CGFloat {
        buttonWidth / 300.0
    }

    var body: some View {
        Button(action: {
            triggerLightImpact()
            if !viewState.showingFilterGallery {
                viewState.showingFilterGallery = true
            }
        }) {
            ZStack {
                if filterManager.selectedFilter.category == .custom, let customFilter = filterManager.selectedCustomFilter {
                    customFilterPlaceholder(name: customFilter.name)
                } else if filterManager.selectedFilter.category == .none {
                    // "Original camera" has no LUT/photo background — render the
                    // dedicated square placeholder instead of a scaled-down card
                    // (which would collapse into a tiny text strip).
                    originalCameraPlaceholder
                } else if let displayConfig = filterManager.getDisplayConfig(for: filterManager.selectedFilter) {
                    filterCardWithOverlay(displayConfig: displayConfig)
                } else {
                    placeholderView
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
        }
        .frame(width: buttonWidth, height: buttonHeight)
    }

    @MainActor
    private func triggerLightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @ViewBuilder
    private func customFilterPlaceholder(name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: thumbnailCornerRadius)
                .fill(Color.white.opacity(0.12))

            Text(name)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
        }
        .frame(width: buttonWidth, height: buttonHeight)
    }

    @ViewBuilder
    private func filterCardWithOverlay(displayConfig: FilterDisplayConfig) -> some View {
        // Base card
        FilterCard(displayConfig: displayConfig)
            .scaleEffect(cardScale)
            .frame(width: buttonWidth, height: buttonHeight)
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: thumbnailCornerRadius)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: thumbnailCornerRadius)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
            )
            .frame(width: buttonWidth, height: buttonHeight)
    }

    /// Square tile representing the "Original camera" (no filter) state
    private var originalCameraPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: thumbnailCornerRadius)
                .fill(Color.white.opacity(0.10))

            RoundedRectangle(cornerRadius: thumbnailCornerRadius)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)

            VStack(spacing: 3) {
                Image(systemName: "camera")
                    .font(.system(size: buttonWidth * 0.3, weight: .medium))
                Text(String.filterNoneName.localized)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.9))
        }
        .frame(width: buttonWidth, height: buttonHeight)
    }

    /// Corner radius matching the square 56pt thumbnail design
    private var thumbnailCornerRadius: CGFloat {
        buttonWidth * 0.25
    }
}
