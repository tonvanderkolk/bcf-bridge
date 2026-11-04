import Foundation

/// Vertaalt één BCF2000-fader (7-bit CC) naar een Mackie-fader (14-bit Pitch Bend + touch) en terug.
public final class FaderBridge {
    public let index: Int // 0 = fader 1
    public var mapping: ControlMapping
    public var releaseMs: Int
    public var resyncMs = 150
    public var echoWindowMs = 150

    // Uitgangen: bytes plus een uitleg voor de log
    public var sendToLogic: ([UInt8], String) -> Void = { _, _ in }
    public var sendToBCF: ([UInt8], String) -> Void = { _, _ in }
    public var note: (String) -> Void = { _ in }

    let clock: BridgeClock

    public private(set) var touched = false
    private var touchGeneration = 0
    private var lastSentToLogic: Int?
    /// Laatst bekende stand van de fysieke fader (ontvangen of door ons gestuurd), 0-127
    public private(set) var bcfPosition: Int?
    private var lastSentToBCF: (value: Int, at: Double)?
    private var pendingFromLogic: Int?

    public init(index: Int, mapping: ControlMapping, releaseMs: Int, clock: BridgeClock) {
        self.index = index
        self.mapping = mapping
        self.releaseMs = releaseMs
        self.clock = clock
    }

    public func matches(_ m: [UInt8]) -> Bool {
        m.count == 3 && m[0] == 0xB0 | UInt8(mapping.channel - 1) && Int(m[1]) == mapping.cc
    }

    static func to14(_ v: Int) -> Int { (v << 7) | v } // 0 -> 0, 127 -> 16383
    static func to7(_ v: Int) -> Int { v >> 7 }

    // MARK: BCF2000 -> Logic

    public func fromBCF(value: Int) {
        // Echo van onze eigen motoropdracht negeren
        if !touched, let last = lastSentToBCF, last.value == value,
           (clock.now - last.at) * 1000 < Double(echoWindowMs) {
            note("Fader \(index + 1): echo van motor genegeerd (\(value))")
            return
        }
        bcfPosition = value

        if !touched {
            touched = true
            sendToLogic([0x90, UInt8(0x68 + index), 0x7F], "Fader \(index + 1) touch AAN (gesimuleerd)")
        }
        let v14 = Self.to14(value)
        if v14 != lastSentToLogic {
            lastSentToLogic = v14
            sendToLogic([0xE0 | UInt8(index), UInt8(v14 & 0x7F), UInt8(v14 >> 7)],
                        "Fader \(index + 1) = \(v14) (BCF \(value))")
        }
        touchGeneration += 1
        let gen = touchGeneration
        clock.after(ms: releaseMs) { [weak self] in
            guard let self, gen == self.touchGeneration else { return }
            self.release()
        }
    }

    private func release() {
        guard touched else { return }
        touched = false
        sendToLogic([0x90, UInt8(0x68 + index), 0x00], "Fader \(index + 1) touch UIT (na \(releaseMs) ms stilstand)")
        let gen = touchGeneration
        clock.after(ms: resyncMs) { [weak self] in
            guard let self, gen == self.touchGeneration, !self.touched else { return }
            if let p = self.pendingFromLogic {
                self.pendingFromLogic = nil
                if p != self.bcfPosition {
                    self.moveMotor(p, reason: "na loslaten, stand van Logic")
                }
            }
        }
    }

    // MARK: Logic -> BCF2000

    public func fromLogic(pitchBend v14: Int) {
        let v7 = Self.to7(v14)
        if touched {
            pendingFromLogic = v7
            note("Fader \(index + 1): feedback van Logic (\(v7)) tegengehouden, fader is aangeraakt")
            return
        }
        if v7 == bcfPosition {
            note("Fader \(index + 1): feedback van Logic (\(v7)) gelijk aan huidige stand, niet opnieuw gestuurd")
            return
        }
        moveMotor(v7, reason: "feedback van Logic")
    }

    private func moveMotor(_ v7: Int, reason: String) {
        bcfPosition = v7
        lastSentToBCF = (v7, clock.now)
        sendToBCF([0xB0 | UInt8(mapping.channel - 1), UInt8(mapping.cc), UInt8(v7)],
                  "Motorfader \(index + 1) naar \(v7) (\(reason))")
    }

    /// Bij afsluiten: zorgen dat Logic de fader niet als aangeraakt blijft zien.
    public func forceRelease() {
        if touched {
            touched = false
            touchGeneration += 1
            sendToLogic([0x90, UInt8(0x68 + index), 0x00], "Fader \(index + 1) touch UIT (afsluiten)")
        }
    }
}
