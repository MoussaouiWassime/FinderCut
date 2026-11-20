import AppKit
import FinderCutCore
import Foundation

@MainActor
final class CutCoordinator: ObservableObject {
    @Published private(set) var state: CutState = .idle

    var onArmed: ((CutPayload) -> Void)?
    var onMoved: ((CutPayload) -> Void)?
    var onCancelled: (() -> Void)?
    var onStateChanged: ((CutState) -> Void)?

    private var machine = CutStateMachine(armingTimeout: 0.65)
    private var pollTimer: Timer?
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var currentChangeCount: Int {
        pasteboard.changeCount
    }

    func currentFileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return []
        }
        return objects
    }

    func beginCut() {
        machine.beginCut(previousChangeCount: pasteboard.changeCount, now: Date())
        syncState()
        scheduleTimer(interval: 0.025)
    }

    func resolvePayloadForPaste() -> CutPayload? {
        let payload = machine.resolvePayloadForPaste(
            currentChangeCount: pasteboard.changeCount,
            fileURLs: currentFileURLs(),
            now: Date()
        )
        syncState()
        return payload
    }

    func completeMove() {
        let payload = machine.consumeArmedCut()
        syncState()
        stopTimer()
        if let payload {
            onMoved?(payload)
        }
    }

    func cancelCut(notifyUser: Bool) {
        let wasArmed = machine.cancel()
        syncState()
        stopTimer()
        if wasArmed && notifyUser {
            onCancelled?()
        }
    }

    func invalidateIfClipboardChanged() {
        checkPasteboard()
    }

    // MARK: - Private Polling

    private func scheduleTimer(interval: TimeInterval) {
        stopTimer()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkPasteboard() {
        let transition = machine.handlePasteboardCheck(
            currentChangeCount: pasteboard.changeCount,
            fileURLs: currentFileURLs(),
            now: Date()
        )

        switch transition {
        case .noChange:
            break

        case .armed(let payload):
            syncState()
            // Switch from fast arming poll (25ms) to gentle clipboard watch (350ms).
            scheduleTimer(interval: 0.35)
            onArmed?(payload)

        case .armingFailed, .armingTimedOut, .invalidatedByClipboardChange:
            syncState()
            stopTimer()
        }
    }

    private func syncState() {
        if state != machine.state {
            state = machine.state
            onStateChanged?(state)
        }
    }
}
