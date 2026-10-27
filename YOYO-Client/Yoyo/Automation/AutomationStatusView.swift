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
        // The off state is dimmed here rather than removed, so the view stays
        // coherent on its own. The top bar no longer renders it while
        // automation is off (see `CameraView.topMenuBar`), so this only covers
        // the frame in which a long-press toggles automation off.
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

    /// Icon name. UX-07: this is the badge from the original build —
    /// `square.stack.3d.up` reads as "stacked rules", which is what the
    /// feature does; the slashed variant carries the off state on top of the
    /// 60% opacity the whole control already gets.
    ///
    /// An earlier pass of this fix replaced both with `crown.fill`. That was
    /// wrong twice over: the crown means "Pro subscriber" everywhere else in
    /// the app (SettingsView, PaywallView, the drawer's upgrade row), so it
    /// advertised the automation trigger as a paywall entry, and it dropped
    /// the only visual difference between on and off.
    ///
    /// Both names are verified present in the iOS 18.3 CoreGlyphs catalogue
    /// (introduced in 2019, i.e. iOS 13). Check before swapping in something
    /// unfamiliar: an unknown SF Symbol name does not fail the build, it
    /// renders as an empty glyph.
    private var iconName: String {
        isAutomationEnabled
            ? "square.stack.3d.up.fill"
            : "square.stack.3d.up.slash.fill"
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
