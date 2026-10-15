import Combine
import SwiftData
import SwiftUI

/// Shared haptic feedback helper
@MainActor
private func triggerLightImpact() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

struct CameraControlView: View {
    private enum SwipeConfig {
        static let minimumDistance: CGFloat = 30
        static let downwardThreshold: CGFloat = 40
        static let leftTriggerRatio: CGFloat = 0.4
        static let rightTriggerRatio: CGFloat = 0.6
    }

    // Note: avoid observing high-frequency objects at the top level to prevent frequent redraws of the entire control view; child views observe them individually instead
    let latestPhoto: PhotoAsset?
    let managers: CameraManagersContainer

    /// Whether the drawer is expanded
    @Binding var isDrawerExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Bottom control bar
            BottomControlBar(
                latestPhoto: latestPhoto,
                managers: managers
            )
            .overlay(alignment: .bottom) {
                // Drawer handle — centred below the two control rows.
                // UX-12: the visible handle is still 44×16, but the *hit
                // area* is now 44pt tall (the whole Capsule frame), and a
                // small "参数" label sits 4pt below the handle to make
                // the affordance discoverable.
                VStack(spacing: 4) {
                    Button {
                        triggerLightImpact()
                        var transaction = Transaction(animation: .none)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            isDrawerExpanded = true
                        }
                    } label: {
                        ZStack {
                            Capsule()
                                .fill(.regularMaterial)
                                .environment(\.colorScheme, .dark)
                                .frame(width: 44, height: 16)

                            Capsule()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: 20, height: 1.5)
                        }
                        // Expand the tappable area without changing the
                        // visual. 44pt is the iOS-recommended minimum for
                        // hit targets; we add the extra space evenly above
                        // and below the visible handle.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(String.cameraDrawerHandleLabel.localized))

                    Text(String.cameraDrawerHandleLabel.localized)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.55))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: CameraLayoutConfig.bottomControlHeight)
        }
    }
}

/// #Preview
struct CameraControlView_Previews: PreviewProvider {
    static var previews: some View {
        let managers = CameraManagersContainer()

        return CameraControlView(
            latestPhoto: nil,
            managers: managers,
            isDrawerExpanded: .constant(false)
        )
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
