import AppKit
import ApplicationServices
import Combine
import FinderCutCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let reopenNotificationName = Notification.Name("com.wassime.FinderCut.openSettings")

    private let preferences = PreferencesStore()
    private let coordinator = CutCoordinator()
    private let hud = HUDOverlayController()
    private let launchAtLogin = LaunchAtLoginManager()
    private let statusModel = AppStatusModel()
    private let l10n = L10n.current

    private lazy var eventTapController = EventTapController(
        preferences: preferences,
        coordinator: coordinator
    )

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionPollTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupBindings()
        setupCoordinatorCallbacks()
        setupWorkspaceObserver()
        setupReopenObserver()
        updateStatusItemVisibility()

        checkAccessibilityAndStartTap(promptIfUntrusted: false)

        if !statusModel.isAccessibilityTrusted || !statusModel.isTapRunning {
            openSettingsWindow()
            startPermissionPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPermissionPolling()
        eventTapController.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    // MARK: - Setup

    private func setupBindings() {
        preferences.$isEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    self.coordinator.cancelCut(notifyUser: false)
                }
                self.eventTapController.setEnabled(enabled)
                self.updateStatusBarButton()
            }
            .store(in: &cancellables)

        preferences.$showCountInMenuBar
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateStatusBarButton()
            }
            .store(in: &cancellables)

        preferences.$hideMenuBarIcon
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateStatusItemVisibility()
            }
            .store(in: &cancellables)
    }

    private func setupCoordinatorCallbacks() {
        coordinator.onStateChanged = { [weak self] newState in
            guard let self else { return }
            self.statusModel.cutState = newState
            self.updateStatusBarButton()
        }

        coordinator.onArmed = { [weak self] payload in
            guard let self else { return }
            self.animateStatusBarCutFeedback()
            if self.preferences.playSound {
                self.playSubtleCutSound()
            }
            if self.preferences.showHUD {
                self.hud.show(
                    symbolName: "scissors",
                    message: self.l10n.hudCut(count: payload.itemCount, singleName: payload.singleItemName),
                    accentColor: .blue
                )
            }
        }

        coordinator.onMoved = { [weak self] payload in
            guard let self else { return }
            if self.preferences.showHUD {
                self.hud.show(
                    symbolName: "checkmark.circle.fill",
                    message: self.l10n.hudMoved(count: payload.itemCount),
                    accentColor: .green
                )
            }
        }

        coordinator.onCancelled = { [weak self] in
            guard let self else { return }
            if self.preferences.showHUD {
                self.hud.show(
                    symbolName: "xmark.circle.fill",
                    message: self.l10n.hudCancelled,
                    accentColor: .secondary
                )
            }
        }
    }

    private func setupWorkspaceObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleIdentifier = app?.bundleIdentifier
            let processIdentifier = app?.processIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                if let processIdentifier {
                    self.eventTapController.handleFrontmostApplicationChanged(
                        bundleIdentifier: bundleIdentifier,
                        processIdentifier: processIdentifier
                    )
                } else {
                    let frontmost = NSWorkspace.shared.frontmostApplication
                    self.eventTapController.handleFrontmostApplicationChanged(
                        bundleIdentifier: frontmost?.bundleIdentifier,
                        processIdentifier: frontmost?.processIdentifier
                    )
                }
                self.coordinator.invalidateIfClipboardChanged()
            }
        }
    }

    private func setupReopenObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.reopenNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openSettingsWindow()
            }
        }
    }

    // MARK: - Accessibility & Event Tap

    private func checkAccessibilityAndStartTap(promptIfUntrusted: Bool) {
        let trusted: Bool
        if promptIfUntrusted {
            let key = "AXTrustedCheckOptionPrompt" as CFString
            let options = [key: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }

        let previousTrusted = statusModel.isAccessibilityTrusted
        let previousRunning = statusModel.isTapRunning

        statusModel.isAccessibilityTrusted = trusted

        if trusted {
            let started = eventTapController.start()
            statusModel.isTapRunning = started
            if started {
                stopPermissionPolling()
            }
        } else {
            eventTapController.stop()
            statusModel.isTapRunning = false
        }

        if previousTrusted != statusModel.isAccessibilityTrusted || previousRunning != statusModel.isTapRunning {
            updateStatusBarButton()
        }
    }

    private func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAccessibilityAndStartTap(promptIfUntrusted: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    @objc private func openAccessibilitySettings() {
        checkAccessibilityAndStartTap(promptIfUntrusted: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPermissionPolling()
    }

    // MARK: - Status Bar

    private func updateStatusItemVisibility() {
        if preferences.hideMenuBarIcon {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }

        updateStatusBarButton()
    }

    private func updateStatusBarButton() {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let alpha: CGFloat
        var title = ""

        if !statusModel.isAccessibilityTrusted || !statusModel.isTapRunning {
            symbolName = "exclamationmark.triangle"
            alpha = 1.0
        } else if !preferences.isEnabled {
            symbolName = "scissors"
            alpha = 0.45
        } else if let payload = statusModel.cutState.armedPayload {
            symbolName = "scissors"
            alpha = 1.0
            if preferences.showCountInMenuBar {
                title = " \(payload.itemCount)"
            }
        } else {
            symbolName = "scissors"
            alpha = 1.0
        }

        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: statusModel.cutState.isArmed ? .bold : .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: l10n.appName)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true

        button.image = image
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.title = title
        button.alphaValue = alpha

        if let payload = statusModel.cutState.armedPayload {
            button.toolTip = "\(l10n.appName) — \(l10n.statusCutReady(count: payload.itemCount))"
        } else if !statusModel.isAccessibilityTrusted {
            button.toolTip = "\(l10n.appName) — \(l10n.statusNeedsPermission)"
        } else if !preferences.isEnabled {
            button.toolTip = "\(l10n.appName) — \(l10n.statusPaused)"
        } else {
            button.toolTip = "\(l10n.appName) — \(l10n.statusActive)"
        }
    }

    private func animateStatusBarCutFeedback() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let button = statusItem?.button else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.09
            button.animator().alphaValue = 0.35
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let button = self?.statusItem?.button else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    button.animator().alphaValue = 1.0
                }
            }
        })
    }

    private func makeMenuSymbol(_ name: String, tint: NSColor? = nil) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let tint {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = (tint == nil)
        return image
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        coordinator.invalidateIfClipboardChanged()
        menu.removeAllItems()

        // Status header item (native SF Symbol, no emoji)
        let statusTitle: String
        let statusSymbol: String
        let statusTint: NSColor

        if !statusModel.isAccessibilityTrusted {
            statusTitle = l10n.statusNeedsPermission
            statusSymbol = "exclamationmark.triangle.fill"
            statusTint = .systemOrange
        } else if !statusModel.isTapRunning {
            statusTitle = l10n.statusTapError
            statusSymbol = "exclamationmark.triangle.fill"
            statusTint = .systemRed
        } else if !preferences.isEnabled {
            statusTitle = l10n.statusPaused
            statusSymbol = "pause.circle.fill"
            statusTint = .secondaryLabelColor
        } else if let payload = statusModel.cutState.armedPayload {
            statusTitle = l10n.statusCutReady(count: payload.itemCount)
            statusSymbol = "scissors"
            statusTint = .systemBlue
        } else {
            statusTitle = l10n.statusActive
            statusSymbol = "checkmark.circle.fill"
            statusTint = .systemGreen
        }

        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenuItem.image = makeMenuSymbol(statusSymbol, tint: statusTint)
        menu.addItem(statusMenuItem)

        if !statusModel.isAccessibilityTrusted || !statusModel.isTapRunning {
            let grantItem = NSMenuItem(
                title: l10n.menuGrantPermission,
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            grantItem.image = makeMenuSymbol("lock.shield")
            grantItem.target = self
            menu.addItem(grantItem)
        }

        // Currently armed cut files
        if let payload = statusModel.cutState.armedPayload {
            menu.addItem(.separator())

            let header = NSMenuItem(title: l10n.menuCutHeader, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let maxDisplayed = 5
            for url in payload.fileURLs.prefix(maxDisplayed) {
                let item = NSMenuItem(title: "  \(url.lastPathComponent)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 15, height: 15)
                item.image = icon
                menu.addItem(item)
            }

            if payload.fileURLs.count > maxDisplayed {
                let moreItem = NSMenuItem(
                    title: "  \(l10n.menuMoreItems(count: payload.fileURLs.count - maxDisplayed))",
                    action: nil,
                    keyEquivalent: ""
                )
                moreItem.isEnabled = false
                menu.addItem(moreItem)
            }

            let cancelItem = NSMenuItem(
                title: l10n.menuCancelCut,
                action: #selector(cancelCutFromMenu),
                keyEquivalent: ""
            )
            cancelItem.image = makeMenuSymbol("xmark.circle")
            cancelItem.target = self
            menu.addItem(cancelItem)
        }

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: preferences.isEnabled ? l10n.menuPause : l10n.menuEnable,
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.image = makeMenuSymbol(preferences.isEnabled ? "pause.circle" : "play.circle")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let settingsItem = NSMenuItem(
            title: l10n.menuPreferences,
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.image = makeMenuSymbol("gearshape")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: l10n.menuQuit,
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        preferences.isEnabled.toggle()
    }

    @objc private func cancelCutFromMenu() {
        coordinator.cancelCut(notifyUser: true)
    }

    @objc private func openSettingsWindow() {
        launchAtLogin.refresh()
        checkAccessibilityAndStartTap(promptIfUntrusted: false)
        if !statusModel.isAccessibilityTrusted || !statusModel.isTapRunning {
            startPermissionPolling()
        }

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = PreferencesView(
            preferences: preferences,
            status: statusModel,
            launchAtLogin: launchAtLogin,
            onOpenAccessibilitySettings: { [weak self] in
                self?.openAccessibilitySettings()
            },
            onRetryEventTap: { [weak self] in
                self?.checkAccessibilityAndStartTap(promptIfUntrusted: false)
            },
            onCancelCut: { [weak self] in
                self?.coordinator.cancelCut(notifyUser: true)
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = .preferredContentSize
        let containerController = LiquidGlassWindowController(child: hostingController)

        let window = NSWindow(contentViewController: containerController)
        window.title = l10n.settingsTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func playSubtleCutSound() {
        guard let sound = NSSound(named: NSSound.Name("Pop")) else { return }
        sound.volume = 0.35
        sound.play()
    }
}

@MainActor
private final class LiquidGlassWindowController: NSViewController {
    private let childController: NSViewController

    init(child: NSViewController) {
        self.childController = child
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        addChild(childController)
        let childView = childController.view

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = 20
            glassView.contentView = childView
            view = glassView
            return
        }
        #endif

        let visualView = NSVisualEffectView()
        visualView.material = .hudWindow
        visualView.blendingMode = .behindWindow
        visualView.state = .active
        childView.translatesAutoresizingMaskIntoConstraints = false
        visualView.addSubview(childView)
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: visualView.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: visualView.trailingAnchor),
            childView.topAnchor.constraint(equalTo: visualView.topAnchor),
            childView.bottomAnchor.constraint(equalTo: visualView.bottomAnchor),
        ])
        view = visualView
    }
}
