import AuthenticationServices
import SwiftUI

// MARK: - design constants
private enum SettingsDesign {
    static let backgroundColor = Color(white: 0.04)
    static let cardColor = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255, opacity: 0.4)
    static let cardBorderColor = Color.white.opacity(0.08)
    static let cardCornerRadius: CGFloat = 24
    static let cardPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 32
    static let rowSpacing: CGFloat = 0
    static let iconSize: CGFloat = 28
    static let iconCornerRadius: CGFloat = 8
}

// MARK: - Icon color definition
private let settingsIconColor = Color.white.opacity(0.15)

// MARK: - Support links
//
// A-17: these were Day 1 Labs' own assets — a support mailbox, their X
// account, their Xiaohongshu, and their App Store listing (rating it would
// have rated *their* app). Shipping them inside this product would send our
// users to someone else's inbox, so every one of them is empty by default
// and the "支持" group hides itself until this product has real addresses.
//
// Fill these in when they exist; nothing else needs to change.
private enum SupportLinks {
    /// e.g. "support@yourdomain.com" — empty hides the row.
    static let contactEmail = ""
    /// The numeric App Store id of *this* app. Empty hides the row; the old
    /// upstream value would have sent users to a different app entirely.
    static let appStoreID = ""
    /// Full Xiaohongshu profile URL (Chinese users only).
    static let xiaohongshuURL = ""
    /// X / Twitter handle, without the "@".
    static let xAccount = ""

    static var contactURL: URL? {
        contactEmail.isEmpty ? nil : URL(string: "mailto:\(contactEmail)")
    }

    static var rateURL: URL? {
        appStoreID.isEmpty
            ? nil
            : URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")
    }

    static var xURL: URL? {
        xAccount.isEmpty ? nil : URL(string: "https://x.com/\(xAccount)")
    }

    static var resolvedXiaohongshuURL: URL? {
        xiaohongshuURL.isEmpty ? nil : URL(string: xiaohongshuURL)
    }
}

private struct SupportLink {
    let icon: String
    let title: String
    let url: URL
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsState: CameraSettingsState
    @StateObject private var authService = AuthService.shared
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var languageManager = LanguageManager.shared
    @AppStorage("isDeveloperMode") private var isDeveloperMode: Bool = false
    @State private var showDeleteAccountAlert = false
    @State private var showEditNameAlert = false
    @State private var editingName = ""
    @State private var showDebugPaywall = false

    /// The support rows that actually have somewhere to send the user.
    /// A-17: all four upstream (Day 1 Labs) links were removed, so today
    /// this is empty and the whole group is hidden. Rows appear as soon as
    /// `SupportLinks` gains a real address.
    private var supportLinks: [SupportLink] {
        var links: [SupportLink] = []
        if let url = SupportLinks.contactURL {
            links.append(SupportLink(icon: "envelope", title: String.settingsContactUs.localized, url: url))
        }
        if let url = SupportLinks.rateURL {
            links.append(SupportLink(icon: "star", title: String.settingsRateApp.localized, url: url))
        }
        if languageManager.currentLanguage.isChinese,
           let url = SupportLinks.resolvedXiaohongshuURL {
            links.append(SupportLink(icon: "text.book.closed", title: String.settingsFollowXiaohongshu.localized, url: url))
        }
        if let url = SupportLinks.xURL {
            links.append(SupportLink(icon: "xmark", title: String.settingsFollowX.localized, url: url))
        }
        return links
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground()

                ScrollView {
                    VStack(spacing: SettingsDesign.sectionSpacing) {
                        // MARK: - Account
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String.settingsGroupAccount.localized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.gray)
                                .padding(.leading, 4)

                            if authService.isLoggedIn {
                                UserProfileRow(user: authService.currentUser, onEditName: {
                                    editingName = authService.currentUser?.fullName ?? ""
                                    showEditNameAlert = true
                                }, onSignOut: {
                                    AnalyticsManager.shared.log(.settingsAction(action: "sign_out"))
                                    authService.signOut()
                                }, onDeleteAccount: {
                                    showDeleteAccountAlert = true
                                })
                                .glassCardStyle(cardColor: SettingsDesign.cardColor)
                            } else {
                                appleSignInButton
                            }
                        }

                        // MARK: - camera
                        SettingsSection(title: String.settingsGroupCamera.localized) {
                            SettingsNavigationRow(icon: "pencil", iconColor: settingsIconColor, title: String.cameraSettingsFileNaming.localized) { FileNamingSettingsView() }
                            SettingsDivider()
                            SettingsNavigationRow(icon: "waveform", iconColor: settingsIconColor, title: String.audioSettingsTitle.localized) { AudioSettingsView() }
                            SettingsDivider()
                            SettingsToggleRow(icon: "photo.on.rectangle", iconColor: settingsIconColor, title: String.cameraSettingsPreviewLatestPhoto.localized, isOn: $settingsState.previewLatestPhoto)
                            SettingsDivider()
                            SettingsToggleRow(icon: "rectangle.on.rectangle", iconColor: settingsIconColor, title: String.cameraSettingsSaveOriginal.localized, isOn: $settingsState.saveOriginalEnabled)
                            SettingsDivider()
                            SettingsToggleRow(icon: "square.stack.3d.up", iconColor: settingsIconColor, title: String.cameraSettingsAutomation.localized, isOn: $settingsState.automationEnabled)
                            SettingsDivider()
                            SettingsToggleRow(icon: "square.3.layers.3d.down.right", iconColor: settingsIconColor, title: "HDR", isOn: $settingsState.hdrEnabled)
                            SettingsDivider()
                            SettingsToggleRow(icon: "location.fill", iconColor: settingsIconColor, title: String.cameraSettingsSaveGps.localized, isOn: Binding(get: { settingsState.saveGPSEnabled }, set: { _ in settingsState.toggleGPSSetting() }))
                            SettingsDivider()
                            SettingsToggleRow(icon: "c.circle", iconColor: settingsIconColor, title: String.cameraSettingsCopyright.localized, isOn: $settingsState.copyrightEnabled)

                            if settingsState.copyrightEnabled {
                                SettingsDivider()
                                SettingsTextFieldRow(icon: "doc.text", iconColor: settingsIconColor, title: String.cameraSettingsCopyrightText.localized, text: $settingsState.copyrightText, placeholder: String.cameraSettingsCopyrightPlaceholder.localized)
                            }

                            SettingsDivider()
                            SettingsToggleRow(icon: "speaker.wave.2", iconColor: settingsIconColor, title: String.cameraSettingsVolumeButton.localized, isOn: $settingsState.volumeButtonCaptureEnabled)
                            SettingsDivider()
                            SettingsToggleRow(icon: "chart.bar.xaxis", iconColor: settingsIconColor, title: String.cameraSettingsHistogram.localized, isOn: $settingsState.histogramEnabled)
                        }

                        // MARK: - Universal
                        SettingsSection(title: String.settingsGroupGeneral.localized) {
                            SettingsPickerRow(icon: "globe", iconColor: settingsIconColor, title: String.settingsLanguage.localized, selection: Binding(get: { languageManager.currentLanguage.rawValue }, set: { if let l = Language(rawValue: $0) { AnalyticsManager.shared.log(.settingsAction(action: "change_language_\($0)")); languageManager.setLanguage(l) } }), options: Language.allCases.map { ($0.displayName, $0.rawValue) })
                            SettingsDivider()
                            SettingsNavigationRow(icon: "externaldrive", iconColor: settingsIconColor, title: String.settingsStorageManagement.localized) { StorageSettingsView() }
                            SettingsDivider()
                            SettingsNavigationRow(icon: "hand.raised", iconColor: settingsIconColor, title: String.permissionSettingsTitle.localized) { PermissionSettingsView() }
                        }

                        // MARK: - support
                        // A-17: these used to point at the upstream team's
                        // assets — support@day1-labs.com, Day 1 Labs' X
                        // account, their Xiaohongshu, and their App Store
                        // listing (rating `id6756349089` would have rated
                        // *their* app). None of them belong to this product,
                        // so the rows are now driven by `supportLinks` and the
                        // whole group is hidden until real addresses exist.
                        if !supportLinks.isEmpty {
                            SettingsSection(title: String.settingsGroupSupport.localized) {
                                ForEach(Array(supportLinks.enumerated()), id: \.offset) { index, link in
                                    if index > 0 {
                                        SettingsDivider()
                                    }
                                    SettingsLinkRow(icon: link.icon, iconColor: settingsIconColor, title: link.title, url: link.url)
                                }
                            }
                        }

                        // MARK: - about
                        SettingsSection(title: String.settingsGroupAbout.localized) {
                            SettingsNavigationRow(icon: "hand.raised", iconColor: settingsIconColor, title: String.settingsPrivacyPolicy.localized) { PrivacyPolicyView() }
                            SettingsDivider()
                            SettingsNavigationRow(icon: "doc.text", iconColor: settingsIconColor, title: String.settingsUserAgreement.localized) { UserAgreementView() }
                        }

                        // MARK: - Developer mode
                        if isDeveloperMode {
                            SettingsSection(title: String.settingsGroupDeveloper.localized) {
                                SettingsToggleRow(
                                    icon: "hammer.fill",
                                    iconColor: settingsIconColor,
                                    title: String.settingsDeveloperMode.localized,
                                    isOn: $isDeveloperMode
                                )

                                SettingsDivider()

                                Button {
                                    showDebugPaywall = true
                                } label: {
                                    SettingsRow(
                                        icon: "crown",
                                        iconColor: settingsIconColor,
                                        title: "Debug: Show Paywall"
                                    ) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.gray.opacity(0.6))
                                    }
                                }
                                .fullScreenCover(isPresented: $showDebugPaywall) {
                                    PaywallView()
                                }

                                if authService.isLoggedIn {
                                    SettingsDivider()
                                    SettingsToggleRow(
                                        icon: "crown.fill",
                                        iconColor: settingsIconColor,
                                        title: "Debug: Pro Status",
                                        isOn: Binding(
                                            get: { authService.currentUser?.subscriptionStatus == 1 },
                                            set: { authService.debugSetProStatus(isPro: $0) }
                                        )
                                    )
                                }

                                SettingsDivider()

                                SettingsNavigationRow(
                                    icon: "server.rack",
                                    iconColor: settingsIconColor,
                                    title: "服务地址",
                                    subtitle: ServiceEndpoints.shared.isCustomized ? "已自定义" : nil
                                ) { ServiceEndpointSettingsView() }

                                SettingsDivider()

                                SettingsNavigationRow(
                                    icon: "camera.filters",
                                    iconColor: settingsIconColor,
                                    title: "滤镜完整性自检",
                                    subtitle: "内置滤镜资源检查"
                                ) { FilterDiagnosticsSettingsView() }
                            }
                        }

                        // MARK: - Privacy & Data is temporarily offline.
                        // SettingsSection(title: String.settingsPrivacyAnalytics.localized) {
                        //     VStack(alignment: .leading, spacing: 12) {
                        //         Text(String.settingsPrivacyAnalyticsDescription.localized)
                        //             .font(.system(size: 13))
                        //             .foregroundStyle(.gray)
                        //             .padding(.horizontal, SettingsDesign.cardPadding)
                        //             .padding(.top, 12)

                        //         SettingsDivider()

                        //         SettingsToggleRow(
                        //             icon: "chart.bar",
                        //             iconColor: settingsIconColor,
                        //             title: String.settingsPrivacyDataCollection.localized,
                        //             isOn: Binding(
                        //                 get: { AnalyticsManager.shared.isAnalyticsEnabled },
                        //                 set: { newValue in
                        //                     AnalyticsManager.shared.isAnalyticsEnabled = newValue
                        //                     AnalyticsManager.shared.log(.settingsAction(action: "toggle_analytics_\(newValue)"))
                        //                 }
                        //             )
                        //         )
                        //     }
                        // }

                        AppFooterView().padding(.top, 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle(String.settingsTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if !authService.isLoggedIn || authService.currentUser?.subscriptionStatus != 1 {
                            AuthManager.shared.checkProAccess {
                                // No-op: showing the paywall is handled inside `checkProAccess`.
                            }
                        }
                    } label: {
                        if authService.currentUser?.subscriptionStatus == 1 {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .trackScreen(name: "Settings")
            .buttonStyle(.plain)
            .alert(String.settingsDeleteAccountConfirmTitle.localized, isPresented: $showDeleteAccountAlert) {
                Button(String.commonCancel.localized, role: .cancel) {}
                Button(String.commonDelete.localized, role: .destructive) {
                    Task {
                        try? await authService.deleteAccount()
                    }
                }
            } message: {
                Text(String.settingsDeleteAccountConfirmMessage.localized)
            }
            .alert(String.settingsEditName.localized, isPresented: $showEditNameAlert) {
                TextField(String.settingsEditNamePlaceholder.localized, text: Binding(
                    get: { editingName },
                    set: { editingName = String($0.prefix(30)) }
                ))
                Button(String.commonCancel.localized, role: .cancel) {}
                Button(String.settingsSave.localized) {
                    let name = editingName
                    Task {
                        do {
                            try await authService.updateName(name)
                        } catch {
                            debugLog("❌ Update name failed: \(error)")
                        }
                    }
                }
            }
            .task {
                await authService.fetchUserProfile()
            }
            .fullScreenCover(isPresented: $authManager.showAuthSheet) {
                UnifiedAuthSheet()
            }
        }
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton(
            onRequest: { $0.requestedScopes = [.fullName, .email] },
            onCompletion: { result in
                switch result {
                case let .success(authorization):
                    AnalyticsManager.shared.log(.settingsAction(action: "sign_in_success"))
                    Task { await authService.signInWithApple(authorization: authorization) }
                case let .failure(error):
                    AnalyticsManager.shared.log(.settingsAction(action: "sign_in_failed"))
                    debugLog("❌ Auth failed: \(error.localizedDescription)")
                }
            }
        )
        .signInWithAppleButtonStyle(.white)
        .frame(height: 48)
        .cornerRadius(12)
        .disabled(authService.isLoading)
        .overlay {
            if authService.isLoading { ProgressView().tint(.black) }
        }
    }
}

// MARK: - Common components
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            GlassCard(cardColor: SettingsDesign.cardColor, paddingValue: 0) {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.1))
            .padding(.leading, 52)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: SettingsDesign.iconSize, height: SettingsDesign.iconSize)
                .background(iconColor)
                .cornerRadius(SettingsDesign.iconCornerRadius)

            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.white)

            Spacer()

            trailing
        }
        .padding(.horizontal, SettingsDesign.cardPadding)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct SettingsNavigationRow<Destination: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String?
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRow(icon: icon, iconColor: iconColor, title: title) {
                HStack(spacing: 8) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(.gray)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.gray.opacity(0.6))
                }
            }
        }
    }
}

private struct SettingsLinkRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let url: URL?

    var body: some View {
        Button {
            if let url { UIApplication.shared.open(url) }
        } label: {
            SettingsRow(icon: icon, iconColor: iconColor, title: title) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.6))
            }
        }
    }
}

private struct SettingsPickerRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var selection: String
    let options: [(String, String)]

    var body: some View {
        Menu {
            ForEach(options, id: \.1) { option in
                Button {
                    selection = option.1
                } label: {
                    HStack {
                        Text(option.0)
                        if selection == option.1 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            SettingsRow(icon: icon, iconColor: iconColor, title: title) {
                HStack(spacing: 8) {
                    Text(options.first { $0.1 == selection }?.0 ?? "")
                        .font(.system(size: 15))
                        .foregroundStyle(.gray)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.gray.opacity(0.6))
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(icon: icon, iconColor: iconColor, title: title) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.accentColor)
        }
    }
}

private struct SettingsTextFieldRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: SettingsDesign.iconSize, height: SettingsDesign.iconSize)
                    .background(iconColor)
                    .cornerRadius(SettingsDesign.iconCornerRadius)

                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }

            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .padding(.leading, 40)
        }
        .padding(.horizontal, SettingsDesign.cardPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - App Footer Component
private struct AppFooterView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                sloganView

                Text("v\(appVersion) · Crafted by Day1 Labs")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var sloganView: some View {
        "Your Outlook, Your Output".reduce(Text("")) { result, char in
            result + Text(String(char))
                .fontWeight(char.isUppercase ? .bold : .regular)
                .foregroundColor(.white.opacity(char.isUppercase ? 0.9 : 0.4))
        }
        .font(.system(size: 13, design: .monospaced))
        .italic()
    }
}

// MARK: - User information component
private struct UserProfileRow: View {
    let user: User?
    let onEditName: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void
    @AppStorage("isDeveloperMode") private var isDeveloperMode: Bool = false
    @State private var tapCount = 0
    @State private var lastTapTime = Date.distantPast
    @State private var showPaywall = false

    private var isPro: Bool {
        user?.subscriptionStatus == 1
    }

    private var credits: Int {
        user?.credits ?? 0
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(settingsIconColor)
                    .frame(width: 44, height: 44)
                Image(systemName: isPro ? "crown.fill" : "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isPro ? Color.accentColor : .white.opacity(0.2))
            }

            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 0) {
                    Text(user?.fullName ?? "Apple User")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .fixedSize()
                }
                .contentShape(Rectangle())
                .onTapGesture { handleTap() }

                if user != nil {
                    HStack(spacing: 4) {
                        Image(systemName: isPro ? "star.circle.fill" : "lock.circle")
                            .font(.system(size: 12))
                        Text("\(credits)")
                            .fixedSize()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isPro ? Color.white : Color.gray)
                }
            }

            Spacer()

            if !isPro {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11))
                        Text(String.paywallTitle.localized)
                            .font(.system(size: 13, weight: .semibold))
                            .fixedSize()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.25), lineWidth: 1)
                    )
                }
                .fullScreenCover(isPresented: $showPaywall) {
                    PaywallView()
                }
            }

            Menu {
                Button(action: onEditName) {
                    Label(String.settingsEditName.localized, systemImage: "pencil")
                }

                Button(action: onSignOut) {
                    Label(String.settingsAppleLogout.localized, systemImage: "rectangle.portrait.and.arrow.right")
                }

                Button(role: .destructive, action: onDeleteAccount) {
                    Label(String.settingsDeleteAccount.localized, systemImage: "person.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundStyle(.gray)
                    .padding(8)
            }
        }
        .padding(.horizontal, SettingsDesign.cardPadding)
        .padding(.vertical, 12)
    }

    private func handleTap() {
        let now = Date()
        tapCount = now.timeIntervalSince(lastTapTime) > 1.0 ? 1 : tapCount + 1
        lastTapTime = now

        if tapCount >= 5 {
            isDeveloperMode.toggle()
            tapCount = 0
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

private struct AtmosphericBackground: View {
    var body: some View {
        ZStack {
            SettingsDesign.backgroundColor.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(white: 0.12),
                    SettingsDesign.backgroundColor,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CameraSettingsState.shared)
}
