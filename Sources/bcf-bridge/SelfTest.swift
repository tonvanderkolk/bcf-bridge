import BridgeCore
import BridgeEngine
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

        routerTests()
        learnerTests()
        settingsTests()

        print(failures == 0 ? "\nAlles in orde." : "\n\(failures) test(s) mislukt.")
        return failures == 0 ? 0 : 1
    }

    static func routerTests() {
        print("Router (standaard fabriekspreset)")
        let clock = ManualClock()
        let r = Router(settings: BridgeSettings(), clock: clock)
        var toLogic: [[UInt8]] = []
        var toBCF: [[UInt8]] = []
        r.sendToLogic = { b, _ in toLogic.append(b) }
        r.sendToBCF = { b, _ in toBCF.append(b) }

        r.fromBCF([0xB0, 88, 100])
        expect(toLogic.prefix(2) == [[0x90, 0x6F, 0x7F], [0xE7, 100, 100]], "fader 8 (CC 88) wordt touch 8 + pitch bend kanaal 8")
        clock.advance(ms: 1000)
        toLogic = []
        r.fromLogic([0xE3, 0x00, 0x40])
        expect(toBCF.last == [0xB0, 84, 64], "Logic fader 4 beweegt motorfader 4 (CC 84)")

        print("Encoders")
        r.fromBCF([0xB0, 3, 64])
        expect(toLogic.isEmpty, "eerste encoderwaarde is alleen beginpunt")
        r.fromBCF([0xB0, 3, 66])
        expect(toLogic.last == [0xB0, 0x12, 0x02], "encoder 3 omhoog = V-Pot 3 twee stappen rechtsom")
        r.fromBCF([0xB0, 3, 63])
        expect(toLogic.last == [0xB0, 0x12, 0x43], "encoder 3 omlaag = V-Pot 3 drie stappen linksom")
        let bcfBefore = toBCF.count
        r.fromLogic([0xB0, 0x32, 0x16])
        expect(toBCF.count == bcfBefore, "LED-krans tijdens draaien wordt tegengehouden")
        clock.advance(ms: 400)
        expect(toBCF.last == [0xB0, 3, 64], "na draaien: krans positie 6 zet encoder op 64")
        r.fromBCF([0xB0, 3, 65])
        expect(toLogic.last == [0xB0, 0x12, 0x01], "daarna verder draaien rekent vanaf de stand van Logic")

        print("Knoppen")
        toLogic = []
        r.fromBCF([0xB0, 65, 127])
        expect(toLogic == [[0x90, 0x10, 0x7F], [0x90, 0x10, 0x00]], "bovenste knop 1 (toggle) = één klik op Mute 1")
        let n = toBCF.count
        r.fromLogic([0x90, 0x10, 0x7F])
        expect(toBCF.count == n, "lampje aan na eigen druk: BCF heeft het al, niet opnieuw sturen")
        r.fromLogic([0x90, 0x10, 0x00])
        expect(toBCF.last == [0xB0, 65, 0], "Logic zet Mute 1 uit: lampje uit")
        toLogic = []
        r.fromBCF([0xB0, 73, 0])
        expect(toLogic == [[0x90, 0x08, 0x7F], [0x90, 0x08, 0x00]], "onderste knop 1 met waarde 0 is ook een klik (Solo 1)")
        r.fromLogic([0x90, 0x09, 0x01])
        expect(toBCF.last == [0xB0, 74, 127], "knipperen van Solo 2 wordt lampje aan")

        var s = BridgeSettings()
        s.nav[NavButton.bankRight.rawValue] = ControlMapping(channel: 1, cc: 90, buttonMode: .toggle)
        s.topRowFunction = .select
        r.update(s)
        toLogic = []
        r.fromBCF([0xB0, 90, 127])
        expect(toLogic == [[0x90, 0x2F, 0x7F], [0x90, 0x2F, 0x00]], "bank rechts gekoppeld aan CC 90")
        clock.advance(ms: 200)
        expect(toBCF.last == [0xB0, 90, 0], "lampje van bank-knop gaat vanzelf weer uit")
        toLogic = []
        r.fromBCF([0xB0, 66, 127])
        expect(toLogic.first == [0x90, 0x19, 0x7F], "bovenste rij op Select: knop 2 = Select 2")
        expect(r.fromBCF([0xB0, 120, 5]) == false, "ongekoppelde CC wordt gemeld")
    }

    static func learnerTests() {
        print("Learn")
        let clock = ManualClock()
        let l = Learner(clock: clock)
        var got: [(LearnTarget, ControlMapping)] = []
        var done = false
        l.learned = { t, m, _ in got.append((t, m)) }
        l.finished = { _ in done = true }
        l.start([.fader(0), .encoder(0), .top(0), .bottom(0)])
        _ = l.feed([0xB1, 20, 10])
        expect(got.last?.0 == .fader(0) && got.last?.1.cc == 20 && got.last?.1.channel == 2, "fader geleerd: CC 20 kanaal 2")
        _ = l.feed([0xB1, 20, 11])
        clock.advance(ms: 700)
        _ = l.feed([0xB1, 20, 12])
        expect(l.current == .encoder(0), "nabewegen van de geleerde fader telt niet voor de encoder")
        for v in [1, 1, 1, 2] { _ = l.feed([0xB0, 5, UInt8(v)]) }
        clock.advance(ms: 1100)
        expect(got.last?.1.cc == 5 && got.last?.1.encoderMode == .relativeTwosComplement, "relatieve encoder herkend")
        clock.advance(ms: 700)
        _ = l.feed([0xB0, 65, 127])
        clock.advance(ms: 1100)
        expect(got.last?.1.buttonMode == .toggle, "knop met één bericht = toggle")
        clock.advance(ms: 700)
        _ = l.feed([0xB0, 73, 127]); _ = l.feed([0xB0, 73, 0])
        clock.advance(ms: 1100)
        expect(got.last?.1.buttonMode == .momentary, "knop met indrukken + loslaten = momentary")
        clock.advance(ms: 700)
        expect(done && !l.isActive, "leren klaar na laatste doel")
        expect(Learner.detectEncoderMode([64, 65, 66, 67, 68]) == .absolute, "oplopende waarden = absoluut")
        expect(Learner.detectEncoderMode([65, 65, 66, 65]) == .relativeOffset64, "waarden rond 64 = relatief offset")
    }

    static func settingsTests() {
        print("Instellingen")
        let v1 = #"{"version":1,"fader1":{"channel":3,"cc":7},"touchReleaseMs":500}"#.data(using: .utf8)!
        let s = try? JSONDecoder().decode(BridgeSettings.self, from: v1)
        expect(s?.faders[0]?.cc == 7 && s?.faders[0]?.channel == 3 && s?.touchReleaseMs == 500, "oude versie 1 wordt overgenomen")
        expect(s?.faders[1]?.cc == 82, "overige faders krijgen de standaard")
        var t = BridgeSettings()
        let cleared = t.assign(ControlMapping(channel: 1, cc: 81), to: .top(0))
        expect(cleared == [.fader(0)] && t.faders[0] == nil, "dubbele CC wordt bij het andere element weggehaald")
        if let data = try? JSONEncoder().encode(t), let back = try? JSONDecoder().decode(BridgeSettings.self, from: data) {
            expect(back == t, "opslaan en teruglezen geeft hetzelfde")
        } else {
            expect(false, "opslaan en teruglezen")
        }
    }
}
