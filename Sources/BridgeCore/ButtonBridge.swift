import Foundation

/// Vertaalt een BCF2000-knop (CC) naar een Mackie-knop (Note On) en het lampje terug.
public final class ButtonBridge {
    public let name: String
    public let mackieNote: UInt8
    public let mapping: ControlMapping
    /// Stuurt Logic zelf de stand van het lampje terug? Zo niet, dan zet de bridge het lampje weer uit.
    public let hasLEDFeedback: Bool

    public var sendToLogic: ([UInt8], String) -> Void = { _, _ in }
    public var sendToBCF: ([UInt8], String) -> Void = { _, _ in }

    let clock: BridgeClock
    /// Stand van het lampje op de BCF2000 zoals wij die kennen
    private var ledState: Int?

    public init(name: String, mackieNote: UInt8, mapping: ControlMapping, hasLEDFeedback: Bool, clock: BridgeClock) {
        self.name = name
        self.mackieNote = mackieNote
        self.mapping = mapping
        self.hasLEDFeedback = hasLEDFeedback
        self.clock = clock
    }

    public func fromBCF(value: Int) {
        switch mapping.buttonMode ?? .toggle {
        case .toggle:
            // Een toggle-knop stuurt per druk één bericht: altijd één complete klik naar Logic
            ledState = value
            sendToLogic([0x90, mackieNote, 0x7F], "\(name) ingedrukt")
            sendToLogic([0x90, mackieNote, 0x00], "\(name) losgelaten")
            if !hasLEDFeedback {
                clock.after(ms: 120) { [weak self] in self?.setLED(0, reason: "geen lampje bij deze functie") }
            }
        case .momentary:
            sendToLogic([0x90, mackieNote, value > 0 ? 0x7F : 0x00], "\(name) \(value > 0 ? "ingedrukt" : "losgelaten")")
        }
    }

    /// Lampjesbericht van Logic: 127 aan, 1 knipperen, 0 uit.
    public func fromLogicLED(velocity: Int) {
        setLED(velocity > 0 ? 127 : 0, reason: velocity == 1 ? "Logic: knipperen (BCF toont aan)" : "lampje van Logic")
    }

    private func setLED(_ v: Int, reason: String) {
        guard v != ledState else { return }
        ledState = v
        sendToBCF([0xB0 | UInt8(mapping.channel - 1), UInt8(mapping.cc), UInt8(v)],
                  "\(name) lampje \(v > 0 ? "aan" : "uit") (\(reason))")
    }
}
