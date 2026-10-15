import Photos
import SwiftData
import SwiftUI

struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isUIPreview) private var isUIPreview
    @EnvironmentObject var permissionManager: PermissionManager

    let initialCaptureMode: CameraCaptureMode?

    init(initialCaptureMode: CameraCaptureMode? = nil) {
        self.initialCaptureMode = initialCaptureMode
    }

    // MARK: - Core State

    @StateObject private var cameraManagers = CameraManagersContainer()
    @ObservedObject private var tutorialManager = TutorialManager.shared
    @State private var showAutomationHistory = false
    @State private var isDrawerExpanded = false
    @State private var latestPhoto: PhotoAsset?
    @State private var latestPhotoRefreshTask: Task<Void, Never>?
    /// Asset identifiers the app deleted during this session. A deleted asset keeps
    /// answering `PHAsset` fetches while it sits in "Recently Deleted", so an
    /// existence check alone can hand the removed photo straight back.
    @State private var recentlyDeletedAssetIdentifiers: Set<String> = []
    @State private var isCoordinatorReady = false
    @State private var showCameraGestureTutorial = false

    private var automationSettingsBinding: Binding<Bool> {
        Binding(
            get: { cameraManagers.viewState.showingAutomationSettings },
            set: { cameraManagers.viewState.showingAutomationSettings = $0 }
        )
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                mainContentArea
                topMenuBar(geometry: geometry)
            }
        }
        .preferredColorScheme(.dark)
        .overlay(overlayViews, alignment: .bottom)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear(perform: handleViewAppear)
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
        ) { _ in
            cameraManagers.handleEnterBackground()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            cameraManagers.handleEnterForeground()
            requestLatestPhotoRefresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            // On cold launch `willEnterForeground` never fires, so the `.task` refresh is the only
            // attempt and it can permanently give up while the app is still `.inactive` (the Photos
            // existence checks are unreliable before activation). Retry once we are truly active.
            if latestPhoto == nil { requestLatestPhotoRefresh() }
        }
        .fullScreenCover(isPresented: $cameraManagers.viewState.showingPhotoGallery) {
            photoGalleryView
        }
        .fullScreenCover(isPresented: automationSettingsBinding) {
            AutomationSettingsView(
                isPresented: automationSettingsBinding,
                cameraSettings: cameraManagers.settingsState,
                automationManager: cameraManagers.automationManager
            )
            .environmentObject(permissionManager)
        }
        .fullScreenCover(isPresented: $cameraManagers.viewState.showingSettings) {
            SettingsView()
                .environmentObject(cameraManagers.settingsState)
                .environmentObject(permissionManager)
        }
        .sheet(isPresented: $isDrawerExpanded) {
            CameraDrawer(
                isExpanded: $isDrawerExpanded,
                focusManager: cameraManagers.focusManager,
                exposureManager: cameraManagers.exposureManager,
                automationManager: cameraManagers.automationManager,
                viewState: cameraManagers.viewState,
                settingsState: cameraManagers.settingsState
            )
            .presentationDetents([.height(CameraLayoutConfig.drawerSheetHeight)])
            .presentationDragIndicator(.visible)
        }
        .permissionAlert()
        .modifier(
            CameraStateObserver(
                cameraManagers: cameraManagers, permissionManager: permissionManager,
                showAutomationSettings: automationSettingsBinding
            )
        )
        .onChange(of: cameraManagers.settingsState.effectiveAspectRatio) { _, new in
            cameraManagers.captureService.updatePhotoProcessorAspectRatio(new)
        }
        .onChange(of: isCoordinatorReady) { _, isReady in
            handleCoordinatorAvailability(isReady)
        }
        .onChange(of: permissionManager.hasCameraPermission) { _, hasPermission in
            if hasPermission { cameraManagers.startCamera() }
        }
        .onChange(of: cameraManagers.viewState.showingPhotoGallery) { _, isShowing in
            if !isShowing { requestLatestPhotoRefresh() }
        }
        .onChange(of: permissionManager.hasPhotoLibraryPermission) { _, _ in
            requestLatestPhotoRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraSaveFinished)) { notification in
            if notification.userInfo?[CameraNotificationKeys.saveSuccess] as? Bool == true {
                requestLatestPhotoRefresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .photoLibraryDidChange)) { _ in
            // Covers deletions from the in-app gallery and from the system Photos
            // app alike. `requestLatestPhotoRefresh` cancels any in-flight refresh,
            // which is all the debouncing a burst of library changes needs.
            requestLatestPhotoRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraDidDeleteAssets)) { notification in
            let identifiers = Set(
                notification.userInfo?[CameraNotificationKeys.assetIdentifiers] as? [String] ?? []
            )
            guard !identifiers.isEmpty else { return }

            // Remember them for the rest of the session: while a deleted asset is
            // still in "Recently Deleted" the photo library answers existence
            // checks with "yes", so a later refresh must not pick it up again.
            recentlyDeletedAssetIdentifiers.formUnion(identifiers)

            // When the button is showing exactly the photo that just went away, drop
            // it straight away. Re-resolving usually lands on the previous photo,
            // and clearing first guarantees the stale frame cannot survive.
            if let shown = latestPhoto, isDeletedThisSession(shown) {
                latestPhoto = nil
            }

            requestLatestPhotoRefresh()
        }
        .onReceive(FilterManager.shared.$selectedFilter.dropFirst()) { newFilter in
            let toastContent = FilterManager.shared.makeFilterSwitchToastContent(for: newFilter)
            cameraManagers.viewState.showInfo(toastContent.message, customIcon: toastContent.icon)
        }
        .task { requestLatestPhotoRefresh() }
    }

    @ViewBuilder
    private var photoGalleryView: some View {
        let initialPhotos: [PhotoAsset] = {
            guard let latestPhoto, permissionManager.hasPhotoLibraryPermission else { return [] }
            let fetchResult = PHAsset.fetchAssets(
                withLocalIdentifiers: [latestPhoto.assetIdentifier], options: nil
            )
            return fetchResult.firstObject == nil ? [] : [latestPhoto]
        }()
        PhotoGalleryView(
            autoPreviewLatest: cameraManagers.settingsState.previewLatestPhoto,
            initialPhotos: initialPhotos
        )
        .environmentObject(permissionManager)
    }

    // MARK: - View Builders

    @ViewBuilder
    private var mainContentArea: some View {
        ZStack {
            GeometryReader { geometry in
                CameraPreviewContainerView(
                    geometry: geometry,
                    viewState: cameraManagers.viewState,
                    settingsState: cameraManagers.settingsState,
                    cameraManagers: cameraManagers,
                    automationManager: cameraManagers.automationManager,
                    isParameterDrawerExpanded: isDrawerExpanded,
                    onCoordinatorCreated: { _ in
                        isCoordinatorReady = true
                    }
                )
            }
            .animation(
                .spring(response: 0.3, dampingFraction: 0.8),
                value: cameraManagers.viewState.showingFilterGallery
            )

            VStack(spacing: 0) {
                Spacer()

                bottomControls
            }
            .animation(
                .spring(response: 0.3, dampingFraction: 0.8),
                value: cameraManagers.viewState.showingFilterGallery
            )
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        if cameraManagers.viewState.showingFilterGallery {
            FilterGalleryView(
                isPresented: $cameraManagers.viewState.showingFilterGallery,
                latestPhoto: latestPhoto,
                viewState: cameraManagers.viewState,
                settingsState: cameraManagers.settingsState,
                onShutterAction: { cameraManagers.captureService.triggerShutterAction() }
            )
            .transition(bottomTransition)
        } else {
            CameraControlView(
                latestPhoto: latestPhoto,
                managers: cameraManagers,
                isDrawerExpanded: $isDrawerExpanded
            )
            .transition(controlTransition)
        }
    }

    @ViewBuilder
    private func topMenuBar(geometry: GeometryProxy) -> some View {
        HStack {
            // UX-07: always show `AutomationStatusView` so the user can find
            // their way back to enabling automation. When automation is off
            // the view itself renders a dimmed crown-slash icon at 0.6
            // opacity (see `AutomationStatusView`).
            AutomationStatusView(
                automationManager: cameraManagers.automationManager,
                settingsState: cameraManagers.settingsState,
                showHistory: $showAutomationHistory,
                showSettings: automationSettingsBinding
            )
            .overlay(alignment: .topLeading) {
                // Confirmation bubble shown below `AutomationStatusView`
                if let pending = cameraManagers.automationManager.pendingConfirmation {
                    AutomationConfirmationBubble(
                        pending: pending,
                        onConfirm: { cameraManagers.automationManager.confirmPendingRules() },
                        onDismiss: { cameraManagers.automationManager.dismissPendingRules() }
                    )
                    .offset(y: 40)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity),
                            removal: .scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity)
                        ))
                }
            }
            .animation(
                .spring(response: 0.3, dampingFraction: 0.7),
                value: cameraManagers.automationManager.pendingConfirmation?.id
            )

            AudioStatusView(
                audioManager: cameraManagers.audioManager,
                captureMode: cameraManagers.settingsState.currentCaptureMode,
                hasMicrophonePermission: permissionManager.hasMicrophonePermission
            )

            Spacer()

            if cameraManagers.settingsState.histogramEnabled {
                HistogramHost(previewRenderController: cameraManagers.previewRenderController)
                    .frame(width: 60, height: 32)
                    .transition(.opacity)
            }

            CameraControlPanel(
                settingsState: cameraManagers.settingsState,
                viewState: cameraManagers.viewState,
                sessionManager: cameraManagers.sessionManager,
                automationManager: cameraManagers.automationManager,
                orientationManager: cameraManagers.orientationManager
            )
        }
        .padding(.horizontal, 16)
        // Bottom-align the row inside the reserved band so it lands just
        // below the Dynamic Island (island bottom ≈ 48pt → row bottom 88pt).
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .frame(height: CameraLayoutConfig.topMenuHeight, alignment: .bottom)
        .position(
            x: geometry.size.width / 2,
            y: CameraLayoutConfig.topMenuHeight / 2
        )
    }

    @ViewBuilder
    private var overlayViews: some View {
        if showAutomationHistory {
            AutomationHistoryOverlay(
                automationManager: cameraManagers.automationManager,
                isPresented: $showAutomationHistory
            )
        }

        // Camera gesture tutorial
        if showCameraGestureTutorial {
            CameraGestureTutorialView(isPresented: $showCameraGestureTutorial)
                .transition(.opacity)
        }
    }

    // MARK: - Transitions

    private var bottomTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).combined(
                with: .scale(scale: 0.95, anchor: .bottom)),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    private var controlTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)),
            removal: .opacity
        )
    }

    // MARK: - Event Handlers

    private func handleViewAppear() {
        debugLog("📱 [CameraView] handleViewAppear - View appeared")
        guard !isUIPreview else {
            debugLog("📱 [CameraView] handleViewAppear - isUIPreview=true, skipping")
            return
        }

        // Apply the initial capture mode
        if let shortcutMode = ShortcutItemHandler.shared.consumeCaptureMode() {
            debugLog("📱 [CameraView] handleViewAppear - applying shortcutMode: \(shortcutMode.rawValue)")
            cameraManagers.settingsState.setCaptureMode(shortcutMode)
        } else if let initialMode = initialCaptureMode {
            debugLog("📱 [CameraView] handleViewAppear - applying initialMode: \(initialMode.rawValue)")
            cameraManagers.settingsState.setCaptureMode(initialMode)
        }

        // Initialize services
        debugLog("📱 [CameraView] handleViewAppear - Setting up CameraSaveService")
        CameraSaveService.shared.setup(
            modelContext: modelContext
        )

        // Core permissions: camera and photo library (required)
        debugLog("📱 [CameraView] handleViewAppear - Checking permissions")
        permissionManager.checkCameraPermission()
        permissionManager.checkPhotoLibraryPermission()

        // Only start the camera when permission is granted to avoid crashes when access is denied
        if permissionManager.hasCameraPermission {
            debugLog("📱 [CameraView] handleViewAppear - Camera permission granted, starting camera")
            cameraManagers.startCamera()

            // Show the camera gesture tutorial on first launch
            if !tutorialManager.hasShownCameraGestureTutorial {
                debugLog("📱 [CameraView] handleViewAppear - Scheduling tutorial")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showCameraGestureTutorial = true
                }
            }
        } else {
            debugLog("📱 [CameraView] handleViewAppear - No camera permission yet")
        }
        setupVolumeButtonCapture()
    }

    // MARK: - Capture Logic

    private func requestLatestPhotoRefresh() {
        latestPhotoRefreshTask?.cancel()
        latestPhotoRefreshTask = Task {
            await updateLatestPhoto()
        }
    }

    private func updateLatestPhoto() async {
        guard !isUIPreview, permissionManager.hasPhotoLibraryPermission else {
            await MainActor.run {
                latestPhotoRefreshTask = nil
                latestPhoto = nil
            }
            return
        }

        // The Photos framework may not be fully initialized on cold launch, so retry with increasing delays
        let retryDelays: [UInt64] = [0, 500_000_000, 1_000_000_000, 2_000_000_000, 3_000_000_000]
        for delay in retryDelays {
            if Task.isCancelled {
                await MainActor.run { latestPhotoRefreshTask = nil }
                return
            }
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            if Task.isCancelled {
                await MainActor.run { latestPhotoRefreshTask = nil }
                return
            }
            // Removed the strict `applicationState` check so data can load while the app is not yet active, such as during launch
            // if UIApplication.shared.applicationState != .active {
            //     continue
            // }
            if let result = await loadLatestPhotoFromLibrary() {
                await MainActor.run {
                    latestPhotoRefreshTask = nil
                    latestPhoto = result
                }
                return
            }
        }

        // Every retry failed. That is usually transient — assets are briefly
        // unavailable during launch or right after a save — so an existing
        // thumbnail is deliberately left alone. But when what we are showing has
        // itself been deleted, keeping it on screen is simply wrong: clear it so
        // the empty state appears instead of a photo the user just removed.
        let shown = await MainActor.run { latestPhoto }
        await MainActor.run { latestPhotoRefreshTask = nil }
        if let shown {
            // "Still fetchable" is not "the user still has it": a photo deleted from
            // the system Photos app keeps that answer true for 30 days. Both
            // questions have to be asked before the thumbnail is kept or cleared.
            let stillExists = await PhotoLoader.shared.assetExistsAsync(shown.assetIdentifier)
            let removedFromLibrary = await PhotoAlbumManager.shared.identifiersRemovedFromLibrary(
                among: [shown.assetIdentifier]
            )
            let deletedOutsideApp = removedFromLibrary?.contains(shown.assetIdentifier) ?? false
            if !stillExists || deletedOutsideApp {
                await MainActor.run { latestPhoto = nil }
            }
        }
    }

    private func loadLatestPhotoFromLibrary() async -> PhotoAsset? {
        // Removed the strict `applicationState` check so data can load while the app is not yet active, such as during launch
        // if UIApplication.shared.applicationState != .active {
        //     return nil
        // }

        let candidates: [PhotoAsset] = await MainActor.run {
            var descriptor = FetchDescriptor<PhotoAsset>(sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
            ])
            descriptor.fetchLimit = 50
            return (try? modelContext.fetch(descriptor)) ?? []
        }

        // A photo deleted from the system Photos app leaves the camera roll but keeps
        // answering existence checks while it sits in "Recently Deleted" — which is
        // exactly how the removed photo stayed on the thumbnail. What the app deleted
        // itself wins, and so does what the camera roll reports.
        let removedFromLibrary = await PhotoAlbumManager.shared.identifiersRemovedFromLibrary(
            among: candidates.map(\.assetIdentifier)
        )
        let usableCandidates = candidates.filter { candidate in
            guard !isDeletedThisSession(candidate) else { return false }
            guard let removedFromLibrary else { return true }
            return !isExcluded(candidate, by: removedFromLibrary)
        }
        guard let firstCandidate = usableCandidates.first else { return nil }

        // Validate the latest photo first
        let firstExists = await Task.detached(priority: .userInitiated) {
            PHAsset.fetchAssets(withLocalIdentifiers: [firstCandidate.assetIdentifier], options: nil)
                .count > 0
        }.value
        if firstExists { return firstCandidate }

        // If the latest photo is missing, batch-query candidates and return the first existing one
        let identifiers = usableCandidates.map(\.assetIdentifier)
        let existing = await PhotoAlbumManager.shared.existingAssetIdentifiers(for: identifiers)

        guard existing.isReliable else { return nil }
        return usableCandidates.first { existing.existing.contains($0.assetIdentifier) }
    }

    /// Whether either identifier the app tracks for this photo — the asset itself
    /// and the original of a Live Photo — appears in `identifiers`.
    private func isExcluded(_ photo: PhotoAsset, by identifiers: Set<String>) -> Bool {
        if identifiers.contains(photo.assetIdentifier) { return true }
        guard let originalIdentifier = photo.originalAssetIdentifier else { return false }
        return identifiers.contains(originalIdentifier)
    }

    /// Whether the app deleted this photo during this session. Deleted assets remain
    /// visible to `PHAsset` fetches while they sit in "Recently Deleted", so an
    /// existence check is not enough on its own.
    private func isDeletedThisSession(_ photo: PhotoAsset) -> Bool {
        isExcluded(photo, by: recentlyDeletedAssetIdentifiers)
    }

    private func handleCoordinatorAvailability(_ isReady: Bool) {
        guard isReady else { return }
        if cameraManagers.settingsState.isCaptureSessionActive {
            cameraManagers.sessionManager.startSession()
        } else {
            cameraManagers.sessionManager.stopSession()
        }
    }

    private func setupVolumeButtonCapture() {
        cameraManagers.volumeButtonManager.onVolumeButtonPressed = {
            Task { @MainActor in
                // Use `CaptureService` to handle shutter triggers consistently
                cameraManagers.captureService.triggerShutterAction()
            }
        }
    }
}

// MARK: - Camera State Observer

private struct CameraStateObserver: ViewModifier {
    @ObservedObject var cameraManagers: CameraManagersContainer
    @ObservedObject var permissionManager: PermissionManager
    @Binding var showAutomationSettings: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: cameraManagers.viewState.showingPhotoGallery) { _, new in
                handleFullScreenCoverChange(isShowing: new)
            }
            .onChange(of: cameraManagers.viewState.showingSettings) { _, new in
                handleFullScreenCoverChange(isShowing: new)
            }
            .onChange(of: showAutomationSettings) { _, new in handleFullScreenCoverChange(isShowing: new)
            }
            .onChange(of: cameraManagers.settingsState.currentCaptureMode) { _, new in
                if new == .movie { permissionManager.checkMicrophonePermission() }
            }
            .onChange(of: permissionManager.hasLocationPermission) { _, new in
                if new { cameraManagers.settingsState.onLocationPermissionGranted() }
            }
            .onChange(of: permissionManager.hasMicrophonePermission) { _, new in
                if new { cameraManagers.sessionManager.reconfigureAudioInput() }
            }
            .onChange(of: cameraManagers.settingsState.volumeButtonCaptureEnabled) { _, new in
                new
                    ? cameraManagers.volumeButtonManager.startMonitoring()
                    : cameraManagers.volumeButtonManager.stopMonitoring()
            }
            .onChange(of: cameraManagers.settingsState.saveGPSEnabled) { _, new in
                new
                    ? cameraManagers.locationManager.startMonitoring()
                    : cameraManagers.locationManager.stopMonitoring()
            }
            .onChange(of: cameraManagers.settingsState.isCaptureSessionActive) { old, new in
                if new, !old {
                    if cameraManagers.automationManager.automationEngine.rules.contains(where: \.isEnabled) {
                        cameraManagers.automationManager.activateAutomation()
                    }
                } else if !new, old {
                    cameraManagers.automationManager.deactivateAutomation()
                }
            }
            .onChange(of: cameraManagers.settingsState.automationEnabled) { _, new in
                new
                    ? cameraManagers.automationManager.activateAutomation()
                    : cameraManagers.automationManager.deactivateAutomation()
                AnalyticsManager.shared.log(.automationToggle(isOn: new))
            }
    }

    private func handleFullScreenCoverChange(isShowing: Bool) {
        if isShowing {
            cameraManagers.stopCamera()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // The delayed block may fire right after returning from background; in that case
                // starting the session would be interrupted immediately, and `handleEnterForeground`
                // is responsible for restarting the camera instead
                guard UIApplication.shared.applicationState != .background else { return }
                let allCoversClosed =
                    !cameraManagers.viewState.showingPhotoGallery
                        && !cameraManagers.viewState.showingSettings
                        && !showAutomationSettings
                if allCoversClosed { cameraManagers.startCamera() }
            }
        }
    }
}

#Preview {
    let permissionManager = PermissionManager.shared
    permissionManager.cameraStatus = .authorized

    return CameraView(initialCaptureMode: .photo)
        .environmentObject(permissionManager)
        .modelContainer(for: PhotoAsset.self, inMemory: true)
        .environment(\.isUIPreview, true)
}
