import SwiftUI

/// Centralized layout configuration for the camera view
enum CameraLayoutConfig {
    // MARK: - Layout Constants

    /// Height of the top system-bar band. On notch / Dynamic Island devices
    /// the camera controls row sits *below* the island (island bottom ≈ 48pt,
    /// row bottom at 88pt), so the band reserves 96pt. Without a notch there
    /// is nothing to clear and the row hugs the top as before.
    static var topMenuHeight: CGFloat {
        hasNotch ? 96 : 52
    }

    static let bottomControlHeight: CGFloat = 210

    static let drawerSheetHeight: CGFloat = 340

    // MARK: - Helper Properties

    static var hasNotch: Bool {
        guard let window = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .filter(\.isKeyWindow).first
        else {
            return false
        }
        return window.safeAreaInsets.top > 20
    }

    // MARK: - Computed Properties

    static func availableHeight(
        for geometry: GeometryProxy,
        bottomControlHeight: CGFloat
    ) -> CGFloat {
        geometry.size.height - topMenuHeight - bottomControlHeight
    }

    static func availableWidth(for geometry: GeometryProxy) -> CGFloat {
        geometry.size.width
    }
}
