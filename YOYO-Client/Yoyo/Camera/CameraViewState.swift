import Combine
import Foundation
import SwiftUI

// MARK: - Global Notification Definitions

extension Notification.Name {
    static let cameraUserAction = Notification.Name("cameraUserAction")
    static let cameraCaptureStateChanged = Notification.Name("cameraCaptureStateChanged")
    static let cameraSaveFinished = Notification.Name("cameraSaveFinished")
}

enum CameraNotificationKeys {
    static let action = "action"
    static let captureState = "captureState"
    static let saveSuccess = "saveSuccess"
    static let saveError = "saveError"
}

// MARK: - Camera View State Manager

@MainActor
final class CameraViewState: ObservableObject {
    // MARK: - Singleton

    static let shared = CameraViewState()

    // MARK: - User Action Intents

    enum UserAction {
        case startCapture
        case startTimerCapture
        case cancel
        case stopRecording
        case reset
        case requestAIInspiration
        /// Bottom-bar AI composition entry: capture the current preview frame
        /// and show the two-step confirmation overlay (does not upload yet).
        case prepareAIInspiration
    }

    /// Broadcast an action
    func sendAction(_ action: UserAction) {
        debugLog("📡 [ViewState] Broadcasting action: \(action)")
        NotificationCenter.default.post(
            name: .cameraUserAction,
            object: nil,
            userInfo: [CameraNotificationKeys.action: action]
        )
    }

    // MARK: - Capture Result State

    // Capture result state is now managed by `CameraCaptureService`

    // MARK: - UI State

    @Published var showingPhotoGallery = false
    @Published var showingFilterGallery = false
    @Published var showingSettings = false
    @Published var showingAutomationSettings = false
    @Published var isInspirationMaximized = false
    @Published var currentToast: ToastMessage? = nil
    @Published var showLensSwitchButton: Bool = true

    // MARK: - Device Rotation State

    @Published var rotation: Double = 0
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupOrientationObservation()
    }

    private func setupOrientationObservation() {
        // Observe device orientation changes
        OrientationManager.shared.$currentDeviceOrientation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deviceOrientation in
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.rotation = OrientationManager.rotationAngle(deviceOrientation)
                }
            }
            .store(in: &cancellables)
    }

    /// Clear the error state for recovery
    func clearError() {
        // Clear the error toast
        currentToast = nil
    }

    /// Force-reset the state
    func forceReset() {
        // Clear the error toast as well
        if currentToast?.type == .error {
            currentToast = nil
        }
    }

    // MARK: - UI State Management

    func resetUIState() {
        showingPhotoGallery = false
        showingFilterGallery = false
        isInspirationMaximized = false
    }

    /// Show a toast message
    func showToast(type: ToastType,
                   message: String,
                   duration: TimeInterval = 3.0,
                   customIcon: String? = nil,
                   accentColor: Color? = nil) {
        let toast = ToastMessage(type: type,
                                 message: message,
                                 duration: duration,
                                 customIcon: customIcon,
                                 accentColor: accentColor)
        currentToast = toast

        // Auto-hide
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if currentToast?.id == toast.id {
                currentToast = nil
            }
        }
    }

    // MARK: - Feature state toasts

    /// How long a feature-toggle confirmation stays on screen. Shorter than the
    /// default because it sits over the viewfinder rather than over a form.
    static let stateToastDuration: TimeInterval = 1.5

    /// Confirm a feature toggle, e.g. "Flash On" / "Flash Off".
    ///
    /// - Parameters:
    ///   - feature: Localized feature name, taken from the control's own label
    ///     so the toast and the button never drift apart.
    ///   - icon: SF Symbol matching the control that was tapped.
    ///   - isOn: The state *after* the toggle; picks the tint.
    func showToggleToast(feature: String, icon: String, isOn: Bool) {
        let format = isOn ? String.stateToastOn : String.stateToastOff
        showStateToast(format.localized(feature), icon: icon, isOn: isOn)
    }

    /// Confirm an operation that is not an on/off pair — an aspect-ratio or
    /// capture-mode readout, for instance.
    func showNeutralToast(_ message: String, icon: String) {
        showStateToast(message, icon: icon, isOn: false)
    }

    /// Shared entry point for the short state confirmations.
    func showStateToast(_ message: String,
                        icon: String,
                        isOn: Bool,
                        accentColor: Color? = nil) {
        // Never talk over an error: a toggle confirmation is not worth losing
        // "out of storage" over.
        guard currentToast?.type != .error else { return }

        let tint = accentColor ?? (isOn ? StateToastStyle.on : StateToastStyle.neutral)
        showToast(type: .info,
                  message: message,
                  duration: Self.stateToastDuration,
                  customIcon: icon,
                  accentColor: tint)
    }

    /// Show a success message
    func showSuccess(_ message: String, customIcon: String? = nil) {
        showToast(type: .success, message: message, customIcon: customIcon)
    }

    /// Show an error message
    func showError(_ message: String, customIcon: String? = nil) {
        showToast(type: .error, message: message, customIcon: customIcon)
    }

    /// Show a warning message
    func showWarning(_ message: String, customIcon: String? = nil) {
        showToast(type: .warning, message: message, customIcon: customIcon)
    }

    /// Show an informational message
    func showInfo(_ message: String, customIcon: String? = nil) {
        showToast(type: .info, message: message, customIcon: customIcon)
    }
}
