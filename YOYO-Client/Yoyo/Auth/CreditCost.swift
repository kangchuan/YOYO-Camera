import Foundation

/// Centralised credit cost for AI features.
///
/// All UI that pre-displays "消耗 N 积分" and all pre-click gates must go
/// through this enum. The previous code had magic `1` literals scattered
/// across `InspirationManager` and `AIDarkroomPanelView`, which made it
/// trivial for the displayed cost to drift from the server-side cost.
///
/// These values are intentionally hard-coded. The server is still the
/// source of truth — if the client over-charges the displayed cost the
/// `AIInspirationServiceError.insufficientCredits` 403 path will catch
/// the mismatch on the next request. If the server price changes, bump
/// the constant here and ship an updated app; do not push divergent
/// copies into the call sites.
enum CreditCost {
    /// Cost of the "AI Inspiration" pipeline (one fetchInspirations call).
    static let aiInspiration: Int = 1

    /// Cost of the "AI Darkroom" image edit (one `AIDarkroomService.processImage` call).
    static let aiDarkroom: Int = 1

    /// True when the user has at least one credit (or enough to cover `cost`).
    static func hasEnoughCredits(current: Int?, cost: Int = aiInspiration) -> Bool {
        (current ?? 0) >= cost
    }
}
