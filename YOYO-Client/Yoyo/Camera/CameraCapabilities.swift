import Foundation

/// A-10: capability protocols.
///
/// The problem they solve: `CameraSettingsState` used to reach straight for
/// `CameraDeviceManager.shared` and `PermissionManager.shared`, while those
/// managers read `CameraSettingsState` back. Two modules pointing at each
/// other means neither can be extracted, reordered or reasoned about on its
/// own, and it is exactly what stops the project from ever splitting into
/// frameworks.
///
/// The fix is not "inject everything" — that is a rewrite. It is to make the
/// consumer state what it *needs* instead of naming a concrete manager, and
/// let the composition root (`CameraManagersContainer`) hand over an
/// implementation. The dependency then points one way: root → both sides.
///
/// Rules for adding to this file:
/// - A protocol describes a capability, not "a manager". Name it after what
///   the caller gets (`LocationPermissionProviding`), not who provides it.
/// - Keep it as small as the call sites need. Every method added here is a
///   method every future implementation must write.
/// - Do not add a default implementation that reaches for `.shared`; that
///   would reintroduce the very edge we are removing.
protocol LocationPermissionProviding: AnyObject {
    /// Whether location access is already granted for this app.
    var hasLocationPermission: Bool { get }

    /// Ask the system for location access. The result arrives asynchronously;
    /// callers re-read `hasLocationPermission` rather than assuming success.
    func requestLocationPermission()
}