import AppKit
import SwiftUI

@MainActor
final class HUDOverlayController {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var presentationToken: UInt64 = 0

    func show(
        symbolName: String,
        message: String,
        accentColor: Color = .accentColor,
        duration: TimeInterval = 1.25
    ) {
        dismissWorkItem?.cancel()
        presentationToken &+= 1
        let currentToken = presentationToken

        let hudView = HUDPillView(symbolName: symbolName, message: message, accentColor: accentColor)
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let width = max(168, min(368, ceil(fittingSize.width)))
        let height = max(44, ceil(fittingSize.height))

        let targetScreen = activeScreen()
        let screenFrame = targetScreen.visibleFrame
        let originX = round(screenFrame.midX - (width / 2))
        let originY = round(screenFrame.minY + 72)

        let panel = ensurePanel()
        let wasVisible = panel.isVisible && panel.alphaValue > 0.1
        panel.contentView = hostingView
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if wasVisible || reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss(token: currentToken)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func dismiss(token: UInt64) {
        guard presentationToken == token, let panel else { return }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard self?.presentationToken == token else { return }
                panel?.orderOut(nil)
            }
        })
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    private func activeScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}

private struct HUDPillView: View {
    let symbolName: String
    let message: String
    let accentColor: Color

    var body: some View {
        let content = HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentColor)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: 360)
        .fixedSize(horizontal: false, vertical: true)

        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(
                    FallbackVisualEffect(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(Capsule())
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

private struct FallbackVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
