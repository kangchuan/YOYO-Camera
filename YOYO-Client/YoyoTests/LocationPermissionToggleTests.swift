import Foundation
import Testing
@testable import Yoyo

/// A-11: covers the GPS toggle, which is the one live code path that changed
/// shape in A-10.
///
/// Before the refactor, `toggleGPSSetting()` reached for
/// `PermissionManager.shared`, so the only way to test it was a real
/// permission prompt on a real device. It now asks for a
/// `LocationPermissionProviding`, which is the seam that makes this file
/// possible — and these tests are the proof that the seam is real rather than
/// decorative.
private final class StubLocationPermissions: LocationPermissionProviding {
    var hasLocationPermission: Bool
    private(set) var requestCount = 0

    init(hasLocationPermission: Bool) {
        self.hasLocationPermission = hasLocationPermission
    }

    func requestLocationPermission() {
        requestCount += 1
        // Simulate the user tapping Allow, the way PermissionManager's
        // delegate callback eventually would.
        hasLocationPermission = true
    }
}

@Suite(.serialized)
@MainActor
struct LocationPermissionToggleTests {
    private let gpsKey = "saveGPSEnabled"

    /// Restores the user's real preference afterwards — `@AppStorage` writes
    /// straight through to `UserDefaults.standard`, so a test that flipped the
    /// switch would otherwise change the app on this device.
    private func withCleanGPS<T>(_ body: () throws -> T) rethrows -> T {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: gpsKey)
        defer {
            if let saved {
                defaults.set(saved, forKey: gpsKey)
            } else {
                defaults.removeObject(forKey: gpsKey)
            }
        }
        defaults.set(false, forKey: gpsKey)
        return try body()
    }

    @Test func turnsOnImmediatelyWhenPermissionAlreadyGranted() {
        withCleanGPS {
            let state = CameraSettingsState()
            let permissions = StubLocationPermissions(hasLocationPermission: true)
            state.locationPermissions = permissions

            state.toggleGPSSetting()

            #expect(state.saveGPSEnabled)
            #expect(permissions.requestCount == 0, "already granted — no prompt needed")
        }
    }

    @Test func asksForPermissionAndStaysOffUntilItArrives() {
        withCleanGPS {
            let state = CameraSettingsState()
            let permissions = StubLocationPermissions(hasLocationPermission: false)
            state.locationPermissions = permissions

            // First tap: no permission yet, so nothing may be switched on.
            state.toggleGPSSetting()
            #expect(state.saveGPSEnabled == false)
            #expect(permissions.requestCount == 1)

            // The system answers; the pending flag flips the switch for the
            // user rather than making them tap a second time.
            state.onLocationPermissionGranted()
            #expect(state.saveGPSEnabled)
        }
    }

    @Test func turnsOffWithoutAskingAnything() {
        withCleanGPS {
            let state = CameraSettingsState()
            let permissions = StubLocationPermissions(hasLocationPermission: true)
            state.locationPermissions = permissions

            state.toggleGPSSetting()   // on
            #expect(state.saveGPSEnabled)

            state.toggleGPSSetting()   // off again
            #expect(state.saveGPSEnabled == false)
            #expect(permissions.requestCount == 0)
        }
    }

    @Test func staysOffWhenNoProviderWasWiredUp() {
        // The defensive path added in A-10: a caller that forgets to inject must
        // not end up tagging photos with coordinates it was never granted.
        withCleanGPS {
            let state = CameraSettingsState()
            #expect(state.locationPermissions == nil)

            state.toggleGPSSetting()

            #expect(state.saveGPSEnabled == false)
        }
    }

    @Test func pendingEnableIsConsumedOnlyOnce() {
        withCleanGPS {
            let state = CameraSettingsState()
            state.locationPermissions = StubLocationPermissions(hasLocationPermission: false)

            state.toggleGPSSetting()
            state.onLocationPermissionGranted()
            #expect(state.saveGPSEnabled)

            // A stray second callback must not re-enable a switch the user has
            // since turned off.
            state.toggleGPSSetting()
            #expect(state.saveGPSEnabled == false)
            state.onLocationPermissionGranted()
            #expect(state.saveGPSEnabled == false)
        }
    }

    @Test func permissionManagerSatisfiesTheCapability() {
        // Guards the conformance itself: if PermissionManager ever loses the
        // conformance the injection in CameraManagersContainer stops compiling,
        // and this documents the intended pairing.
        let permissions: LocationPermissionProviding = PermissionManager.shared
        // Just a read — the simulator's authorisation state is not what this
        // test is about, the wiring is.
        _ = permissions.hasLocationPermission
    }
}