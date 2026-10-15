import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// Centralised guard for "should we boot the Firebase SDK at all?".
///
/// Background
/// ──────────
/// `GoogleService-Info.plist` ships with `PROJECT_ID = yoyo-camera` — the
/// private Firebase project the team created on Day 1 for prototyping.
/// Calling `FirebaseApp.configure()` against that project makes the app
/// phone home to a project that no longer matches our legal / privacy
/// posture (the analytics + Crashlytics toggle only suppresses *uploads*;
/// the SDK still initialises and the device still registers).
///
/// Decision rule
/// ─────────────
/// - If `GoogleService-Info.plist` is missing entirely → no Firebase.
/// - If the project's `PROJECT_ID` is the Day-1 stub (`yoyo-camera`) → no
///   Firebase. The audit calls this out as the "still on Day 1" smell.
/// - Otherwise (a real, post-cutover plist) → opt-in initialise.
///
/// This file intentionally avoids importing `FirebaseCore` so that even
/// tests that don't link FirebaseCore can ask the question. The single
/// `FirebaseApp.configure()` call site lives in `AppDelegate`.
enum FirebaseBootstrap {
    /// The Day-1 stub PROJECT_ID. Any plist carrying this value is treated
    /// as "the SDK must not be initialised". Update this constant if/when
    /// the team creates a new Firebase project and ships a new plist.
    static let dayOneProjectID = "yoyo-camera"

    /// Plist key (Firebase) holding the project identifier.
    static let projectIDKey = "PROJECT_ID"

    /// Returns `true` when the bundled `GoogleService-Info.plist` is
    /// present **and** its `PROJECT_ID` is not the Day-1 stub. This is the
    /// single source of truth that the AppDelegate and any analytics
    /// helper should consult before touching the SDK.
    static func shouldInitializeFirebase() -> Bool {
        guard let projectID = currentProjectID() else {
            debugLog("🔥 Firebase: GoogleService-Info.plist missing — skipping configure()")
            return false
        }
        if projectID == dayOneProjectID {
            debugLog("🔥 Firebase: Day-1 project ID (\(dayOneProjectID)) detected — skipping configure()")
            return false
        }
        debugLog("🔥 Firebase: project ID \(projectID) — will configure()")
        return true
    }

    /// Reads `PROJECT_ID` from the bundled plist. Returns `nil` if the
    /// plist is missing or the key is not present.
    static func currentProjectID() -> String? {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist[projectIDKey] as? String
    }

    /// Convenience wrapper for the call site. Centralised so we don't
    /// sprinkle `FirebaseApp.configure()` around the codebase.
    ///
    /// The Firebase types are guarded by `canImport` so targets that don't
    /// link `FirebaseCore` (e.g. unit tests) can still ask
    /// `shouldInitializeFirebase()` and merely get a no-op here.
    static func configureIfEligible() {
        guard shouldInitializeFirebase() else { return }
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif
    }
}
