// Sources/App/PowerAssertionManager.swift
import IOKit.pwr_mgt

/// Wraps a macOS power-management assertion that prevents idle system sleep
/// — the same mechanism `caffeinate -i` uses. Held only while the user has
/// opted in via Settings, so it never keeps a Mac awake without consent.
final class PowerAssertionManager {
    static let shared = PowerAssertionManager()
    private init() {}

    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    /// Fired whenever `isActive` actually changes, so UI (e.g. the menu bar
    /// indicator) can mirror the real assertion state instead of assuming it.
    var onStateChange: ((Bool) -> Void)?

    func start() {
        guard !isActive else { return }
        var id: IOPMAssertionID = 0
        let reason = "Clippy is keeping the Mac awake to monitor the clipboard" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )
        guard result == kIOReturnSuccess else {
            print("[PowerAssertionManager] failed to create assertion: \(result)")
            return
        }
        assertionID = id
        isActive = true
        onStateChange?(true)
    }

    func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        isActive = false
        onStateChange?(false)
    }
}
