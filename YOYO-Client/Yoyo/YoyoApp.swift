import SwiftData
import SwiftUI
import UIKit

enum AppConfig {
    static let isDebugMode = false
}

@main
struct YoyoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var permissionManager = PermissionManager.shared
    @StateObject var languageManager = LanguageManager.shared
    @StateObject var authManager = AuthManager.shared

    /// SwiftData 容器只建一次。打不开时降级为内存库而不是崩，见 `StorageBootstrap`。
    private let storage = StorageBootstrap.make()

    /// 降级提示每个进程只弹一次；语言切换会重建视图树，`onAppear` 会再触发。
    @State private var hasShownStorageDegradeAlert = false
    @State private var showsStorageDegradeAlert = false

    var body: some Scene {
        WindowGroup {
            Group {
                if permissionManager.needsOnboarding {
                    OnboardingView {
                        // It will hide automatically after onboarding is completed
                    }
                } else {
                    CameraView()
                        .buttonStyle(.plain)
                        .trackScreen(name: "CameraMain")
                        .onOpenURL { url in
                            handleURL(url: url)
                        }
                        // 注意：不要把这个 alert 挂在下面那个 Group 上。
                        // `permissionAlert()` 内部已经是一个 `.alert`，同一视图上叠两个
                        // alert 时 SwiftUI 只保证最后一个生效，会吞掉权限提示。
                        .alert(
                            String.storageDegradedTitle.localized,
                            isPresented: $showsStorageDegradeAlert
                        ) {
                            Button(String.commonOk.localized, role: .cancel) {}
                        } message: {
                            Text(String.storageDegradedMessage.localized)
                        }
                        .onAppear {
                            presentStorageDegradeNoticeIfNeeded()
                        }
                        // 首次启动时权限弹窗会先出来，同一时刻 SwiftUI 只允许一个
                        // alert，存储提示会被直接挤掉且不会补弹。等它关掉再来。
                        .onChange(of: permissionManager.pendingPermissionAlert) { pending in
                            guard pending == nil else { return }
                            presentStorageDegradeNoticeIfNeeded()
                        }
                }
            }
            .permissionAlert()
            .environmentObject(permissionManager)
            .environmentObject(languageManager)
            .environment(\.locale, languageManager.locale)
            .id(languageManager.uuid)
            .animation(.easeInOut(duration: 0.3), value: permissionManager.needsOnboarding)
            .fullScreenCover(isPresented: $authManager.showAuthSheet) {
                UnifiedAuthSheet()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task {
                        await AuthService.shared.fetchUserProfile()
                    }
                }
            }
        }
        .modelContainer(storage.container)
    }

    /// 提示「本次运行使用内存库」。
    ///
    /// 只在没有权限弹窗时弹：同一时刻 SwiftUI 只能呈现一个 alert，权限弹窗
    /// 在首次启动时必定先出现，会把这条提示挤掉，且关掉后不会自动补弹——
    /// 用户就永远不知道索引没在保存。
    ///
    /// 每个进程只提示一次。降级是进程级状态，运行期间不会变；语言切换会重建
    /// 视图树并再次触发 `onAppear`，靠这个标记挡住重复弹窗。
    private func presentStorageDegradeNoticeIfNeeded() {
        guard storage.isDegraded, !hasShownStorageDegradeAlert else { return }
        guard permissionManager.pendingPermissionAlert == nil else { return }
        hasShownStorageDegradeAlert = true
        showsStorageDegradeAlert = true
    }

    private func handleURL(url: URL) {
        // Record the app launch event triggered by a URL
        AnalyticsManager.shared.log(.appOpenURL(host: url.host ?? "none", path: url.path))

        // Handle URL-based launch
        if url.absoluteString.contains("quick-capture") {
            // Open the camera screen directly; it is already the default screen
        }
    }
}
