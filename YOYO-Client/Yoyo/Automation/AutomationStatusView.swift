import Foundation
import SwiftUI

struct AutomationStatusView: View {
    @ObservedObject var automationManager: CameraAutomationManager
    @ObservedObject var settingsState: CameraSettingsState
    @Binding var showHistory: Bool
    @Binding var showSettings: Bool

    private var enabledRules: [AutomationRule] {
        automationManager.ruleStore.rules.filter(\.isEnabled)
    }

    private var enabledCount: Int {
        enabledRules.count
    }

    /// Read directly from settingsState to ensure reactive updates
    private var isAutomationEnabled: Bool {
        settingsState.automationEnabled
    }

    var body: some View {
        HStack(spacing: 4) {
            statusIconView

            if enabledCount > 0 {
                Text("\(enabledCount)")
                    // UX-11: was pinned at 10pt; semantic so it follows the
                    // reader's text size (top bar caps at xxxLarge).
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(textColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // UX-07: dim the icon when automation is off so the user can still
        // see and tap it (to re-enable via the management page) without
        // thinking the feature is gone.
        .opacity(isAutomationEnabled ? 1.0 : 0.6)
        // UX-22: a single tap no longer toggles automation in place — that
        // was easy to do by accident. Tap opens the management sheet where
        // the user can decide deliberately. The long-press shortcut is
        // preserved for power users.
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSettings = true
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            settingsState.automationEnabled.toggle()
            // Reuse the settings label ("Task Master") rather than inventing a
            // second name for the same feature.
            CameraViewState.shared.showToggleToast(
                feature: String.cameraSettingsAutomation.localized,
                icon: iconName,
                isOn: isAutomationEnabled
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String.cameraSettingsAutomation.localized))
        .accessibilityValue(Text(isAutomationEnabled
            ? String.automationStatusOn.localized
            : String.automationStatusOff.localized))
        .accessibilityHint(Text(String.automationStatusAccessibilityHint.localized))
    }

    /// Status icon view
    private var statusIconView: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(iconColor)
    }

    /// Icon name. UX-07 / UX-22: identical in both states. The off state is
    /// carried by the 60% opacity applied to the whole control (i.e. the
    /// "grey icon" the review asked for), plus the accessibility value and
    /// the icon's role in the top bar. A slashed variant would need an
    /// SF Symbol name that isn't guaranteed to exist — an unknown name
    /// renders as a blank glyph, which is strictly worse than a dim one.
    private var iconName: String {
        "crown.fill"
    }

    /// Icon color
    private var iconColor: Color {
        .white
    }

    /// Text color
    private var textColor: Color {
        .white
    }
}

#Preview {
    let settingsState = CameraSettingsState.shared
    let automationManager = CameraAutomationManager.shared

    return AutomationStatusView(
        automationManager: automationManager,
        settingsState: settingsState,
        showHistory: .constant(false),
        showSettings: .constant(false)
    )
    .background(Color.black)
}
