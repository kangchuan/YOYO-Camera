import Combine
import SwiftUI

// MARK: - inspiration manager

@MainActor
final class InspirationManager: ObservableObject {
    static let shared = InspirationManager()

    @Published private(set) var inspirations: [AIInspiration] = []
    @Published private(set) var historyInspirations: [AIInspiration] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var credits: Int = 0
    /// Per-card failure state. `inspirationCard` checks this and renders
    /// an error state + retry button when the index is in the set. The
    /// previous code only logged to `debugLog` and left the card stuck on
    /// a spinner placeholder forever.
    @Published private(set) var failedIndices: Set<Int> = []
    @Published var showLoginSheet: Bool = false
    @Published var showPaywall: Bool = false

    /// Last successful `requestAIInspirations` result; drives the success
    /// toast on the camera screen. Cleared on every fresh request.
    @Published private(set) var lastSuccessMessage: String?

    private var loadingIndices: Set<Int> = []
    private var originalImage: UIImage? // Store for lazy loading

    private var cancellables = Set<AnyCancellable>()

    private init() {
        AuthService.shared.$currentUser
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                self?.credits = user?.credits ?? 0
            }
            .store(in: &cancellables)

        // The manager is created on the main thread during camera view setup at cold launch;
        // decoding the entire history (JSON + every cached image) synchronously here can block
        // the main thread for seconds and drop taps on the freshly shown controls
        Task { [weak self] in
            await self?.loadHistoryAsync()
        }
    }

    func requestAIInspirations(from image: UIImage?) async {
        guard AuthService.shared.isLoggedIn else {
            showLoginSheet = true
            return
        }

        if AuthService.shared.currentUser?.subscriptionStatus != 1 {
            showPaywall = true
            return
        }

        guard !isLoading else { return }

        // UX-04: pre-click credit gate, driven by the shared `CreditCost`
        // constant instead of a magic `1` literal.
        if !CreditCost.hasEnoughCredits(current: credits, cost: CreditCost.aiInspiration) {
            errorMessage = String.aiInspirationErrorInsufficientCredits.localized
            return
        }

        guard let image else {
            errorMessage = String.aiInspirationNoImage.localized
            return
        }

        originalImage = image // Keep reference
        isLoading = true
        errorMessage = nil
        failedIndices = []
        lastSuccessMessage = nil

        do {
            let (results, remainingCredits) = try await AIInspirationService.shared.fetchInspirations(from: image)
            inspirations = results

            // Add to history
            addToHistory(results)

            // Update global credits
            AuthService.shared.updateCredits(remainingCredits)

            // UX-03: surface success. The cost is communicated in the
            // localised message so the user sees what was charged.
            lastSuccessMessage = String.aiInspirationSuccessMessage.localized(CreditCost.aiInspiration, remainingCredits)

            // 💡 Instantly trigger the generation of all inspiration maps in parallel
            for index in results.indices {
                Task {
                    await self.generateImage(for: index)
                }
            }
        } catch let error as AIInspirationServiceError {
            if case .insufficientCredits = error {
                errorMessage = String.aiInspirationErrorInsufficientCredits.localized
            } else {
                errorMessage = error.localizedDescription
            }
            inspirations = []
        } catch {
            errorMessage = String.aiInspirationGenerateFailed.localized
            inspirations = []
        }

        isLoading = false
    }

    /// Clear the success banner; called by the view once the toast has been
    /// picked up so the next request can refresh it.
    func clearSuccessMessage() {
        lastSuccessMessage = nil
    }

    func clearInspirations() {
        inspirations = []
        errorMessage = nil
        originalImage = nil
        loadingIndices.removeAll()
    }

    func generateImage(for index: Int) async {
        guard index >= 0, index < inspirations.count else { return }

        // Skip if already has image, no original image, or already loading
        guard inspirations[index].image == nil,
              let originalImage,
              !loadingIndices.contains(index) else { return }

        loadingIndices.insert(index)
        let inspiration = inspirations[index]

        do {
            let (image, remainingCredits) = try await AIInspirationService.shared.generateImage(for: inspiration, originalImage: originalImage)

            // Update on main thread
            await MainActor.run {
                self.loadingIndices.remove(index)

                // Update global credits
                AuthService.shared.updateCredits(remainingCredits)

                if index < self.inspirations.count {
                    // Update struct copy
                    var updatedInspiration = self.inspirations[index]
                    updatedInspiration.image = image
                    self.inspirations[index] = updatedInspiration

                    // Update in history as well
                    updateHistoryItem(updatedInspiration)

                    // Clear any previous failure marker for this card.
                    self.failedIndices.remove(index)
                }
            }
        } catch {
            // UX-03: stop leaving the card in a permanent spinner. Mark
            // the card as failed and show a "no charge" toast so the user
            // is not left wondering whether anything happened.
            debugLog("Failed to generate lazy image: \(error)")
            await MainActor.run {
                self.loadingIndices.remove(index)
                self.failedIndices.insert(index)
                self.lastSuccessMessage = nil
            }
        }
    }

    /// UX-03 retry hook. Called by the per-card retry button in
    /// `InspirationOverlay`. Re-arms the slot and fires the same request.
    func retryGenerateImage(for index: Int) {
        guard index >= 0, index < inspirations.count else { return }
        failedIndices.remove(index)
        loadingIndices.remove(index)
        inspirations[index].image = nil
        Task { [weak self] in
            await self?.generateImage(for: index)
        }
    }

    // MARK: - History Management

    private var historyDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory.appendingPathComponent("Inspirations", isDirectory: true)
    }

    private var imagesDirectory: URL {
        historyDirectory.appendingPathComponent("Images", isDirectory: true)
    }

    private var historyFile: URL {
        historyDirectory.appendingPathComponent("history.json")
    }

    private func ensureDirectoriesExist() {
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            debugLog("Failed to create history directories: \(error)")
        }
    }

    private func addToHistory(_ newInspirations: [AIInspiration]) {
        // Prepend to history
        historyInspirations.insert(contentsOf: newInspirations, at: 0)

        // Save images for those that have them (though usually new ones don't yet)
        for inspiration in newInspirations {
            if let image = inspiration.image {
                saveImage(image, for: inspiration.id)
            }
        }

        saveHistory()
    }

    private func updateHistoryItem(_ updatedInspiration: AIInspiration) {
        if let index = historyInspirations.firstIndex(where: { $0.id == updatedInspiration.id }) {
            historyInspirations[index] = updatedInspiration

            // Save image if updated
            if let image = updatedInspiration.image {
                saveImage(image, for: updatedInspiration.id)
            }

            saveHistory()
        }
    }

    func deleteHistoryItem(at indexSet: IndexSet) {
        for index in indexSet {
            let inspiration = historyInspirations[index]
            deleteImage(for: inspiration.id)
        }
        historyInspirations.remove(atOffsets: indexSet)
        saveHistory()
    }

    func clearHistory() {
        historyInspirations = []
        saveHistory()

        // Delete all images
        do {
            if FileManager.default.fileExists(atPath: imagesDirectory.path) {
                try FileManager.default.removeItem(at: imagesDirectory)
            }
            ensureDirectoriesExist()
        } catch {
            debugLog("Failed to clear images directory: \(error)")
        }
    }

    private func saveHistory() {
        ensureDirectoriesExist()
        do {
            let data = try JSONEncoder().encode(historyInspirations)
            try data.write(to: historyFile)
        } catch {
            debugLog("Failed to save history: \(error)")
        }
    }

    private func loadHistoryAsync() async {
        let historyFile = self.historyFile
        let imagesDirectory = self.imagesDirectory

        let loadedHistory = await Task.detached(priority: .utility) { () -> [AIInspiration]? in
            do {
                try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
                guard FileManager.default.fileExists(atPath: historyFile.path) else { return nil }
                let data = try Data(contentsOf: historyFile)
                var loadedHistory = try JSONDecoder().decode([AIInspiration].self, from: data)

                // Load images from disk
                for i in 0 ..< loadedHistory.count {
                    let fileURL = imagesDirectory.appendingPathComponent("\(loadedHistory[i].id.uuidString).jpg")
                    if let imageData = try? Data(contentsOf: fileURL),
                       let image = UIImage(data: imageData)
                    {
                        loadedHistory[i].image = image
                    }
                }
                return loadedHistory
            } catch {
                debugLog("Failed to load history: \(error)")
                return nil
            }
        }.value

        guard let loadedHistory else { return }

        // Items added while the history was still loading stay first (they are newer)
        let inMemoryIDs = Set(historyInspirations.map(\.id))
        historyInspirations += loadedHistory.filter { !inMemoryIDs.contains($0.id) }
    }

    private func saveImage(_ image: UIImage, for id: UUID) {
        ensureDirectoriesExist()
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
    }

    private func deleteImage(for id: UUID) {
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }

    var isShowingInspirations: Bool {
        isLoading || !inspirations.isEmpty || errorMessage != nil
    }
}
