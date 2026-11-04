import Foundation

public struct ControlMapping: Codable, Equatable {
    /// MIDI-kanaal 1-16
    public var channel: Int
    public var cc: Int
    public init(channel: Int, cc: Int) { self.channel = channel; self.cc = cc }
}

public struct BridgeSettings: Codable, Equatable {
    public var version = 1
    /// Standaard: BCF2000 fabriekspreset 1, fader 1 = CC 81 op kanaal 1
    public var fader1 = ControlMapping(channel: 1, cc: 81)
    public var touchReleaseMs = 400

    public init() {}

    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BCF Bridge", isDirectory: true)
    }
    public static var file: URL { folder.appendingPathComponent("mapping.json") }
    public static var backup: URL { folder.appendingPathComponent("mapping.vorige.json") }

    public static func load() -> BridgeSettings {
        guard let data = try? Data(contentsOf: file),
              let s = try? JSONDecoder().decode(BridgeSettings.self, from: data) else {
            return BridgeSettings()
        }
        return s
    }

    /// Slaat op en bewaart de vorige versie als backup.
    public func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if fm.fileExists(atPath: Self.file.path) {
            try? fm.removeItem(at: Self.backup)
            try fm.copyItem(at: Self.file, to: Self.backup)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Self.file, options: .atomic)
    }
}
