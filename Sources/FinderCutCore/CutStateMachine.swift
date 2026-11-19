import Foundation

public struct CutPayload: Equatable, Sendable {
    public let fileURLs: [URL]
    public let changeCount: Int
    public let armedAt: Date

    public init(fileURLs: [URL], changeCount: Int, armedAt: Date) {
        self.fileURLs = fileURLs
        self.changeCount = changeCount
        self.armedAt = armedAt
    }

    public var itemCount: Int { fileURLs.count }

    public var singleItemName: String? {
        fileURLs.count == 1 ? fileURLs.first?.lastPathComponent : nil
    }
}

public enum CutState: Equatable, Sendable {
    case idle
    case arming(previousChangeCount: Int, startedAt: Date)
    case armed(CutPayload)

    public var isArmed: Bool {
        if case .armed = self { return true }
        return false
    }

    public var armedPayload: CutPayload? {
        if case .armed(let payload) = self { return payload }
        return nil
    }
}

public enum CutTransition: Equatable, Sendable {
    case noChange
    case armed(CutPayload)
    case armingFailed
    case armingTimedOut
    case invalidatedByClipboardChange
}

public struct CutStateMachine: Sendable {
    public private(set) var state: CutState = .idle
    public let armingTimeout: TimeInterval

    public init(armingTimeout: TimeInterval = 0.6) {
        self.armingTimeout = armingTimeout
    }

    public mutating func beginCut(previousChangeCount: Int, now: Date = Date()) {
        state = .arming(previousChangeCount: previousChangeCount, startedAt: now)
    }

    @discardableResult
    public mutating func handlePasteboardCheck(
        currentChangeCount: Int,
        fileURLs: @autoclosure () -> [URL],
        now: Date = Date()
    ) -> CutTransition {
        switch state {
        case .idle:
            return .noChange

        case .arming(let previousChangeCount, let startedAt):
            if currentChangeCount != previousChangeCount {
                let urls = fileURLs()
                if !urls.isEmpty {
                    let payload = CutPayload(
                        fileURLs: urls,
                        changeCount: currentChangeCount,
                        armedAt: now
                    )
                    state = .armed(payload)
                    return .armed(payload)
                } else {
                    state = .idle
                    return .armingFailed
                }
            } else if now.timeIntervalSince(startedAt) >= armingTimeout {
                state = .idle
                return .armingTimedOut
            } else {
                return .noChange
            }

        case .armed(let payload):
            if currentChangeCount != payload.changeCount {
                state = .idle
                return .invalidatedByClipboardChange
            }
            return .noChange
        }
    }

    public mutating func resolvePayloadForPaste(
        currentChangeCount: Int,
        fileURLs: @autoclosure () -> [URL],
        now: Date = Date()
    ) -> CutPayload? {
        _ = handlePasteboardCheck(
            currentChangeCount: currentChangeCount,
            fileURLs: fileURLs(),
            now: now
        )
        if case .armed(let payload) = state, payload.changeCount == currentChangeCount {
            return payload
        }
        return nil
    }

    @discardableResult
    public mutating func consumeArmedCut() -> CutPayload? {
        defer { state = .idle }
        if case .armed(let payload) = state {
            return payload
        }
        return nil
    }

    /// Cancels any active or arming cut. Returns `true` if a cut was actively armed.
    @discardableResult
    public mutating func cancel() -> Bool {
        let wasArmed = state.isArmed
        state = .idle
        return wasArmed
    }
}
