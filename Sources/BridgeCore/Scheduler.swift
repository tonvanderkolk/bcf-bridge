import Foundation

/// Klok plus vertraagde taken. In de app via een DispatchQueue, in de selftest handmatig.
public protocol BridgeClock: AnyObject {
    var now: Double { get } // seconden
    func after(ms: Int, _ block: @escaping () -> Void)
}

public final class QueueClock: BridgeClock {
    let queue: DispatchQueue
    let start = Date()
    public init(queue: DispatchQueue) { self.queue = queue }
    public var now: Double { Date().timeIntervalSince(start) }
    public func after(ms: Int, _ block: @escaping () -> Void) {
        queue.asyncAfter(deadline: .now() + .milliseconds(ms), execute: block)
    }
}

public final class ManualClock: BridgeClock {
    public private(set) var now: Double = 0
    private var tasks: [(at: Double, seq: Int, block: () -> Void)] = []
    private var seq = 0
    public init() {}
    public func after(ms: Int, _ block: @escaping () -> Void) {
        seq += 1
        tasks.append((now + Double(ms) / 1000, seq, block))
    }
    public func advance(ms: Int) {
        let target = now + Double(ms) / 1000
        while true {
            tasks.sort { ($0.at, $0.seq) < ($1.at, $1.seq) }
            guard let first = tasks.first, first.at <= target + 1e-9 else { break }
            tasks.removeFirst()
            now = max(now, first.at)
            first.block()
        }
        now = target
    }
}
