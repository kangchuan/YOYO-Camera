import Photos
import SwiftData
import SwiftUI
import UIKit

struct AIDarkroomPanelView: View {
    @Binding var showingAIPanel: Bool
    @Binding var isProcessingAI: Bool
    @Binding var isSaved: Bool
    @Binding var currentIndex: Int
    @Binding var localPhotos: [PhotoAsset]

    let photo: PhotoAsset?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var permissionManager: PermissionManager
    @ObservedObject private var authService = AuthService.shared

    /// Surfaced failure state. Set to a non-nil value to show the alert;
    /// the alert's "Retry" re-runs the same operation, "OK" dismisses.
    @State private var errorMessage: String?

    /// Cached so "Retry" can re-run the same operation without forcing
    /// the user to tap the same feature tile again.
    @State private var lastFailedOperation: AIDarkroomOperation?

    /// Operation in flight for the loading overlay / double-tap guard.
    @State private var pendingOperation: AIDarkroomOperation?

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text(String.aiDarkroomTitle.localized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                // Credits
                HStack(spacing: 4) {
                    Image(systemName: "star.circle")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    Text("\(authService.currentUser?.credits ?? 0)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

                // Per-feature cost badge: "消耗 N 积分" (UX-04)
                HStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text(String.aiDarkroomCostHint.localized(CreditCost.aiDarkroom))
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)

                Spacer()

                Button(action: {
                    performHaptic()
                    withAnimation {
                        showingAIPanel = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 4)

            // Insufficient credits banner (UX-04): shown in the panel itself
            // so the user sees *why* every feature is disabled.
            if !CreditCost.hasEnoughCredits(current: authService.currentUser?.credits, cost: CreditCost.aiDarkroom) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(String.aiDarkroomInsufficientCreditsHint.localized)
                        .font(.caption2)
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            // Features List
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                    aiFeatureButton(icon: "face.smiling", title: String.aiDarkroomPortraitEnhance.localized, operation: .portraitEnhance)
                    aiFeatureButton(icon: "sparkles.rectangle.stack", title: String.aiDarkroomBlurRepair.localized, operation: .blurRepair)
                    aiFeatureButton(icon: "eraser", title: String.aiDarkroomRemoveObjects.localized, operation: .removeObjects)
                    aiFeatureButton(icon: "eye", title: String.aiDarkroomFixClosedEyes.localized, operation: .fixClosedEyes)
                    aiFeatureButton(icon: "person.crop.rectangle", title: String.aiDarkroomIdPhoto.localized, operation: .idPhoto)
                    aiFeatureButton(icon: "briefcase", title: String.aiDarkroomProfessionalPhoto.localized, operation: .professionalPhoto)
                    aiFeatureButton(icon: "person.circle", title: String.aiDarkroomSocialAvatar.localized, operation: .socialAvatar)
                    aiFeatureButton(icon: "paintpalette", title: String.aiDarkroomColorGrading.localized, operation: .colorGrading)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 190)
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 24)
        // UX-03: surface failures to the user with a retry affordance.
        .alert(
            String.aiDarkroomFailureTitle.localized,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button(String.aiDarkroomRetry.localized) {
                if let op = lastFailedOperation {
                    errorMessage = nil
                    lastFailedOperation = nil
                    attempt(operation: op)
                }
            }
            Button(String.commonOk.localized, role: .cancel) {
                errorMessage = nil
                lastFailedOperation = nil
            }
        } message: { msg in
            Text(msg)
        }
    }

    private func aiFeatureButton(icon: String, title: String, operation: AIDarkroomOperation) -> some View {
        let hasCredits = CreditCost.hasEnoughCredits(current: authService.currentUser?.credits, cost: CreditCost.aiDarkroom)
        return Button(action: {
            performHaptic()
            // UX-04: gate the click *before* showing the Pro/login flow so
            // a non-Pro user without credits sees a clear "not enough"
            // rather than getting bounced through the paywall.
            if !hasCredits {
                if AuthService.shared.currentUser?.subscriptionStatus != 1 {
                    // Not Pro: hand off to the unified auth flow, which
                    // will route to the paywall.
                    AuthManager.shared.checkProAccess { }
                } else {
                    errorMessage = String.aiDarkroomInsufficientCreditsMessage.localized
                }
                return
            }
            AuthManager.shared.checkProAccess { [self] in
                performAIOperation(operation)
            }
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(hasCredits ? 0.1 : 0.05))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(hasCredits ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
                    )

                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(hasCredits ? 0.9 : 0.45))
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(width: 76)
            .opacity(hasCredits ? 1.0 : 0.55)
        }
        .disabled(!hasCredits || pendingOperation == operation)
    }

    /// Entry point that records the operation, then runs the heavy work.
    private func attempt(operation: AIDarkroomOperation) {
        lastFailedOperation = nil
        pendingOperation = operation
        performAIOperation(operation)
    }

    private func performAIOperation(_ operation: AIDarkroomOperation) {
        guard let targetPhoto = photo else { return }

        // Check permissions.
        guard permissionManager.hasPhotoLibraryPermission else {
            permissionManager.checkPhotoLibraryPermission()
            return
        }

        AnalyticsManager.shared.log(.galleryAction(action: "ai_darkroom_\(operation.rawValue)"))

        isProcessingAI = true

        Task {
            do {
                let image: UIImage?
                if let originalImage = await targetPhoto.loadOriginalImage() {
                    image = originalImage
                } else {
                    image = await targetPhoto.loadFullImage()
                }

                guard let inputImage = image else {
                    throw AIInspirationServiceError.noImageProvided
                }

                let (resultImage, remainingCredits) = try await AIDarkroomService.shared.processImage(
                    image: inputImage,
                    operation: operation
                )

                await MainActor.run {
                    AuthService.shared.updateCredits(remainingCredits)
                }

                var localIdentifier: String?

                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest.creationRequestForAsset(from: resultImage)
                    localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
                }

                guard let newAssetId = localIdentifier else { return }

                await MainActor.run {
                    isProcessingAI = false
                    pendingOperation = nil
                    performHaptic(style: .medium)

                    // Create a new `PhotoAsset` and insert it into the database.
                    let newPhoto = PhotoAsset(
                        assetIdentifier: newAssetId,
                        originalAssetIdentifier: nil,
                        title: (targetPhoto.title) + " (AI)",
                        metadata: targetPhoto.metadata, // Try to preserve metadata
                        filterIdentifier: nil, // AI-processed images usually already include effects and no filters are applied
                        mediaType: 1, // Image
                        isLivePhoto: false
                    )

                    modelContext.insert(newPhoto)
                    try? modelContext.save()

                    // Update the local list and selection state.
                    let insertIndex = currentIndex + 1
                    if insertIndex <= localPhotos.count {
                        localPhotos.insert(newPhoto, at: insertIndex)
                    } else {
                        localPhotos.append(newPhoto)
                    }

                    withAnimation {
                        currentIndex = insertIndex
                        isSaved = true
                        showingAIPanel = false
                    }

                    // Reset the saved state after 2 seconds.
                    Task {
                        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                        await MainActor.run {
                            withAnimation {
                                isSaved = false
                            }
                        }
                    }
                }
            } catch {
                // UX-03: surface the failure with a retry entry point and
                // make it explicit that the user was *not* charged.
                let failureMessage = String.aiDarkroomFailureNoCharge.localized + "\n" + (String(describing: error))
                await MainActor.run {
                    isProcessingAI = false
                    pendingOperation = nil
                    lastFailedOperation = operation
                    errorMessage = failureMessage
                    debugLog("AI Processing failed (will surface to user): \(error)")
                }
            }
        }
    }

    private func performHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }
}

struct AIDarkroomButton: View {
    @Binding var showingAIPanel: Bool
    let sideButtonSize: CGFloat

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            withAnimation {
                showingAIPanel = true
            }
        }) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 20))
                .foregroundColor(showingAIPanel ? .accentColor : .white.opacity(0.8))
                .frame(width: sideButtonSize, height: sideButtonSize)
                .glassCardStyle(cornerRadius: sideButtonSize / 2)
        }
    }
}

struct AIDarkroomLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).edgesIgnoringSafeArea(.all)
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                Text(String.aiDarkroomProcessing.localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .transition(.opacity)
        .zIndex(100)
    }
}
