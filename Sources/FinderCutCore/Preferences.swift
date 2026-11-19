import Combine
import Foundation

@MainActor
public final class PreferencesStore: ObservableObject {
    private enum Keys {
        static let isEnabled = "FinderCut.isEnabled"
        static let cancelWithEscape = "FinderCut.cancelWithEscape"
        static let showHUD = "FinderCut.showHUD"
        static let playSound = "FinderCut.playSound"
        static let showCountInMenuBar = "FinderCut.showCountInMenuBar"
        static let hideMenuBarIcon = "FinderCut.hideMenuBarIcon"
    }

    private let defaults: UserDefaults

    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published public var cancelWithEscape: Bool {
        didSet { defaults.set(cancelWithEscape, forKey: Keys.cancelWithEscape) }
    }

    @Published public var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Keys.showHUD) }
    }

    @Published public var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Keys.playSound) }
    }

    @Published public var showCountInMenuBar: Bool {
        didSet { defaults.set(showCountInMenuBar, forKey: Keys.showCountInMenuBar) }
    }

    @Published public var hideMenuBarIcon: Bool {
        didSet { defaults.set(hideMenuBarIcon, forKey: Keys.hideMenuBarIcon) }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults

        self.isEnabled = userDefaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.cancelWithEscape = userDefaults.object(forKey: Keys.cancelWithEscape) as? Bool ?? true
        self.showHUD = userDefaults.object(forKey: Keys.showHUD) as? Bool ?? true
        self.playSound = userDefaults.object(forKey: Keys.playSound) as? Bool ?? false
        self.showCountInMenuBar = userDefaults.object(forKey: Keys.showCountInMenuBar) as? Bool ?? true
        self.hideMenuBarIcon = userDefaults.object(forKey: Keys.hideMenuBarIcon) as? Bool ?? false
    }
}
