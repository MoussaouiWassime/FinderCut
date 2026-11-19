import Carbon
import CoreGraphics
import Foundation

public enum KeyboardLayoutMapper {
    public static let ansiKeyCodeX = CGKeyCode(kVK_ANSI_X)
    public static let ansiKeyCodeC = CGKeyCode(kVK_ANSI_C)
    public static let ansiKeyCodeV = CGKeyCode(kVK_ANSI_V)
    public static let keyCodeEscape = CGKeyCode(kVK_Escape)

    /// Resolves the virtual key code that produces `character` on the active keyboard layout.
    /// Supports QWERTY, AZERTY, Dvorak, Colemak, BÉPO, and IME layouts via ASCII-capable fallback.
    public static func keyCode(for character: Character) -> CGKeyCode? {
        let target = String(character).lowercased()

        if let data = activeUnicodeKeyLayoutData() {
            if let code = findKeyCode(for: target, in: data) {
                return code
            }
        }

        return ansiFallback(for: target)
    }

    public static func ansiFallback(for character: String) -> CGKeyCode? {
        switch character.lowercased() {
        case "x": return ansiKeyCodeX
        case "c": return ansiKeyCodeC
        case "v": return ansiKeyCodeV
        default: return nil
        }
    }

    private static func activeUnicodeKeyLayoutData() -> Data? {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let data = layoutData(from: source) {
            return data
        }
        if let asciiSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let data = layoutData(from: asciiSource) {
            return data
        }
        return nil
    }

    private static func layoutData(from inputSource: TISInputSource) -> Data? {
        guard let rawPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let cfData = Unmanaged<CFData>.fromOpaque(rawPointer).takeUnretainedValue()
        return cfData as Data
    }

    private static func findKeyCode(for targetLowercased: String, in layoutData: Data) -> CGKeyCode? {
        let keyboardType = UInt32(LMGetKbdType())
        return layoutData.withUnsafeBytes { rawBuffer -> CGKeyCode? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            let keyLayoutPtr = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)

            for keyCode in UInt16(0)..<UInt16(128) {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var actualLength = 0

                let status = UCKeyTranslate(
                    keyLayoutPtr,
                    keyCode,
                    UInt16(kUCKeyActionDown),
                    0, // No modifiers
                    keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    chars.count,
                    &actualLength,
                    &chars
                )

                if status == noErr, actualLength > 0 {
                    let translated = String(utf16CodeUnits: chars, count: actualLength).lowercased()
                    if translated == targetLowercased {
                        return CGKeyCode(keyCode)
                    }
                }
            }
            return nil
        }
    }
}
