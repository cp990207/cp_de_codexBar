import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

/// `ProviderSwitcherTrackingRunLoopScheduler` is general run-loop-during-modal-tracking plumbing
/// still used by `deferSwitcherMenuRebuildIfStillVisible` (Codex/token account switcher rebuilds),
/// even though the tab-style provider switcher UI it was originally built for no longer exists.
@MainActor
@Suite(.serialized)
struct StatusMenuSwitcherTrackingTests {
    @Test
    func `switcher rebuild scheduler runs during menu tracking exactly once`() {
        var runCount = 0
        ProviderSwitcherTrackingRunLoopScheduler.schedule {
            runCount += 1
        }

        CFRunLoopRunInMode(
            CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString),
            0.1,
            true)
        #expect(runCount == 1)

        CFRunLoopRunInMode(.defaultMode, 0.1, true)
        #expect(runCount == 1)
    }
}
