import Foundation

/// Pure state model determining whether the session-level `CGEventTap` should be enabled.
///
/// Suspending the event tap whenever Finder is not frontmost (or when FinderCut is paused)
/// avoids waking the process on global keystrokes in other applications.
public struct EventTapActivationPolicy: Equatable, Sendable {
    public static let finderBundleIdentifier = "com.apple.finder"

    public private(set) var isEnabled: Bool
    public private(set) var activeFinderPID: pid_t?

    public init(
        isEnabled: Bool = true,
        frontmostBundleIdentifier: String? = nil,
        frontmostProcessIdentifier: pid_t? = nil
    ) {
        self.isEnabled = isEnabled
        if frontmostBundleIdentifier == Self.finderBundleIdentifier,
           let frontmostProcessIdentifier
        {
            self.activeFinderPID = frontmostProcessIdentifier
        } else {
            self.activeFinderPID = nil
        }
    }

    public var isFinderFrontmost: Bool {
        activeFinderPID != nil
    }

    public var shouldEnableTap: Bool {
        isEnabled && activeFinderPID != nil
    }

    /// Updates the cached frontmost application.
    /// Returns `true` if `shouldEnableTap` changed as a result.
    @discardableResult
    public mutating func updateFrontmostApplication(
        bundleIdentifier: String?,
        processIdentifier: pid_t?
    ) -> Bool {
        let previousShouldEnable = shouldEnableTap
        if bundleIdentifier == Self.finderBundleIdentifier, let processIdentifier {
            activeFinderPID = processIdentifier
        } else {
            activeFinderPID = nil
        }
        return shouldEnableTap != previousShouldEnable
    }

    /// Updates whether FinderCut interception is enabled by the user.
    /// Returns `true` if `shouldEnableTap` changed as a result.
    @discardableResult
    public mutating func updateEnabled(_ enabled: Bool) -> Bool {
        let previousShouldEnable = shouldEnableTap
        isEnabled = enabled
        return shouldEnableTap != previousShouldEnable
    }
}
