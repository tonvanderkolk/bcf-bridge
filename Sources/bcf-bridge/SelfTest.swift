import BridgeCore
import Foundation

/// Controleert de vertaallogica zonder hardware. Start met: bcf-bridge selftest
enum SelfTest {
    static var failures = 0

    static func expect(_ cond: Bool, _ what: String) {
        print((cond ? "  ok    " : "  FOUT  ") + what)
        if !cond { failures += 1 }
    }

    static func run() -> Int32 {
        print("Parser")
        var p = MIDIParser()
        var out: [[UInt8]] = []
        p.feed([0xB0, 81, 10, 11, 12, 0xF0, 0x00, 0x00]) { out.append($0) }
        p.feed([0x66, 0x14, 0x00, 0xF7, 0xF8, 0xE0, 0x00]) { out.append($0) }
        p.feed([0x40]) { out.append($0) }
        expect(out.count == 5, "running status, gesplitste SysEx, realtime en gesplitst pitch bend (\(out.count) berichten)")
        expect(out.first == [0xB0, 81, 10], "eerste CC compleet")
        expect(out.count > 1 && out[1] == [0xB0, 11, 12], "running status CC")
        expect(out.count > 2 && out[2] == [0xF0, 0x00, 0x00, 0x66, 0x14, 0x00, 0xF7], "SysEx samengevoegd")
        expect(out.last == [0xE0, 0x00, 0x40], "pitch bend over twee pakketten")

        print("Handshake")
        let h = MackieHandshake()
        let r1 = h.handle([0xF0, 0x00, 0x00, 0x66, 0x14, 0x00, 0xF7]).reply ?? []
        expect(r1.count == 18 && r1[5] == 0x01, "device query -> host connection query (18 bytes)")
        let r2 = h.handle([0xF0, 0x00, 0x00, 0x66, 0x14, 0x02] + Array("BCFBRG1".utf8) + [1, 2, 3, 4, 0xF7]).reply ?? []
        expect(r2.count == 14 && r2[5] == 0x03 && h.online, "host reply -> confirmation, online")

        print("Fader 1")
        let clock = ManualClock()
        let f = FaderBridge(index: 0, mapping: ControlMapping(channel: 1, cc: 81), releaseMs: 400, clock: clock)
        var toLogic: [[UInt8]] = []
        var toBCF: [[UInt8]] = []
        f.sendToLogic = { b, _ in toLogic.append(b) }
        f.sendToBCF = { b, _ in toBCF.append(b) }

        f.fromBCF(value: 64)
        expect(toLogic.first == [0x90, 0x68, 0x7F], "eerste beweging stuurt eerst touch aan")
        expect(toLogic.count == 2 && toLogic[1] == [0xE0, 0x40, 0x40], "daarna pitch bend 8256")
        clock.advance(ms: 100)
        f.fromBCF(value: 127)
        expect(toLogic.count == 3 && toLogic[2] == [0xE0, 0x7F, 0x7F], "127 wordt 16383, geen tweede touch")

        f.fromLogic(pitchBend: 8192)
        expect(toBCF.isEmpty, "feedback tijdens touch wordt tegengehouden")
        clock.advance(ms: 399)
        expect(f.touched, "nog aangeraakt na 399 ms")
        clock.advance(ms: 2)
        expect(!f.touched && toLogic.last == [0x90, 0x68, 0x00], "touch uit na 400 ms stilstand")
        clock.advance(ms: 200)
        expect(toBCF.last == [0xB0, 81, 64], "na loslaten wordt de afwijkende stand van Logic alsnog gestuurd")

        let before = toBCF.count
        f.fromLogic(pitchBend: 8192 + 50)
        expect(toBCF.count == before, "zelfde 7-bit stand niet opnieuw naar de motor")
        f.fromLogic(pitchBend: 0)
        expect(toBCF.last == [0xB0, 81, 0], "nieuwe stand van Logic beweegt de motor")

        let logicBefore = toLogic.count
        clock.advance(ms: 20)
        f.fromBCF(value: 0)
        expect(toLogic.count == logicBefore, "echo van de motor wordt niet als aanraking gezien")
        clock.advance(ms: 500)
        f.fromBCF(value: 5)
        expect(toLogic.count == logicBefore + 2, "echte beweging daarna geeft weer touch + pitch bend")

        print(failures == 0 ? "\nAlles in orde." : "\n\(failures) test(s) mislukt.")
        return failures == 0 ? 0 : 1
    }
}
