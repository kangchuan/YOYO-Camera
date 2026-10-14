import SwiftUI

// MARK: - Camera Control View Design Constants

/// Shared design constants for the camera control view
enum CameraControlDesign {
    /// Small-screen threshold (iPhone 12 mini and smaller)
    static let smallScreenThreshold: CGFloat = 390

    /// Whether the device has a small screen
    static var isSmallScreen: Bool {
        UIScreen.main.bounds.width < smallScreenThreshold
    }

    /// Side button size (gallery and filter buttons)
    static var sideButtonSize: CGFloat {
        isSmallScreen ? 40 : 48
    }

    /// Filter button width (slightly wider than its height)
    static var filterButtonWidth: CGFloat {
        sideButtonSize * 1.25
    }

    // MARK: - Two-row bottom bar (2026-10 redesign)

    /// Filter thumbnail size in the upper row (square)
    static var filterThumbnailSize: CGFloat {
        isSmallScreen ? 48 : 56
    }

    /// AI composition button size in the upper row (circular)
    static var aiButtonSize: CGFloat {
        isSmallScreen ? 48 : 56
    }

    /// Vertical spacing between the upper and lower rows
    static var rowSpacing: CGFloat {
        isSmallScreen ? 18 : 22
    }

    /// Capture mode pill: container height / segment height / font size / segment horizontal padding
    static var modePillHeight: CGFloat {
        isSmallScreen ? 34 : 38
    }

    static var modePillSegmentHeight: CGFloat {
        isSmallScreen ? 26 : 30
    }

    static var modePillFontSize: CGFloat {
        isSmallScreen ? 14 : 15
    }

    static var modePillSegmentHPadding: CGFloat {
        isSmallScreen ? 14 : 18
    }

    /// Bottom control bar padding
    static var bottomPadding: CGFloat {
        isSmallScreen ? 40 : 50
    }

    /// Horizontal padding for side buttons
    static var horizontalPadding: CGFloat {
        isSmallScreen ? 20 : 30
    }
}
