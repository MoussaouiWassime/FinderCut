import Foundation
import Testing
@testable import FinderCutCore

@Suite("EventTapActivationPolicy")
struct EventTapActivationPolicyTests {
    @Test("Enables tap only when Finder is frontmost and app is enabled")
    func initialActivationStates() {
        let finderActive = EventTapActivationPolicy(
            isEnabled: true,
            frontmostBundleIdentifier: EventTapActivationPolicy.finderBundleIdentifier,
            frontmostProcessIdentifier: 4242
        )
        #expect(finderActive.isFinderFrontmost)
        #expect(finderActive.activeFinderPID == 4242)
        #expect(finderActive.shouldEnableTap)

        let otherAppActive = EventTapActivationPolicy(
            isEnabled: true,
            frontmostBundleIdentifier: "com.apple.Safari",
            frontmostProcessIdentifier: 1234
        )
        #expect(!otherAppActive.isFinderFrontmost)
        #expect(otherAppActive.activeFinderPID == nil)
        #expect(!otherAppActive.shouldEnableTap)

        let pausedInFinder = EventTapActivationPolicy(
            isEnabled: false,
            frontmostBundleIdentifier: EventTapActivationPolicy.finderBundleIdentifier,
            frontmostProcessIdentifier: 4242
        )
        #expect(pausedInFinder.isFinderFrontmost)
        #expect(pausedInFinder.activeFinderPID == 4242)
        #expect(!pausedInFinder.shouldEnableTap)
    }

    @Test("Suspends tap when leaving Finder and re-enables when returning")
    func frontmostApplicationTransitions() {
        var policy = EventTapActivationPolicy(isEnabled: true)
        #expect(!policy.shouldEnableTap)

        // Switching from unknown to Safari does not change tap state.
        let safariChange = policy.updateFrontmostApplication(
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: 100
        )
        #expect(!safariChange)
        #expect(!policy.shouldEnableTap)

        // Activating Finder enables the tap and caches Finder's PID.
        let finderChange = policy.updateFrontmostApplication(
            bundleIdentifier: EventTapActivationPolicy.finderBundleIdentifier,
            processIdentifier: 512
        )
        #expect(finderChange)
        #expect(policy.shouldEnableTap)
        #expect(policy.activeFinderPID == 512)

        // Leaving Finder suspends the tap and clears Finder's PID.
        let leaveChange = policy.updateFrontmostApplication(
            bundleIdentifier: "com.microsoft.VSCode",
            processIdentifier: 999
        )
        #expect(leaveChange)
        #expect(!policy.shouldEnableTap)
        #expect(policy.activeFinderPID == nil)

        // Unknown / nil frontmost app stays suspended cleanly.
        let nilChange = policy.updateFrontmostApplication(
            bundleIdentifier: nil,
            processIdentifier: nil
        )
        #expect(!nilChange)
        #expect(!policy.shouldEnableTap)
    }

    @Test("Updates cached PID on Finder relaunch without toggling tap state")
    func finderRelaunchUpdatesPID() {
        var policy = EventTapActivationPolicy(
            isEnabled: true,
            frontmostBundleIdentifier: EventTapActivationPolicy.finderBundleIdentifier,
            frontmostProcessIdentifier: 500
        )

        let changed = policy.updateFrontmostApplication(
            bundleIdentifier: EventTapActivationPolicy.finderBundleIdentifier,
            processIdentifier: 777
        )
        #expect(!changed)
        #expect(policy.shouldEnableTap)
        #expect(policy.activeFinderPID == 777)
    }

    @Test("Respects user pause and resume across Finder and non-Finder contexts")
    func pauseAndResumeBehavior() {
        var policy = EventTapActivationPolicy(
            isEnabled: true,
            frontmostBundleIdentifier: EventTapActivationPolicy.finderBundleIdentifier,
            frontmostProcessIdentifier: 321
        )
        #expect(policy.shouldEnableTap)

        // Pausing while in Finder suspends the tap.
        let pausedChanged = policy.updateEnabled(false)
        #expect(pausedChanged)
        #expect(!policy.shouldEnableTap)

        // Switching apps while paused never enables the tap.
        let switchedToTerminal = policy.updateFrontmostApplication(
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 654
        )
        #expect(!switchedToTerminal)
        let switchedBackToFinder = policy.updateFrontmostApplication(
            bundleIdentifier: EventTapActivationPolicy.finderBundleIdentifier,
            processIdentifier: 321
        )
        #expect(!switchedBackToFinder)
        #expect(!policy.shouldEnableTap)

        // Resuming while in Finder immediately re-enables the tap.
        let resumedChanged = policy.updateEnabled(true)
        #expect(resumedChanged)
        #expect(policy.shouldEnableTap)

        // Pausing and resuming outside Finder does not toggle the tap.
        let leftFinder = policy.updateFrontmostApplication(
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 654
        )
        #expect(leftFinder)
        let pausedOutside = policy.updateEnabled(false)
        #expect(!pausedOutside)
        let resumedOutside = policy.updateEnabled(true)
        #expect(!resumedOutside)
        #expect(!policy.shouldEnableTap)
    }
}
