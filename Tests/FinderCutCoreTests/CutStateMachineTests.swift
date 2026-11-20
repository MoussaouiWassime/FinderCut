import Foundation
import Testing
@testable import FinderCutCore

@Suite("CutStateMachine")
struct CutStateMachineTests {
    private let sampleURLs = [
        URL(fileURLWithPath: "/Users/test/Desktop/report.pdf"),
        URL(fileURLWithPath: "/Users/test/Desktop/notes.txt"),
    ]

    @Test("Normal cut -> paste lifecycle")
    func normalCutAndPasteLifecycle() {
        var machine = CutStateMachine(armingTimeout: 0.6)
        let t0 = Date(timeIntervalSince1970: 1000)

        #expect(machine.state == .idle)

        machine.beginCut(previousChangeCount: 10, now: t0)
        #expect(!machine.state.isArmed)

        // Pasteboard has not updated yet
        let pending = machine.handlePasteboardCheck(
            currentChangeCount: 10,
            fileURLs: [],
            now: t0.addingTimeInterval(0.05)
        )
        #expect(pending == .noChange)

        // Finder finishes Copy -> pasteboard changes with file URLs
        let armed = machine.handlePasteboardCheck(
            currentChangeCount: 11,
            fileURLs: sampleURLs,
            now: t0.addingTimeInterval(0.08)
        )
        if case .armed(let payload) = armed {
            #expect(payload.fileURLs == sampleURLs)
            #expect(payload.changeCount == 11)
            #expect(payload.itemCount == 2)
            #expect(payload.singleItemName == nil)
        } else {
            Issue.record("Expected .armed transition, got \(armed)")
        }

        // User pastes while pasteboard matches
        let resolved = machine.resolvePayloadForPaste(
            currentChangeCount: 11,
            fileURLs: sampleURLs,
            now: t0.addingTimeInterval(2.0)
        )
        #expect(resolved?.fileURLs == sampleURLs)

        // Consuming resets to idle
        let consumed = machine.consumeArmedCut()
        #expect(consumed?.fileURLs == sampleURLs)
        #expect(machine.state == .idle)
        #expect(machine.consumeArmedCut() == nil)
    }

    @Test("Fast paste promotes arming state synchronously when clipboard already updated")
    func fastPastePromotesArming() {
        var machine = CutStateMachine(armingTimeout: 0.6)
        let t0 = Date(timeIntervalSince1970: 2000)
        let singleFile = [URL(fileURLWithPath: "/tmp/photo.png")]

        machine.beginCut(previousChangeCount: 5, now: t0)

        let payload = machine.resolvePayloadForPaste(
            currentChangeCount: 6,
            fileURLs: singleFile,
            now: t0.addingTimeInterval(0.015)
        )
        #expect(payload?.singleItemName == "photo.png")
        #expect(machine.state.isArmed)
    }

    @Test("External clipboard change invalidates armed cut")
    func externalClipboardInvalidatesArmedCut() {
        var machine = CutStateMachine()
        let t0 = Date(timeIntervalSince1970: 3000)

        machine.beginCut(previousChangeCount: 1, now: t0)
        _ = machine.handlePasteboardCheck(
            currentChangeCount: 2,
            fileURLs: sampleURLs,
            now: t0.addingTimeInterval(0.03)
        )
        #expect(machine.state.isArmed)

        // User copies text in another app -> changeCount becomes 3
        let transition = machine.handlePasteboardCheck(
            currentChangeCount: 3,
            fileURLs: [],
            now: t0.addingTimeInterval(1.0)
        )
        #expect(transition == .invalidatedByClipboardChange)
        #expect(machine.state == .idle)
    }

    @Test("Arming fails when non-file content is copied")
    func armingFailsOnNonFileContent() {
        var machine = CutStateMachine()
        let t0 = Date(timeIntervalSince1970: 4000)

        machine.beginCut(previousChangeCount: 20, now: t0)
        let transition = machine.handlePasteboardCheck(
            currentChangeCount: 21,
            fileURLs: [],
            now: t0.addingTimeInterval(0.04)
        )
        #expect(transition == .armingFailed)
        #expect(machine.state == .idle)
    }

    @Test("Arming times out cleanly if Finder does not copy anything")
    func armingTimesOut() {
        var machine = CutStateMachine(armingTimeout: 0.5)
        let t0 = Date(timeIntervalSince1970: 5000)

        machine.beginCut(previousChangeCount: 30, now: t0)
        let transition = machine.handlePasteboardCheck(
            currentChangeCount: 30,
            fileURLs: [],
            now: t0.addingTimeInterval(0.6)
        )
        #expect(transition == .armingTimedOut)
        #expect(machine.state == .idle)
    }

    @Test("Cancel returns true only when actively armed")
    func cancelBehavior() {
        var machine = CutStateMachine()
        let t0 = Date(timeIntervalSince1970: 6000)

        let cancelIdle = machine.cancel()
        #expect(!cancelIdle)

        machine.beginCut(previousChangeCount: 1, now: t0)
        let cancelArming = machine.cancel()
        #expect(!cancelArming)
        #expect(machine.state == .idle)

        machine.beginCut(previousChangeCount: 1, now: t0)
        _ = machine.handlePasteboardCheck(currentChangeCount: 2, fileURLs: sampleURLs, now: t0)
        let cancelArmed = machine.cancel()
        #expect(cancelArmed)
        #expect(machine.state == .idle)
    }
}

@Suite("FinderCutDecision")
struct FinderCutDecisionTests {
    @Test("Never intercepts while editing text in Finder")
    func ignoresTextEditing() {
        let renameContext = FinderUIContext(
            focusedRole: "AXTextField",
            focusedSubrole: nil,
            hasEditableTextValue: true,
            isNativeCutEnabled: true,
            isNativeCopyEnabled: true
        )
        #expect(!FinderCutDecision.shouldInterceptCut(context: renameContext))
        #expect(!FinderCutDecision.shouldInterceptPaste(context: renameContext))

        let searchContext = FinderUIContext(
            focusedRole: "AXTextField",
            focusedSubrole: "AXSearchField",
            hasEditableTextValue: true,
            isNativeCutEnabled: nil,
            isNativeCopyEnabled: nil
        )
        #expect(!FinderCutDecision.shouldInterceptCut(context: searchContext))
        #expect(!FinderCutDecision.shouldInterceptPaste(context: searchContext))

        let customTokenContext = FinderUIContext(
            focusedRole: "AXGroup",
            focusedSubrole: nil,
            hasEditableTextValue: true,
            isNativeCutEnabled: false,
            isNativeCopyEnabled: true
        )
        #expect(!FinderCutDecision.shouldInterceptCut(context: customTokenContext))
        #expect(!FinderCutDecision.shouldInterceptPaste(context: customTokenContext))
    }

    @Test("Respects Finder native Cut and Copy menu states")
    func respectsNativeMenuStates() {
        // e.g., Get Info icon selected -> native Cut is enabled
        let nativeCutEnabled = FinderUIContext(
            focusedRole: "AXImage",
            focusedSubrole: nil,
            hasEditableTextValue: false,
            isNativeCutEnabled: true,
            isNativeCopyEnabled: true
        )
        #expect(!FinderCutDecision.shouldInterceptCut(context: nativeCutEnabled))

        // Nothing selected -> native Copy is disabled
        let nothingSelected = FinderUIContext(
            focusedRole: "AXOutline",
            focusedSubrole: nil,
            hasEditableTextValue: false,
            isNativeCutEnabled: false,
            isNativeCopyEnabled: false
        )
        #expect(!FinderCutDecision.shouldInterceptCut(context: nothingSelected))

        // File selected in List view -> native Cut disabled, native Copy enabled
        let filesSelected = FinderUIContext(
            focusedRole: "AXOutline",
            focusedSubrole: nil,
            hasEditableTextValue: false,
            isNativeCutEnabled: false,
            isNativeCopyEnabled: true
        )
        #expect(FinderCutDecision.shouldInterceptCut(context: filesSelected))
        #expect(FinderCutDecision.shouldInterceptPaste(context: filesSelected))
    }
}

@Suite("KeyboardLayoutMapper & Localization & Preferences")
struct CoreUtilitiesTests {
    @Test("Resolves virtual key codes for cut/copy/paste")
    func resolvesKeyCodes() {
        #expect(KeyboardLayoutMapper.keyCode(for: "c") != nil)
        #expect(KeyboardLayoutMapper.keyCode(for: "v") != nil)
        #expect(KeyboardLayoutMapper.keyCode(for: "x") != nil)
    }

    @Test("Localization formats French and English strings cleanly")
    func localizationStrings() {
        let fr = L10n(language: .french)
        #expect(fr.hudCut(count: 1, singleName: "notes.txt") == "Coupé : notes.txt")
        #expect(fr.hudCut(count: 3, singleName: nil) == "3 éléments coupés")
        #expect(fr.hudMoved(count: 1) == "1 élément déplacé")
        #expect(fr.hudMoved(count: 2) == "2 éléments déplacés")
        #expect(fr.statusPillCutReady(count: 1) == "1 prêt")
        #expect(fr.statusPillCutReady(count: 3) == "3 prêts")
        #expect(fr.settingsShortcuts.count == 4)

        let en = L10n(language: .english)
        #expect(en.hudCut(count: 1, singleName: "notes.txt") == "Cut: notes.txt")
        #expect(en.hudCut(count: 3, singleName: nil) == "Cut 3 items")
        #expect(en.hudMoved(count: 1) == "Moved 1 item")
        #expect(en.hudMoved(count: 2) == "Moved 2 items")
        #expect(en.statusPillCutReady(count: 2) == "2 ready")
        #expect(en.settingsShortcuts.count == 4)
    }

    @MainActor
    @Test("PreferencesStore persists settings in UserDefaults")
    func preferencesPersistence() {
        let suiteName = "com.wassime.FinderCut.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(userDefaults: defaults)
        #expect(store.isEnabled == true)
        #expect(store.cancelWithEscape == true)
        #expect(store.showHUD == true)
        #expect(store.playSound == false)

        store.isEnabled = false
        store.playSound = true
        store.showHUD = false

        let reloaded = PreferencesStore(userDefaults: defaults)
        #expect(reloaded.isEnabled == false)
        #expect(reloaded.playSound == true)
        #expect(reloaded.showHUD == false)
    }
}
