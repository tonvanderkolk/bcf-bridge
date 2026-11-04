import Foundation

/// Leert welk BCF2000-element bij welk doel hoort, één voor één of allemaal achter elkaar.
public final class Learner {
    let clock: BridgeClock

    public var prompt: (LearnTarget) -> Void = { _ in }
    public var learned: (LearnTarget, ControlMapping, String) -> Void = { _, _, _ in }
    public var finished: (String) -> Void = { _ in }

    public private(set) var current: LearnTarget?
    private var queue: [LearnTarget] = []
    private var capture: (key: Int, channel: Int, cc: Int, values: [Int])?
    private var usedThisSession: Set<Int> = []
    private var waiting = false
    private var generation = 0

    public var isActive: Bool { current != nil }

    public init(clock: BridgeClock) { self.clock = clock }

    public func start(_ targets: [LearnTarget]) {
        queue = targets
        usedThisSession = []
        next()
    }

    public func skip() {
        guard current != nil else { return }
        capture = nil
        generation += 1
        next()
    }

    public func stop() {
        guard current != nil else { return }
        current = nil
        queue = []
        capture = nil
        generation += 1
        finished(tr("Learning stopped", "Leren gestopt"))
    }

    private func next() {
        capture = nil
        waiting = false
        guard !queue.isEmpty else {
            if current != nil { current = nil; finished(tr("Learning finished", "Leren klaar")) }
            return
        }
        current = queue.removeFirst()
        prompt(current!)
    }

    /// Geeft true als het bericht door het leren is opgebruikt.
    public func feed(_ m: [UInt8]) -> Bool {
        guard let target = current else { return false }
        guard m.count == 3, m[0] & 0xF0 == 0xB0, !waiting else { return true }
        let channel = Int(m[0] & 0x0F) + 1, cc = Int(m[1]), value = Int(m[2])
        let key = ((channel - 1) << 8) | cc
        // Nog nabewegende elementen die net geleerd zijn negeren
        if usedThisSession.contains(key) { return true }

        if var c = capture {
            if c.key == key { c.values.append(value); capture = c }
            return true
        }
        capture = (key, channel, cc, [value])
        switch target.kind {
        case .fader:
            finish()
        case .encoder:
            schedule(ms: 1000)
        case .button:
            schedule(ms: 1000)
        }
        return true
    }

    private func schedule(ms: Int) {
        generation += 1
        let gen = generation
        clock.after(ms: ms) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.finish()
        }
    }

    private func finish() {
        guard let target = current, let c = capture else { return }
        var mapping = ControlMapping(channel: c.channel, cc: c.cc)
        var detail = ""
        switch target.kind {
        case .fader:
            break
        case .encoder:
            let mode = Self.detectEncoderMode(c.values)
            mapping.encoderMode = mode
            detail = mode.label
        case .button:
            let mode: ButtonMode = c.values.count >= 2 ? .momentary : .toggle
            mapping.buttonMode = mode
            detail = mode == .toggle ? "toggle" : "momentary"
        }
        usedThisSession.insert(c.key)
        learned(target, mapping, detail)
        // Korte pauze zodat nabewegen niet bij het volgende doel terechtkomt
        waiting = true
        capture = nil
        generation += 1
        let gen = generation
        clock.after(ms: 600) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.next()
        }
    }

    public static func detectEncoderMode(_ v: [Int]) -> EncoderMode {
        guard v.count >= 3 else { return .absolute }
        let distinct = Set(v).count
        // Absolute encoders lopen op of af, relatieve herhalen dezelfde kleine waarden
        if Double(distinct) >= Double(v.count) * 0.6 { return .absolute }
        if v.allSatisfy({ $0 <= 20 || $0 >= 108 }) { return .relativeTwosComplement }
        if v.allSatisfy({ (44...84).contains($0) }) { return .relativeOffset64 }
        return .absolute
    }
}
