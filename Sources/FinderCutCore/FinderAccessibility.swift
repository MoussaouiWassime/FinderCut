import ApplicationServices
import Foundation

public struct FinderUIContext: Equatable, Sendable {
    public let focusedRole: String?
    public let focusedSubrole: String?
    public let hasEditableTextValue: Bool
    public let isNativeCutEnabled: Bool?
    public let isNativeCopyEnabled: Bool?

    public init(
        focusedRole: String?,
        focusedSubrole: String?,
        hasEditableTextValue: Bool,
        isNativeCutEnabled: Bool? = nil,
        isNativeCopyEnabled: Bool? = nil
    ) {
        self.focusedRole = focusedRole
        self.focusedSubrole = focusedSubrole
        self.hasEditableTextValue = hasEditableTextValue
        self.isNativeCutEnabled = isNativeCutEnabled
        self.isNativeCopyEnabled = isNativeCopyEnabled
    }
}

public enum FinderCutDecision {
    private static let textEditingRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField",
        "AXWebArea",
    ]

    private static let textEditingSubroles: Set<String> = [
        "AXSearchField",
        "AXSecureTextField",
    ]

    public static func isTextEditing(
        role: String?,
        subrole: String?,
        hasEditableTextValue: Bool
    ) -> Bool {
        if let role, textEditingRoles.contains(role) {
            return true
        }
        if let subrole, textEditingSubroles.contains(subrole) {
            return true
        }
        return hasEditableTextValue
    }

    public static func shouldInterceptCut(context: FinderUIContext) -> Bool {
        if isTextEditing(
            role: context.focusedRole,
            subrole: context.focusedSubrole,
            hasEditableTextValue: context.hasEditableTextValue
        ) {
            return false
        }

        if context.isNativeCutEnabled == true {
            return false
        }

        if context.isNativeCopyEnabled == false {
            return false
        }

        return true
    }

    public static func shouldInterceptPaste(context: FinderUIContext) -> Bool {
        !isTextEditing(
            role: context.focusedRole,
            subrole: context.focusedSubrole,
            hasEditableTextValue: context.hasEditableTextValue
        )
    }
}

public protocol FinderAccessibilityInspecting: Sendable {
    func inspectFocusedElement(finderPID: pid_t) -> FinderUIContext
    func inspectForCut(finderPID: pid_t) -> FinderUIContext
}

public final class LiveFinderAccessibilityInspector: FinderAccessibilityInspecting, @unchecked Sendable {
    /// Short timeout so AX IPC can never cause macOS to disable our CGEventTap.
    private let messagingTimeout: Float

    public init(messagingTimeout: Float = 0.08) {
        self.messagingTimeout = messagingTimeout
    }

    public func inspectFocusedElement(finderPID: pid_t) -> FinderUIContext {
        let appElement = AXUIElementCreateApplication(finderPID)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

        // Query Finder's focused UI element, with system-wide fallback for sheets/panels.
        let focused = copyFocusedElement(from: appElement) ?? copySystemWideFocusedElement()
        let role = focused.flatMap { copyStringAttribute($0, kAXRoleAttribute) }
        let subrole = focused.flatMap { copyStringAttribute($0, kAXSubroleAttribute) }
        let editable = focused.map { isEditableTextElement($0) } ?? false

        return FinderUIContext(
            focusedRole: role,
            focusedSubrole: subrole,
            hasEditableTextValue: editable
        )
    }

    /// Inspects real-time focused element state without relying on Finder's lazily-validated Edit menu items,
    /// which can report stale `AXEnabled` values until the menu is manually opened.
    public func inspectForCut(finderPID: pid_t) -> FinderUIContext {
        inspectFocusedElement(finderPID: finderPID)
    }

    // MARK: - Private AX Helpers

    private func copyFocusedElement(from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &value)
        guard status == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func copySystemWideFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        return copyFocusedElement(from: systemWide)
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success, let string = value as? String else { return nil }
        return string
    }

    private func isEditableTextElement(_ element: AXUIElement) -> Bool {
        var selectedTextRange: CFTypeRef?
        let hasSelectionRange = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedTextRange
        ) == .success

        guard hasSelectionRange else { return false }

        var isSettable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable)
        return status == .success && isSettable.boolValue
    }
}
