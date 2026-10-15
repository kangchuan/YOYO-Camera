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
                //
                // Icon only, no visible label: the bottom control band is a
                // fixed 210pt owned by the mode pill, and a text label either
                // collides with the pill (stacked) or breaks the centred
                // handle symmetry (beside it). The affordance stays
                // discoverable through the 44pt tap target and through
                // VoiceOver, which reads "参数" from the accessibility label.
                ZStack {
                    Capsule()
                        .fill(.regularMaterial)
                        .environment(\.colorScheme, .dark)
                        .frame(width: 44, height: 16)

                    Capsule()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 20, height: 1.5)
                }
                .frame(width: 44, height: 16)
                .contentShape(Rectangle())
                // UX-12: grow the tap target to the iOS-recommended 44pt.
                // Done as an *overlay* on purpose: an overlay overflows the
                // 16pt visual without entering the layout, whereas a taller
                // `.frame` here would push the handle up into the pill row.
                .overlay {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture { expandDrawer() }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(String.cameraDrawerHandleLabel.localized))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { expandDrawer() }
            }
            .frame(height: CameraLayoutConfig.bottomControlHeight)
        }
    }

    private func expandDrawer() {
        triggerLightImpact()
        var transaction = Transaction(animation: .none)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isDrawerExpanded = true
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
