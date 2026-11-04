import Foundation

/// Speelt de rol van een Mackie Control Universal (MCU) richting Logic.
public final class MackieHandshake {
    public static let header: [UInt8] = [0xF0, 0x00, 0x00, 0x66, 0x14]
    /// 7 ASCII-tekens, "BCFBRG1"
    public let serial: [UInt8] = Array("BCFBRG1".utf8)
    public let challenge: [UInt8] = [0x01, 0x02, 0x03, 0x04]
    public let version: [UInt8] = Array("V1.02".utf8)

    public private(set) var online = false

    public init() {}

    /// Verwerkt een SysEx van Logic. Geeft het antwoord terug (of nil) plus een korte uitleg.
    public func handle(_ m: [UInt8]) -> (reply: [UInt8]?, note: String?) {
        guard m.count >= 7, Array(m[0..<5]) == Self.header else { return (nil, nil) }
        // Logic slaat de host connection reply (0x02) vaak over: elk ander commando betekent ook verbonden
        if m[5] != 0x00 && m[5] != 0x0F { online = true }
        switch m[5] {
        case 0x00:
            return (Self.header + [0x01] + serial + challenge + [0xF7],
                    "Logic asks for the device, replying with host connection query")
        case 0x02:
            online = true
            return (Self.header + [0x03] + serial + [0xF7],
                    "Logic confirms the connection, replying with confirmation. Mackie connection is up")
        case 0x13:
            return (Self.header + [0x14] + version + [0xF7], "Logic asks for the version")
        case 0x1A:
            return (Self.header + [0x1B] + serial + [0xF7], "Logic asks for the serial number")
        case 0x0F:
            online = false
            return (nil, "Logic says: go offline")
        default:
            return (nil, nil)
        }
    }

    public func reset() { online = false }
}
