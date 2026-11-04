import Foundation

// MARK: Soorten

public enum ButtonFunction: String, Codable, CaseIterable {
    case rec, solo, mute, select

    public var noteBase: UInt8 {
        switch self {
        case .rec: return 0x00
        case .solo: return 0x08
        case .mute: return 0x10
        case .select: return 0x18
        }
    }

    public var label: String {
        switch self {
        case .rec: return "Rec"
        case .solo: return "Solo"
        case .mute: return "Mute"
        case .select: return "Select"
        }
    }
}

public enum EncoderMode: String, Codable {
    /// Encoder stuurt een stand 0-127 (BCF-fabriekspreset)
    case absolute
    /// 1..63 rechtsom, 127..65 linksom
    case relativeTwosComplement
    /// 65.. rechtsom, 63.. linksom
    case relativeOffset64
}

public enum ButtonMode: String, Codable {
    /// Elke druk geeft één bericht (127 of 0 om en om)
    case toggle
    /// 127 bij indrukken, 0 bij loslaten
    case momentary
}

public enum NavButton: String, Codable, CaseIterable {
    case bankLeft, bankRight, channelLeft, channelRight

    public var note: UInt8 {
        switch self {
        case .bankLeft: return 0x2E
        case .bankRight: return 0x2F
        case .channelLeft: return 0x30
        case .channelRight: return 0x31
        }
    }

    public var label: String {
        switch self {
        case .bankLeft: return "Bank links"
        case .bankRight: return "Bank rechts"
        case .channelLeft: return "Kanaal links"
        case .channelRight: return "Kanaal rechts"
        }
    }

    public var command: String {
        switch self {
        case .bankLeft: return "bankleft"
        case .bankRight: return "bankright"
        case .channelLeft: return "chanleft"
        case .channelRight: return "chanright"
        }
    }
}

public enum TransportButton: String, Codable, CaseIterable {
    case rewind, forward, stop, play, record

    public var note: UInt8 {
        switch self {
        case .rewind: return 0x5B
        case .forward: return 0x5C
        case .stop: return 0x5D
        case .play: return 0x5E
        case .record: return 0x5F
        }
    }

    public var label: String {
        switch self {
        case .rewind: return "Terugspoelen"
        case .forward: return "Vooruitspoelen"
        case .stop: return "Stop"
        case .play: return "Play"
        case .record: return "Record"
        }
    }
}

// MARK: Mapping van één bedieningselement

public struct ControlMapping: Codable, Equatable {
    /// MIDI-kanaal 1-16
    public var channel: Int
    public var cc: Int
    public var encoderMode: EncoderMode?
    public var buttonMode: ButtonMode?

    public init(channel: Int, cc: Int, encoderMode: EncoderMode? = nil, buttonMode: ButtonMode? = nil) {
        self.channel = channel
        self.cc = cc
        self.encoderMode = encoderMode
        self.buttonMode = buttonMode
    }

    /// Unieke sleutel voor kanaal + CC
    public var key: Int { ((channel - 1) << 8) | cc }

    public var short: String {
        var s = "CC \(cc) kan.\(channel)"
        if let e = encoderMode { s += " (\(e == .absolute ? "absoluut" : "relatief"))" }
        if let b = buttonMode { s += " (\(b == .toggle ? "toggle" : "momentary"))" }
        return s
    }
}

// MARK: Leerdoelen

public enum LearnTarget: Hashable {
    case fader(Int), encoder(Int), push(Int), top(Int), bottom(Int)
    case nav(NavButton), transport(TransportButton)

    public enum Kind { case fader, encoder, button }

    public var kind: Kind {
        switch self {
        case .fader: return .fader
        case .encoder: return .encoder
        default: return .button
        }
    }

    public func label(_ s: BridgeSettings) -> String {
        switch self {
        case .fader(let i): return "Fader \(i + 1)"
        case .encoder(let i): return "Encoder \(i + 1) (draaien)"
        case .push(let i): return "Encoder \(i + 1) indrukken"
        case .top(let i): return "Bovenste knoprij, knop \(i + 1) (\(s.topRowFunction.label))"
        case .bottom(let i): return "Onderste knoprij, knop \(i + 1) (\(s.bottomRowFunction.label))"
        case .nav(let n): return n.label
        case .transport(let t): return t.label
        }
    }

    public var instruction: String {
        switch kind {
        case .fader: return "beweeg de fader"
        case .encoder: return "draai de encoder een paar tikken rechtsom"
        case .button: return "druk de knop één keer kort in"
        }
    }

    /// Volgorde van "alles leren". Encoder indrukken zit er niet in (los te leren).
    public static var learnAllOrder: [LearnTarget] {
        (0..<8).map { .fader($0) } + (0..<8).map { .encoder($0) }
            + (0..<8).map { .top($0) } + (0..<8).map { .bottom($0) }
            + NavButton.allCases.map { .nav($0) } + TransportButton.allCases.map { .transport($0) }
    }

    /// Leest bijvoorbeeld "fader 3", "encoder 2", "push 1", "top 4", "bottom 5", "bankleft", "play".
    public static func parse(_ words: [String]) -> LearnTarget? {
        guard let first = words.first else { return nil }
        if words.count >= 2, let n = Int(words[1]), (1...8).contains(n) {
            let i = n - 1
            switch first {
            case "fader": return .fader(i)
            case "encoder", "pot": return .encoder(i)
            case "push": return .push(i)
            case "top", "boven": return .top(i)
            case "bottom", "onder": return .bottom(i)
            default: return nil
            }
        }
        if let n = NavButton.allCases.first(where: { $0.command == first }) { return .nav(n) }
        if let t = TransportButton.allCases.first(where: { $0.rawValue == first }) { return .transport(t) }
        return nil
    }
}

// MARK: Instellingen

public struct BridgeSettings: Codable, Equatable {
    public var version = 2
    public var faders: [ControlMapping?]
    public var encoders: [ControlMapping?]
    public var encoderPush: [ControlMapping?]
    public var topRow: [ControlMapping?]
    public var bottomRow: [ControlMapping?]
    public var topRowFunction: ButtonFunction = .mute
    public var bottomRowFunction: ButtonFunction = .solo
    public var nav: [String: ControlMapping] = [:]
    public var transport: [String: ControlMapping] = [:]
    public var touchReleaseMs = 400
    public var encoderIdleMs = 300

    /// Standaard: BCF2000 fabriekspreset 1 (faders CC 81-88, encoders CC 1-8, knoprijen CC 65-72 en 73-80).
    public init() {
        faders = (0..<8).map { ControlMapping(channel: 1, cc: 81 + $0) }
        encoders = (0..<8).map { ControlMapping(channel: 1, cc: 1 + $0, encoderMode: .absolute) }
        encoderPush = Array(repeating: nil, count: 8)
        topRow = (0..<8).map { ControlMapping(channel: 1, cc: 65 + $0, buttonMode: .toggle) }
        bottomRow = (0..<8).map { ControlMapping(channel: 1, cc: 73 + $0, buttonMode: .toggle) }
    }

    enum CodingKeys: String, CodingKey {
        case version, faders, encoders, encoderPush, topRow, bottomRow, topRowFunction, bottomRowFunction
        case nav, transport, touchReleaseMs, encoderIdleMs, fader1
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func row(_ k: CodingKeys, _ fallback: [ControlMapping?]) -> [ControlMapping?] {
            guard let r = try? c.decodeIfPresent([ControlMapping?].self, forKey: k) else { return fallback }
            return (0..<8).map { $0 < r.count ? r[$0] : nil }
        }
        faders = row(.faders, faders)
        encoders = row(.encoders, encoders)
        encoderPush = row(.encoderPush, encoderPush)
        topRow = row(.topRow, topRow)
        bottomRow = row(.bottomRow, bottomRow)
        // Versie 1 had alleen fader1
        if let f1 = try? c.decodeIfPresent(ControlMapping.self, forKey: .fader1) { faders[0] = f1 }
        topRowFunction = (try? c.decodeIfPresent(ButtonFunction.self, forKey: .topRowFunction)) ?? topRowFunction
        bottomRowFunction = (try? c.decodeIfPresent(ButtonFunction.self, forKey: .bottomRowFunction)) ?? bottomRowFunction
        nav = (try? c.decodeIfPresent([String: ControlMapping].self, forKey: .nav)) ?? nav
        transport = (try? c.decodeIfPresent([String: ControlMapping].self, forKey: .transport)) ?? transport
        touchReleaseMs = (try? c.decodeIfPresent(Int.self, forKey: .touchReleaseMs)) ?? touchReleaseMs
        encoderIdleMs = (try? c.decodeIfPresent(Int.self, forKey: .encoderIdleMs)) ?? encoderIdleMs
        version = 2
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(faders, forKey: .faders)
        try c.encode(encoders, forKey: .encoders)
        try c.encode(encoderPush, forKey: .encoderPush)
        try c.encode(topRow, forKey: .topRow)
        try c.encode(bottomRow, forKey: .bottomRow)
        try c.encode(topRowFunction, forKey: .topRowFunction)
        try c.encode(bottomRowFunction, forKey: .bottomRowFunction)
        try c.encode(nav, forKey: .nav)
        try c.encode(transport, forKey: .transport)
        try c.encode(touchReleaseMs, forKey: .touchReleaseMs)
        try c.encode(encoderIdleMs, forKey: .encoderIdleMs)
    }

    // MARK: Per leerdoel lezen en schrijven

    public static var allTargets: [LearnTarget] {
        LearnTarget.learnAllOrder + (0..<8).map { .push($0) }
    }

    public func mapping(for t: LearnTarget) -> ControlMapping? {
        switch t {
        case .fader(let i): return faders[i]
        case .encoder(let i): return encoders[i]
        case .push(let i): return encoderPush[i]
        case .top(let i): return topRow[i]
        case .bottom(let i): return bottomRow[i]
        case .nav(let n): return nav[n.rawValue]
        case .transport(let x): return transport[x.rawValue]
        }
    }

    public mutating func set(_ m: ControlMapping?, for t: LearnTarget) {
        switch t {
        case .fader(let i): faders[i] = m
        case .encoder(let i): encoders[i] = m
        case .push(let i): encoderPush[i] = m
        case .top(let i): topRow[i] = m
        case .bottom(let i): bottomRow[i] = m
        case .nav(let n): nav[n.rawValue] = m
        case .transport(let x): transport[x.rawValue] = m
        }
    }

    /// Zet een mapping en haalt dezelfde CC weg bij andere elementen. Geeft de elementen terug die hem kwijt zijn.
    @discardableResult
    public mutating func assign(_ m: ControlMapping, to t: LearnTarget) -> [LearnTarget] {
        var cleared: [LearnTarget] = []
        for other in Self.allTargets where other != t {
            if mapping(for: other)?.key == m.key {
                set(nil, for: other)
                cleared.append(other)
            }
        }
        set(m, for: t)
        return cleared
    }

    // MARK: Bestand

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

    public func save(makeBackup: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if makeBackup, fm.fileExists(atPath: Self.file.path) {
            try? fm.removeItem(at: Self.backup)
            try fm.copyItem(at: Self.file, to: Self.backup)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Self.file, options: .atomic)
    }
}
