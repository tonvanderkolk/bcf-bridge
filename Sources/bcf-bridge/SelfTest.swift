import BridgeCore
import BridgeEngine
import Foundation

/// Controleert de vertaallogica zonder hardware. Start met: bcf-bridge selftest
enum SelfTest {
    static var failures = 0

    static func expect(_ cond: Bool, _ what: String) {
        print((cond ? "  ok    " : "  FAIL  ") + what)
        if !cond { failures += 1 }
    }

    static func run() -> Int32 {
        print("Parser")
        var p = MIDIParser()
        var out: [[UInt8]] = []
        p.feed([0xB0, 81, 10, 11, 12, 0xF0, 0x00, 0x00]) { out.append($0) }
        p.feed([0x66, 0x14, 0x00, 0xF7, 0xF8, 0xE0, 0x00]) { out.append($0) }
        p.feed([0x40]) { out.append($0) }
        expect(out.count == 5, "running status, split SysEx, realtime and split pitch bend (\(out.count) messages)")
        expect(out.first == [0xB0, 81, 10], "first CC complete")
        expect(out.count > 1 && out[1] == [0xB0, 11, 12], "running status CC")
        expect(out.count > 2 && out[2] == [0xF0, 0x00, 0x00, 0x66, 0x14, 0x00, 0xF7], "SysEx joined")
        expect(out.last == [0xE0, 0x00, 0x40], "pitch bend across two packets")

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
        expect(toLogic.first == [0x90, 0x68, 0x7F], "first movement sends touch on first")
        expect(toLogic.count == 2 && toLogic[1] == [0xE0, 0x40, 0x40], "then pitch bend 8256")
        clock.advance(ms: 100)
        f.fromBCF(value: 127)
        expect(toLogic.count == 3 && toLogic[2] == [0xE0, 0x7F, 0x7F], "127 becomes 16383, no second touch")

        f.fromLogic(pitchBend: 8192)
        expect(toBCF.isEmpty, "feedback while touched is held back")
        clock.advance(ms: 399)
        expect(f.touched, "still touched after 399 ms")
        clock.advance(ms: 2)
        expect(!f.touched && toLogic.last == [0x90, 0x68, 0x00], "touch off after 400 ms idle")
        clock.advance(ms: 200)
        expect(toBCF.last == [0xB0, 81, 64], "after release the differing Logic position is sent")

        let before = toBCF.count
        f.fromLogic(pitchBend: 8192 + 50)
        expect(toBCF.count == before, "same 7-bit position not resent to the motor")
        f.fromLogic(pitchBend: 0)
        expect(toBCF.last == [0xB0, 81, 0], "new Logic position moves the motor")

        let logicBefore = toLogic.count
        clock.advance(ms: 20)
        f.fromBCF(value: 0)
        expect(toLogic.count == logicBefore, "motor echo is not seen as a touch")
        clock.advance(ms: 500)
        f.fromBCF(value: 5)
        expect(toLogic.count == logicBefore + 2, "real movement afterwards gives touch + pitch bend again")

        routerTests()
        learnerTests()
        settingsTests()

        print(failures == 0 ? "\nAll good." : "\n\(failures) test(s) failed.")
        return failures == 0 ? 0 : 1
    }

    static func routerTests() {
        print("Router (default factory preset)")
        let clock = ManualClock()
        let r = Router(settings: BridgeSettings(), clock: clock)
        var toLogic: [[UInt8]] = []
        var toBCF: [[UInt8]] = []
        r.sendToLogic = { b, _ in toLogic.append(b) }
        r.sendToBCF = { b, _ in toBCF.append(b) }

        r.fromBCF([0xB0, 88, 100])
        expect(toLogic.prefix(2) == [[0x90, 0x6F, 0x7F], [0xE7, 100, 100]], "fader 8 (CC 88) becomes touch 8 + pitch bend channel 8")
        clock.advance(ms: 1000)
        toLogic = []
        r.fromLogic([0xE3, 0x00, 0x40])
        expect(toBCF.last == [0xB0, 84, 64], "Logic fader 4 moves motor fader 4 (CC 84)")

        print("Encoders")
        r.fromBCF([0xB0, 3, 64])
        expect(toLogic.isEmpty, "first encoder value is only the starting point")
        r.fromBCF([0xB0, 3, 66])
        expect(toLogic.last == [0xB0, 0x12, 0x02], "encoder 3 up = V-Pot 3 two steps right")
        r.fromBCF([0xB0, 3, 63])
        expect(toLogic.last == [0xB0, 0x12, 0x43], "encoder 3 down = V-Pot 3 three steps left")
        let bcfBefore = toBCF.count
        r.fromLogic([0xB0, 0x32, 0x16])
        expect(toBCF.count == bcfBefore, "LED ring while turning is held back")
        clock.advance(ms: 400)
        expect(toBCF.last == [0xB0, 3, 64], "after turning: ring position 6 sets encoder to 64")
        r.fromBCF([0xB0, 3, 65])
        expect(toLogic.last == [0xB0, 0x12, 0x01], "further turning counts from the Logic position")

        print("Buttons")
        toLogic = []
        r.fromBCF([0xB0, 65, 127])
        expect(toLogic == [[0x90, 0x10, 0x7F], [0x90, 0x10, 0x00]], "top button 1 (toggle) = one click on Mute 1")
        let n = toBCF.count
        r.fromLogic([0x90, 0x10, 0x7F])
        expect(toBCF.count == n, "LED on after own press: BCF already has it, not resent")
        r.fromLogic([0x90, 0x10, 0x00])
        expect(toBCF.last == [0xB0, 65, 0], "Logic turns Mute 1 off: LED off")
        toLogic = []
        r.fromBCF([0xB0, 73, 0])
        expect(toLogic == [[0x90, 0x08, 0x7F], [0x90, 0x08, 0x00]], "bottom button 1 with value 0 is also a click (Solo 1)")
        r.fromLogic([0x90, 0x09, 0x01])
        expect(toBCF.last == [0xB0, 74, 127], "blinking Solo 2 becomes LED on")

        var s = BridgeSettings()
        s.nav[NavButton.bankRight.rawValue] = ControlMapping(channel: 1, cc: 90, buttonMode: .toggle)
        s.topRowFunction = .select
        r.update(s)
        toLogic = []
        r.fromBCF([0xB0, 90, 127])
        expect(toLogic == [[0x90, 0x2F, 0x7F], [0x90, 0x2F, 0x00]], "bank right mapped to CC 90")
        clock.advance(ms: 200)
        expect(toBCF.last == [0xB0, 90, 0], "bank button LED turns off by itself")
        toLogic = []
        r.fromBCF([0xB0, 66, 127])
        expect(toLogic.first == [0x90, 0x19, 0x7F], "top row on Select: button 2 = Select 2")
        expect(r.fromBCF([0xB0, 120, 5]) == false, "unmapped CC is reported")
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
        expect(got.last?.0 == .fader(0) && got.last?.1.cc == 20 && got.last?.1.channel == 2, "fader learned: CC 20 channel 2")
        _ = l.feed([0xB1, 20, 11])
        clock.advance(ms: 700)
        _ = l.feed([0xB1, 20, 12])
        expect(l.current == .encoder(0), "trailing movement of the learned fader does not count for the encoder")
        for v in [1, 1, 1, 2] { _ = l.feed([0xB0, 5, UInt8(v)]) }
        clock.advance(ms: 1100)
        expect(got.last?.1.cc == 5 && got.last?.1.encoderMode == .relativeTwosComplement, "relative encoder detected")
        clock.advance(ms: 700)
        _ = l.feed([0xB0, 65, 127])
        clock.advance(ms: 1100)
        expect(got.last?.1.buttonMode == .toggle, "button with one message = toggle")
        clock.advance(ms: 700)
        _ = l.feed([0xB0, 73, 127]); _ = l.feed([0xB0, 73, 0])
        clock.advance(ms: 1100)
        expect(got.last?.1.buttonMode == .momentary, "button with press + release = momentary")
        clock.advance(ms: 700)
        expect(done && !l.isActive, "learning finished after last target")
        expect(Learner.detectEncoderMode([64, 65, 66, 67, 68]) == .absolute, "rising values = absolute")
        expect(Learner.detectEncoderMode([65, 65, 66, 65]) == .relativeOffset64, "values around 64 = relative offset")
    }

    static func settingsTests() {
        print("Settings")
        let v1 = #"{"version":1,"fader1":{"channel":3,"cc":7},"touchReleaseMs":500}"#.data(using: .utf8)!
        let s = try? JSONDecoder().decode(BridgeSettings.self, from: v1)
        expect(s?.faders[0]?.cc == 7 && s?.faders[0]?.channel == 3 && s?.touchReleaseMs == 500, "old version 1 is migrated")
        expect(s?.faders[1]?.cc == 82, "other faders get the default")
        var t = BridgeSettings()
        let cleared = t.assign(ControlMapping(channel: 1, cc: 81), to: .top(0))
        expect(cleared == [.fader(0)] && t.faders[0] == nil, "duplicate CC is removed from the other element")
        if let data = try? JSONEncoder().encode(t), let back = try? JSONDecoder().decode(BridgeSettings.self, from: data) {
            expect(back == t, "save and reload gives the same")
        } else {
            expect(false, "save and reload")
        }
        let roundTrip = BridgeSettings.allTargets.allSatisfy {
            LearnTarget.parse($0.command.split(separator: " ").map(String.init)) == $0
        }
        expect(roundTrip, "every element round-trips as a text command")
        let old = #"{"version":2,"touchReleaseMs":400}"#.data(using: .utf8)!
        expect((try? JSONDecoder().decode(BridgeSettings.self, from: old))?.hideModelFromLogic == true, "hiding the model from Logic is on by default")
    }
}
