import Foundation

public enum MIDIDescribe {
    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Algemene uitleg zonder Mackie-betekenis (voor de BCF2000-kant).
    public static func generic(_ m: [UInt8]) -> String {
        guard let s = m.first else { return "empty" }
        let ch = Int(s & 0x0F) + 1
        let d1 = m.count > 1 ? Int(m[1]) : 0
        let d2 = m.count > 2 ? Int(m[2]) : 0
        switch s & 0xF0 {
        case 0x80: return "Note Off ch.\(ch) note \(d1) vel \(d2)"
        case 0x90: return "Note On ch.\(ch) note \(d1) vel \(d2)"
        case 0xA0: return "Aftertouch ch.\(ch) note \(d1) = \(d2)"
        case 0xB0: return "CC ch.\(ch) #\(d1) = \(d2)"
        case 0xC0: return "Program Change ch.\(ch) = \(d1)"
        case 0xD0: return "Channel Pressure ch.\(ch) = \(d1)"
        case 0xE0: return "Pitch Bend ch.\(ch) = \(d1 | (d2 << 7))"
        default:
            if s == 0xF0 { return "SysEx (\(m.count) bytes)" }
            return "System message"
        }
    }

    public static let mackieNoteNames: [Int: String] = {
        var n: [Int: String] = [:]
        for i in 0..<8 {
            n[0x00 + i] = "Rec \(i + 1)"
            n[0x08 + i] = "Solo \(i + 1)"
            n[0x10 + i] = "Mute \(i + 1)"
            n[0x18 + i] = "Select \(i + 1)"
            n[0x20 + i] = "V-Pot \(i + 1) push"
            n[0x68 + i] = "Fader \(i + 1) touch"
        }
        n[0x70] = "Master fader touch"
        n[0x2E] = "Bank left"; n[0x2F] = "Bank right"
        n[0x30] = "Channel left"; n[0x31] = "Channel right"
        n[0x5B] = "Rewind"; n[0x5C] = "Forward"; n[0x5D] = "Stop"
        n[0x5E] = "Play"; n[0x5F] = "Record"
        return n
    }()

    public static let mackieSysexNames: [UInt8: String] = [
        0x00: "Device query", 0x01: "Host connection query", 0x02: "Host connection reply",
        0x03: "Host connection confirmation", 0x04: "Host connection error",
        0x0A: "Transport button click", 0x0B: "LCD backlight saver", 0x0C: "Touchless faders",
        0x0E: "Fader touch sensitivity", 0x0F: "Go offline", 0x10: "Timecode display",
        0x11: "Assignment display", 0x12: "LCD text", 0x13: "Version request",
        0x14: "Version reply", 0x1A: "Serial number request", 0x1B: "Serial number reply",
        0x20: "Channel meter mode", 0x21: "Global LCD meter mode",
        0x61: "All faders to minimum", 0x62: "All LEDs off", 0x63: "Reset",
    ]

    /// Uitleg vanuit Mackie Control-oogpunt (voor de Logic-kant).
    public static func mackie(_ m: [UInt8]) -> String {
        guard let s = m.first else { return "empty" }
        let ch = Int(s & 0x0F)
        let d1 = m.count > 1 ? Int(m[1]) : 0
        let d2 = m.count > 2 ? Int(m[2]) : 0
        switch s & 0xF0 {
        case 0x90, 0x80:
            let name = mackieNoteNames[d1] ?? "note \(d1)"
            let vel = (s & 0xF0) == 0x80 ? 0 : d2
            let state: String
            if d1 >= 0x68 && d1 <= 0x70 {
                state = vel >= 64 ? "touched" : "released"
            } else {
                state = vel == 127 ? "on/pressed" : (vel == 1 ? "blink" : (vel == 0 ? "off/released" : "vel \(vel)"))
            }
            return "\(name): \(state)"
        case 0xE0:
            let v = d1 | (d2 << 7)
            let pct = Double(v) / 16383.0 * 100
            return ch < 8 ? "Fader \(ch + 1) = \(v) (\(String(format: "%.1f", pct))%)"
                          : "Master fader = \(v)"
        case 0xB0:
            if (0x10...0x17).contains(d1) {
                let dir = d2 & 0x40 != 0 ? "left" : "right"
                return "V-Pot \(d1 - 0x10 + 1) turned \(dir) \(d2 & 0x0F) step(s)"
            }
            if (0x30...0x37).contains(d1) {
                return "V-Pot \(d1 - 0x30 + 1) LED ring = 0x" + String(format: "%02X", d2)
            }
            if (0x40...0x4B).contains(d1) { return "Timecode digit" }
            return "CC #\(d1) = \(d2)"
        case 0xD0:
            return "Meter channel \((d1 >> 4) + 1) = \(d1 & 0x0F)"
        default:
            if s == 0xF0 {
                if m.count >= 6, m[1] == 0x00, m[2] == 0x00, m[3] == 0x66 {
                    let cmd = m[5]
                    let name = mackieSysexNames[cmd] ?? "unknown command 0x" + String(format: "%02X", cmd)
                    return "Mackie SysEx (model 0x" + String(format: "%02X", m[4]) + "): \(name)"
                }
                return "SysEx (\(m.count) bytes)"
            }
            return generic(m)
        }
    }

    /// Berichten die bij afspelen massaal binnenkomen en standaard niet gelogd worden.
    public static func isNoisyLogicMessage(_ m: [UInt8]) -> Bool {
        guard let s = m.first else { return false }
        if s & 0xF0 == 0xD0 { return true } // meters
        if s & 0xF0 == 0xB0, m.count > 1, (0x40...0x4B).contains(Int(m[1])) { return true } // timecode
        if s == 0xF0, m.count > 5, m[3] == 0x66, m[5] == 0x12 || m[5] == 0x10 { return true } // LCD en timecode
        return false
    }
}
