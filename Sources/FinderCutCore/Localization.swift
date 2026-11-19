import Foundation

public enum AppLanguage: String, Sendable, Equatable {
    case french = "fr"
    case english = "en"

    public static var current: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("fr") ? .french : .english
    }
}

public struct ShortcutReferenceItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let keys: String
    public let description: String

    public init(id: String, keys: String, description: String) {
        self.id = id
        self.keys = keys
        self.description = description
    }
}

public struct L10n: Sendable {
    public let language: AppLanguage

    public init(language: AppLanguage = .current) {
        self.language = language
    }

    public static var current: L10n { L10n(language: .current) }

    private func t(fr: String, en: String) -> String {
        language == .french ? fr : en
    }

    // MARK: - General
    public var appName: String { "FinderCut" }

    public var appSubtitle: String {
        t(
            fr: "Couper (⌘X) et déplacer (⌘V) des fichiers dans le Finder.",
            en: "Cut (⌘X) and move (⌘V) files directly in Finder."
        )
    }

    // MARK: - Status (Full — for Menu & Tooltips)
    public var statusActive: String {
        t(fr: "Actif dans le Finder", en: "Active in Finder")
    }

    public var statusPaused: String {
        t(fr: "En pause", en: "Paused")
    }

    public var statusNeedsPermission: String {
        t(fr: "Autorisation d'Accessibilité requise", en: "Accessibility Permission Required")
    }

    public var statusTapError: String {
        t(fr: "Interception clavier inactive", en: "Keyboard event tap inactive")
    }

    public func statusCutReady(count: Int) -> String {
        if language == .french {
            return count == 1 ? "1 élément prêt à déplacer (⌘V)" : "\(count) éléments prêts à déplacer (⌘V)"
        } else {
            return count == 1 ? "1 item ready to move (⌘V)" : "\(count) items ready to move (⌘V)"
        }
    }

    // MARK: - Status Pill (Concise — for Settings Header)
    public var statusPillActive: String {
        t(fr: "Actif", en: "Active")
    }

    public var statusPillPaused: String {
        t(fr: "En pause", en: "Paused")
    }

    public var statusPillPermission: String {
        t(fr: "Autorisation requise", en: "Permission needed")
    }

    public var statusPillError: String {
        t(fr: "Inactif", en: "Inactive")
    }

    public func statusPillCutReady(count: Int) -> String {
        if language == .french {
            return count == 1 ? "1 prêt" : "\(count) prêts"
        } else {
            return "\(count) ready"
        }
    }

    // MARK: - Menu Bar
    public var menuEnable: String {
        t(fr: "Activer FinderCut", en: "Enable FinderCut")
    }

    public var menuPause: String {
        t(fr: "Mettre en pause", en: "Pause FinderCut")
    }

    public var menuCutHeader: String {
        t(fr: "Éléments coupés", en: "Cut items")
    }

    public var menuCancelCut: String {
        t(fr: "Annuler la coupe", en: "Cancel Cut")
    }

    public var menuGrantPermission: String {
        t(fr: "Autoriser l'Accessibilité…", en: "Grant Accessibility Access…")
    }

    public var menuPreferences: String {
        t(fr: "Réglages…", en: "Settings…")
    }

    public var menuQuit: String {
        t(fr: "Quitter FinderCut", en: "Quit FinderCut")
    }

    public func menuMoreItems(count: Int) -> String {
        t(fr: "et \(count) de plus…", en: "and \(count) more…")
    }

    // MARK: - HUD
    public func hudCut(count: Int, singleName: String?) -> String {
        if count == 1, let name = singleName, !name.isEmpty {
            return t(fr: "Coupé : \(name)", en: "Cut: \(name)")
        }
        if language == .french {
            return count == 1 ? "1 élément coupé" : "\(count) éléments coupés"
        } else {
            return count == 1 ? "Cut 1 item" : "Cut \(count) items"
        }
    }

    public func hudMoved(count: Int) -> String {
        if language == .french {
            return count == 1 ? "1 élément déplacé" : "\(count) éléments déplacés"
        } else {
            return count == 1 ? "Moved 1 item" : "Moved \(count) items"
        }
    }

    public var hudCancelled: String {
        t(fr: "Coupe annulée", en: "Cut cancelled")
    }

    // MARK: - Settings
    public var settingsTitle: String {
        t(fr: "Réglages FinderCut", en: "FinderCut Settings")
    }

    public var settingsPermissionTitle: String {
        t(fr: "Autorisation d'Accessibilité requise", en: "Accessibility Permission Required")
    }

    public var settingsPermissionDescription: String {
        t(
            fr: "FinderCut a besoin de l'accès Accessibilité pour intercepter ⌘X et ⌘V uniquement dans le Finder, tout en préservant la saisie de texte.",
            en: "FinderCut needs Accessibility access to intercept ⌘X and ⌘V exclusively in Finder while preserving text editing."
        )
    }

    public var settingsPermissionHint: String {
        t(
            fr: "Après une mise à jour, supprimez FinderCut de la liste (−) puis réajoutez-le si l'option apparaît déjà cochée.",
            en: "After an update, remove FinderCut from the list (−) and re-add it if it already appears enabled."
        )
    }

    public var settingsTapErrorTitle: String {
        t(fr: "Impossible de démarrer l'interception clavier", en: "Could not start keyboard interception")
    }

    public var settingsTapErrorDescription: String {
        t(
            fr: "L'autorisation semble obsolète. Désactivez puis réactivez FinderCut dans Réglages d'Accessibilité, ou cliquez sur Réessayer.",
            en: "The permission entry may be stale. Toggle FinderCut off and back on in Accessibility Settings, or click Retry."
        )
    }

    public var settingsRetryButton: String {
        t(fr: "Réessayer", en: "Retry")
    }

    public var settingsOpenAccessibility: String {
        t(fr: "Ouvrir Réglages d'Accessibilité", en: "Open Accessibility Settings")
    }

    public var settingsSectionBehavior: String {
        t(fr: "Comportement", en: "Behavior")
    }

    public var settingsToggleEnabled: String {
        t(fr: "Activer ⌘X / ⌘V dans le Finder", en: "Enable ⌘X / ⌘V in Finder")
    }

    public var settingsToggleCancelEscape: String {
        t(fr: "Annuler la coupe avec Échap", en: "Cancel cut with Escape")
    }

    public var settingsToggleHUD: String {
        t(fr: "Afficher l'indicateur flottant (HUD)", en: "Show floating feedback (HUD)")
    }

    public var settingsToggleSound: String {
        t(fr: "Jouer un son discret lors de la coupe", en: "Play subtle sound on cut")
    }

    public var settingsToggleShowCount: String {
        t(fr: "Afficher le compteur dans la barre des menus", en: "Show item count in menu bar")
    }

    public var settingsToggleHideMenuBar: String {
        t(fr: "Masquer l'icône de la barre des menus", en: "Hide menu bar icon")
    }

    public var settingsHideMenuBarHint: String {
        t(
            fr: "Relancez FinderCut depuis Applications pour rouvrir cette fenêtre.",
            en: "Reopen FinderCut from Applications to show this window again."
        )
    }

    public var settingsSectionSystem: String {
        t(fr: "Système", en: "System")
    }

    public var settingsToggleLaunchAtLogin: String {
        t(fr: "Lancer à l'ouverture de session", en: "Launch at login")
    }

    public var settingsLaunchAtLoginUnsupported: String {
        t(
            fr: "Disponible lorsque l'application est lancée depuis FinderCut.app.",
            en: "Available when running from the installed FinderCut.app bundle."
        )
    }

    public var settingsShortcutsTitle: String {
        t(fr: "Raccourcis dans le Finder", en: "Finder Shortcuts")
    }

    public var settingsMenuBarOptions: String {
        t(fr: "Options barre des menus", en: "Menu bar options")
    }

    public var settingsShortcutFooter: String {
        t(fr: "⌘X couper  ·  ⌘V déplacer  ·  Échap annuler", en: "⌘X cut  ·  ⌘V move  ·  Esc cancel")
    }

    public var settingsPermissionShort: String {
        t(
            fr: "Activez FinderCut dans Accessibilité. En cas de mise à jour, supprimez l'ancienne entrée (−) puis réajoutez-la (+).",
            en: "Enable FinderCut in Accessibility. After an update, remove the old entry (−) and add it again (+)."
        )
    }

    public var settingsShortcuts: [ShortcutReferenceItem] {
        if language == .french {
            return [
                ShortcutReferenceItem(id: "cut", keys: "⌘X", description: "Couper les éléments sélectionnés"),
                ShortcutReferenceItem(id: "paste", keys: "⌘V", description: "Déplacer dans le dossier ouvert"),
                ShortcutReferenceItem(id: "escape", keys: "Échap", description: "Annuler la coupe en cours"),
                ShortcutReferenceItem(id: "undo", keys: "⌘Z", description: "Annuler le déplacement (natif Finder)"),
            ]
        } else {
            return [
                ShortcutReferenceItem(id: "cut", keys: "⌘X", description: "Cut selected items"),
                ShortcutReferenceItem(id: "paste", keys: "⌘V", description: "Move into open folder"),
                ShortcutReferenceItem(id: "escape", keys: "Esc", description: "Cancel pending cut"),
                ShortcutReferenceItem(id: "undo", keys: "⌘Z", description: "Undo move (native Finder)"),
            ]
        }
    }
}
