import AppKit
import CoreGraphics
import FinderCutCore
import Foundation
import os

private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

@MainActor
final class EventTapController {
    private static let logger = Logger(subsystem: "com.wassime.FinderCut", category: "EventTap")
    private static let finderBundleIdentifier = "com.apple.finder"
    private static let syntheticEventTag: Int64 = 0x4643_5554_0001
    private static let deviceLeftCommandMask: UInt64 = 0x0000_0008
    private static let deviceLeftAlternateMask: UInt64 = 0x0000_0020

    private let preferences: PreferencesStore
    private let coordinator: CutCoordinator
    private let accessibilityInspector: FinderAccessibilityInspecting

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var suppressedCutKeyCode: CGKeyCode?
    private var modifiedPasteKeyCode: CGKeyCode?

    private(set) var isRunning: Bool = false

    init(
        preferences: PreferencesStore,
        coordinator: CutCoordinator,
        accessibilityInspector: FinderAccessibilityInspecting = LiveFinderAccessibilityInspector()
    ) {
        self.preferences = preferences
        self.coordinator = coordinator
        self.accessibilityInspector = accessibilityInspector
    }

    @discardableResult
    func start() -> Bool {
        if isRunning, let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return true
        }

        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
                let boxedEvent = UncheckedBox(value: event)
                let shouldSuppress = MainActor.assumeIsolated {
                    controller.handleEvent(proxy: proxy, type: type, event: boxedEvent.value)
                }
                return shouldSuppress ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            isRunning = false
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            isRunning = false
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isRunning = true
        Self.logger.info("CGEventTap started successfully")
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        suppressedCutKeyCode = nil
        modifiedPasteKeyCode = nil
        isRunning = false
    }

    // MARK: - Event Handling

    /// Returns `true` to suppress the event, or `false` to pass it through (possibly with modified flags).
    private func handleEvent(
        proxy _: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }

        // Never intercept our own synthetic events.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag {
            return false
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Keep keyUp balanced with any previously suppressed ⌘X or modified ⌘V.
        if type == .keyUp {
            if suppressedCutKeyCode == keyCode {
                suppressedCutKeyCode = nil
                return true
            }
            if modifiedPasteKeyCode == keyCode {
                modifiedPasteKeyCode = nil
                event.flags = CGEventFlags(
                    rawValue: event.flags.rawValue
                        | CGEventFlags.maskAlternate.rawValue
                        | Self.deviceLeftAlternateMask
                )
                return false
            }
            return false
        }

        guard type == .keyDown else {
            return false
        }

        guard preferences.isEnabled else {
            return false
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.bundleIdentifier == Self.finderBundleIdentifier
        else {
            return false
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            if suppressedCutKeyCode == keyCode {
                return true
            }
            return false
        }

        let relevantModifiers = event.flags.intersection([
            .maskCommand,
            .maskShift,
            .maskAlternate,
            .maskControl,
        ])

        // Escape cancels pending cut.
        if keyCode == KeyboardLayoutMapper.keyCodeEscape && relevantModifiers.isEmpty {
            if preferences.cancelWithEscape && coordinator.state.isArmed {
                let context = accessibilityInspector.inspectFocusedElement(finderPID: frontmostApp.processIdentifier)
                if FinderCutDecision.shouldInterceptPaste(context: context) {
                    coordinator.cancelCut(notifyUser: true)
                }
            }
            return false
        }

        guard let character = characterIgnoringModifiers(for: event, keyCode: keyCode) else {
            return false
        }

        // ⌘X -> Intercept and trigger native Finder Copy (⌘C) while arming Cut state.
        if relevantModifiers == .maskCommand && character == "x" {
            let context = accessibilityInspector.inspectForCut(finderPID: frontmostApp.processIdentifier)
            guard FinderCutDecision.shouldInterceptCut(context: context) else {
                Self.logger.debug("Ignoring ⌘X (text editing role: \(context.focusedRole ?? "nil"))")
                return false
            }

            Self.logger.info("Intercepted ⌘X in Finder, triggering synthetic ⌘C")
            suppressedCutKeyCode = keyCode
            coordinator.beginCut()
            DispatchQueue.main.async { [weak self] in
                self?.postSyntheticCopy()
            }
            return true
        }

        // ⌘V -> If a cut is armed, transform into ⌘⌥V (Finder's native Move Item Here).
        if relevantModifiers == .maskCommand && character == "v" {
            guard coordinator.resolvePayloadForPaste() != nil else {
                return false
            }

            let context = accessibilityInspector.inspectFocusedElement(finderPID: frontmostApp.processIdentifier)
            guard FinderCutDecision.shouldInterceptPaste(context: context) else {
                Self.logger.debug("Ignoring ⌘V (text editing role: \(context.focusedRole ?? "nil"))")
                return false
            }

            Self.logger.info("Transforming ⌘V into ⌘⌥V (Move Item Here) in Finder")
            modifiedPasteKeyCode = keyCode
            event.flags = CGEventFlags(
                rawValue: event.flags.rawValue
                    | CGEventFlags.maskAlternate.rawValue
                    | Self.deviceLeftAlternateMask
            )

            DispatchQueue.main.async { [weak self] in
                self?.coordinator.completeMove()
            }
            return false
        }

        // Manual ⌘⌥V -> Clear armed cut state cleanly.
        if relevantModifiers == [.maskCommand, .maskAlternate] && character == "v" {
            if coordinator.state.isArmed {
                DispatchQueue.main.async { [weak self] in
                    self?.coordinator.completeMove()
                }
            }
            return false
        }

        // ⌘C -> User chose normal Copy, cancel any pending Cut silently.
        if relevantModifiers == .maskCommand && character == "c" {
            if coordinator.state != .idle {
                DispatchQueue.main.async { [weak self] in
                    self?.coordinator.cancelCut(notifyUser: false)
                }
            }
            return false
        }

        return false
    }

    private func characterIgnoringModifiers(for event: CGEvent, keyCode: CGKeyCode) -> String? {
        if let nsEvent = NSEvent(cgEvent: event),
           let chars = nsEvent.charactersIgnoringModifiers?.lowercased(),
           !chars.isEmpty {
            return chars
        }
        switch keyCode {
        case KeyboardLayoutMapper.ansiKeyCodeX: return "x"
        case KeyboardLayoutMapper.ansiKeyCodeC: return "c"
        case KeyboardLayoutMapper.ansiKeyCodeV: return "v"
        default: return nil
        }
    }

    private func postSyntheticCopy() {
        let copyKeyCode = KeyboardLayoutMapper.keyCode(for: "c") ?? KeyboardLayoutMapper.ansiKeyCodeC
        guard let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: copyKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: copyKeyCode, keyDown: false)
        else {
            return
        }

        let commandFlags = CGEventFlags(
            rawValue: CGEventFlags.maskCommand.rawValue | Self.deviceLeftCommandMask
        )
        keyDown.flags = commandFlags
        keyUp.flags = commandFlags

        keyDown.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
