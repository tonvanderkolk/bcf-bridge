import Foundation

/// Two languages: English (default) and Dutch. Dutch is used when it is the first preferred
/// language of the Mac, or when the environment variable BCF_BRIDGE_LANG is "nl".
/// The detailed MIDI trace in the log is always English.
public enum Language {
    public static let isDutch: Bool = {
        if let forced = ProcessInfo.processInfo.environment["BCF_BRIDGE_LANG"] {
            return forced.lowercased().hasPrefix("nl")
        }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("nl") ?? false
    }()
}

/// Returns the English or the Dutch text.
@inline(__always)
public func tr(_ en: String, _ nl: String) -> String { Language.isDutch ? nl : en }
