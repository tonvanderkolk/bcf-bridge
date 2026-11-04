import Foundation

/// Vertaalt een BCF2000-encoder naar een Mackie V-Pot (relatieve stappen) en de LED-krans terug.
public final class EncoderBridge {
    public let index: Int
    public var mapping: ControlMapping?
    public var idleMs: Int

    public var sendToLogic: ([UInt8], String) -> Void = { _, _ in }
    public var sendToBCF: ([UInt8], String) -> Void = { _, _ in }
    public var note: (String) -> Void = { _ in }

    let clock: BridgeClock
    /// Laatst bekende absolute stand van de encoder op de BCF2000
    public private(set) var lastAbs: Int?
    public private(set) var active = false
    private var generation = 0
    private var pendingRing: Int?

    public init(index: Int, mapping: ControlMapping?, idleMs: Int, clock: BridgeClock) {
        self.index = index
        self.mapping = mapping
        self.idleMs = idleMs
        self.clock = clock
    }

    var mode: EncoderMode { mapping?.encoderMode ?? .absolute }

    // MARK: BCF2000 -> Logic

    public func fromBCF(value: Int) {
        let delta: Int
        switch mode {
        case .absolute:
            guard let last = lastAbs else {
                lastAbs = value
                note("Encoder \(index + 1): eerste stand \(value) vastgelegd als beginpunt")
                return
            }
            delta = value - last
            lastAbs = value
        case .relativeTwosComplement:
            delta = value < 64 ? value : value - 128
        case .relativeOffset64:
            delta = value - 64
        }
        guard delta != 0 else { return }
        markActive()
        let steps = min(abs(delta), 15)
        let byte = UInt8(delta > 0 ? steps : 0x40 | steps)
        sendToLogic([0xB0, UInt8(0x10 + index), byte],
                    "V-Pot \(index + 1) \(delta > 0 ? "rechtsom" : "linksom") \(steps) stap(pen)")
    }

    private func markActive() {
        active = true
        generation += 1
        let gen = generation
        clock.after(ms: idleMs) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.active = false
            if let p = self.pendingRing {
                self.pendingRing = nil
                self.setEncoder(p, reason: "na draaien, stand van Logic")
            }
        }
    }

    // MARK: Logic -> BCF2000

    /// Waarde van de LED-krans (CC 0x30-0x37). Positie 1-11 in de laagste 4 bits.
    public func fromLogicRing(_ v: Int) {
        guard mode == .absolute else { return }
        let pos = v & 0x0F
        guard (1...11).contains(pos) else { return }
        let target = Int((Double(pos - 1) * 127.0 / 10.0).rounded())
        if active {
            pendingRing = target
            return
        }
        setEncoder(target, reason: "LED-krans van Logic (positie \(pos) van 11)")
    }

    private func setEncoder(_ target: Int, reason: String) {
        guard let m = mapping, target != lastAbs else { return }
        lastAbs = target
        sendToBCF([0xB0 | UInt8(m.channel - 1), UInt8(m.cc), UInt8(target)], "Encoder \(index + 1) naar \(target) (\(reason))")
    }
}
