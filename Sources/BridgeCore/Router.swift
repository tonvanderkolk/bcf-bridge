import Foundation

/// Verdeelt berichten over alle faders, encoders en knoppen.
public final class Router {
    public private(set) var settings: BridgeSettings
    let clock: BridgeClock

    public var sendToLogic: ([UInt8], String) -> Void = { _, _ in }
    public var sendToBCF: ([UInt8], String) -> Void = { _, _ in }
    public var note: (String) -> Void = { _ in }

    public private(set) var faders: [FaderBridge] = []
    public private(set) var encoders: [EncoderBridge] = []
    private var buttons: [ButtonBridge] = []
    private var bcfHandlers: [Int: (Int) -> Void] = [:]

    public init(settings: BridgeSettings, clock: BridgeClock) {
        self.settings = settings
        self.clock = clock
        faders = (0..<8).map { FaderBridge(index: $0, mapping: settings.faders[$0], releaseMs: settings.touchReleaseMs, clock: clock) }
        encoders = (0..<8).map { EncoderBridge(index: $0, mapping: settings.encoders[$0], idleMs: settings.encoderIdleMs, clock: clock) }
        for f in faders {
            f.sendToLogic = { [unowned self] b, w in self.sendToLogic(b, w) }
            f.sendToBCF = { [unowned self] b, w in self.sendToBCF(b, w) }
            f.note = { [unowned self] t in self.note(t) }
        }
        for e in encoders {
            e.sendToLogic = { [unowned self] b, w in self.sendToLogic(b, w) }
            e.sendToBCF = { [unowned self] b, w in self.sendToBCF(b, w) }
            e.note = { [unowned self] t in self.note(t) }
        }
        rebuild()
    }

    /// Nieuwe instellingen overnemen. Faders en encoders houden hun toestand.
    public func update(_ s: BridgeSettings) {
        settings = s
        rebuild()
    }

    private func rebuild() {
        bcfHandlers = [:]
        buttons = []
        for (i, f) in faders.enumerated() {
            f.mapping = settings.faders[i]
            f.releaseMs = settings.touchReleaseMs
            if let m = f.mapping { bcfHandlers[m.key] = { [unowned f] v in f.fromBCF(value: v) } }
        }
        for (i, e) in encoders.enumerated() {
            e.mapping = settings.encoders[i]
            e.idleMs = settings.encoderIdleMs
            if let m = e.mapping { bcfHandlers[m.key] = { [unowned e] v in e.fromBCF(value: v) } }
        }
        func addButton(_ name: String, _ note: UInt8, _ m: ControlMapping?, led: Bool) {
            guard let m else { return }
            let b = ButtonBridge(name: name, mackieNote: note, mapping: m, hasLEDFeedback: led, clock: clock)
            b.sendToLogic = { [unowned self] bytes, w in self.sendToLogic(bytes, w) }
            b.sendToBCF = { [unowned self] bytes, w in self.sendToBCF(bytes, w) }
            buttons.append(b)
            bcfHandlers[m.key] = { [unowned b] v in b.fromBCF(value: v) }
        }
        for i in 0..<8 {
            addButton("\(settings.topRowFunction.label) \(i + 1)", settings.topRowFunction.noteBase + UInt8(i), settings.topRow[i], led: true)
            addButton("\(settings.bottomRowFunction.label) \(i + 1)", settings.bottomRowFunction.noteBase + UInt8(i), settings.bottomRow[i], led: true)
            addButton("V-Pot \(i + 1) indrukken", 0x20 + UInt8(i), settings.encoderPush[i], led: false)
        }
        for n in NavButton.allCases {
            addButton(n.label, n.note, settings.nav[n.rawValue], led: false)
        }
        for t in TransportButton.allCases {
            addButton(t.label, t.note, settings.transport[t.rawValue], led: true)
        }
    }

    // MARK: BCF2000 -> Logic

    /// Geeft false terug als het bericht nergens aan gekoppeld is.
    @discardableResult
    public func fromBCF(_ m: [UInt8]) -> Bool {
        guard m.count == 3, m[0] & 0xF0 == 0xB0 else { return false }
        let key = (Int(m[0] & 0x0F) << 8) | Int(m[1])
        guard let h = bcfHandlers[key] else { return false }
        h(Int(m[2]))
        return true
    }

    // MARK: Logic -> BCF2000

    public func fromLogic(_ m: [UInt8]) {
        guard let s = m.first, m.count == 3 else { return }
        let d1 = Int(m[1]), d2 = Int(m[2])
        switch s & 0xF0 {
        case 0xE0:
            let ch = Int(s & 0x0F)
            if ch < 8 { faders[ch].fromLogic(pitchBend: d1 | (d2 << 7)) }
        case 0xB0:
            if (0x30...0x37).contains(d1) { encoders[d1 - 0x30].fromLogicRing(d2) }
        case 0x90, 0x80:
            let vel = (s & 0xF0) == 0x80 ? 0 : d2
            for b in buttons where Int(b.mackieNote) == d1 && b.hasLEDFeedback {
                b.fromLogicLED(velocity: vel)
            }
        default:
            break
        }
    }

    public func releaseAll() {
        faders.forEach { $0.forceRelease() }
    }
}
