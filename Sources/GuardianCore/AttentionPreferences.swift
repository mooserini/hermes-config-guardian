import Foundation

/// Guardian-owned interruption preferences.
///
/// These deliberately live in the app's defaults domain rather than beside
/// the guarded file. Changing how Guardian gets a person's attention must
/// never create another Hermes configuration proposal.
public struct AttentionPreferences {
    public static let soundKey = "attention.playSound"
    public static let openWindowKey = "attention.openReviewWindow"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var playsSound: Bool {
        defaults.object(forKey: Self.soundKey) as? Bool ?? true
    }

    public var opensReviewWindow: Bool {
        defaults.object(forKey: Self.openWindowKey) as? Bool ?? false
    }

    public func setPlaysSound(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.soundKey)
    }

    public func setOpensReviewWindow(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.openWindowKey)
    }
}
