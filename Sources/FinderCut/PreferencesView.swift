import AppKit
import FinderCutCore
import SwiftUI

@MainActor
final class AppStatusModel: ObservableObject {
    @Published var isAccessibilityTrusted: Bool = false
    @Published var isTapRunning: Bool = false
    @Published var cutState: CutState = .idle
}

struct PreferencesView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var status: AppStatusModel
    @ObservedObject var launchAtLogin: LaunchAtLoginManager

    let onOpenAccessibilitySettings: () -> Void
    let onRetryEventTap: () -> Void
    let onCancelCut: () -> Void

    @State private var showMenuBarOptions = false

    private let l10n = L10n.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            if !status.isAccessibilityTrusted {
                permissionCard(isTapError: false)
            } else if !status.isTapRunning {
                permissionCard(isTapError: true)
            }

            if let payload = status.cutState.armedPayload {
                activeCutPill(payload: payload)
            }

            controlsList

            footerShortcuts
        }
        .padding(.top, 36)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(width: 344)
        .animation(.easeOut(duration: 0.18), value: status.isAccessibilityTrusted)
        .animation(.easeOut(duration: 0.18), value: status.isTapRunning)
        .animation(.easeOut(duration: 0.18), value: status.cutState)
        .animation(.easeOut(duration: 0.16), value: showMenuBarOptions)
        .animation(.easeOut(duration: 0.16), value: preferences.hideMenuBarIcon)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 11) {
            appGlyph

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.appName)
                    .font(.system(size: 15.5, weight: .semibold))

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $preferences.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(l10n.settingsToggleEnabled)
        }
        .padding(.horizontal, 4)
    }

    private var appGlyph: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let icon = Image(systemName: "scissors")
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.56, blue: 1.00),
                        Color(red: 0.28, green: 0.36, blue: 0.94),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: shape
            )
            .overlay(
                shape.strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 3, y: 1.5)

        return icon.accessibilityHidden(true)
    }

    private var statusColor: Color {
        if !status.isAccessibilityTrusted { return .orange }
        if !status.isTapRunning { return .red }
        if !preferences.isEnabled { return .secondary }
        if status.cutState.isArmed { return .blue }
        return .green
    }

    private var statusText: String {
        if !status.isAccessibilityTrusted { return l10n.statusPillPermission }
        if !status.isTapRunning { return l10n.statusPillError }
        if !preferences.isEnabled { return l10n.statusPillPaused }
        if let payload = status.cutState.armedPayload {
            return l10n.statusPillCutReady(count: payload.itemCount)
        }
        return l10n.statusPillActive
    }

    // MARK: - Permission / Active Cut

    private func permissionCard(isTapError: Bool) -> some View {
        let tint: Color = isTapError ? .red : .orange
        let symbolName = isTapError ? "exclamationmark.triangle" : "lock.shield"
        let title = isTapError ? l10n.settingsTapErrorTitle : l10n.settingsPermissionTitle
        let message = isTapError ? l10n.settingsTapErrorDescription : l10n.settingsPermissionShort

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Spacer()

                if isTapError {
                    GlassActionButton(title: l10n.settingsRetryButton, prominent: false, action: onRetryEventTap)
                }

                GlassActionButton(title: l10n.settingsOpenAccessibility, prominent: true, action: onOpenAccessibilitySettings)
            }
        }
        .padding(12)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.75)
        )
    }

    private func activeCutPill(payload: CutPayload) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "scissors")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.statusCutReady(count: payload.itemCount))
                    .font(.system(size: 12, weight: .semibold))

                Text(payload.fileURLs.prefix(2).map(\.lastPathComponent).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            GlassActionButton(
                title: l10n.language == .french ? "Annuler" : "Cancel",
                prominent: false,
                action: onCancelCut
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.24), lineWidth: 0.75)
        )
    }

    // MARK: - Controls

    private var controlsList: some View {
        VStack(spacing: 0) {
            GlassToggleRow(title: l10n.settingsToggleCancelEscape, isOn: $preferences.cancelWithEscape)
            subtleDivider

            GlassToggleRow(title: l10n.settingsToggleHUD, isOn: $preferences.showHUD)
            subtleDivider

            GlassToggleRow(title: l10n.settingsToggleSound, isOn: $preferences.playSound)
            subtleDivider

            GlassToggleRow(
                title: l10n.settingsToggleLaunchAtLogin,
                subtitle: launchAtLogin.isSupported ? nil : l10n.settingsLaunchAtLoginUnsupported,
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ),
                isDisabled: !launchAtLogin.isSupported
            )
            subtleDivider

            Button {
                showMenuBarOptions.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(l10n.settingsMenuBarOptions)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showMenuBarOptions ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if showMenuBarOptions {
                subtleDivider
                GlassToggleRow(
                    title: l10n.settingsToggleShowCount,
                    isOn: $preferences.showCountInMenuBar,
                    isDisabled: preferences.hideMenuBarIcon
                )
                subtleDivider
                GlassToggleRow(
                    title: l10n.settingsToggleHideMenuBar,
                    subtitle: preferences.hideMenuBarIcon ? l10n.settingsHideMenuBarHint : nil,
                    isOn: $preferences.hideMenuBarIcon
                )
            }
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
        )
    }

    private var subtleDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 12)
    }

    // MARK: - Footer

    private var footerShortcuts: some View {
        Text(l10n.settingsShortcutFooter)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
    }
}

// MARK: - Controls

private struct GlassActionButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        if prominent {
            Button(title, action: action)
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else {
            Button(title, action: action)
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

private struct GlassToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isDisabled ? .secondary : .primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(isDisabled)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
