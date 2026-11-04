import Foundation

/// Zet een ruwe MIDI-bytestroom om in losse, complete berichten.
/// Ondersteunt running status, SysEx verspreid over meerdere pakketten en realtime-bytes.
public struct MIDIParser {
    private var running: UInt8 = 0
    private var buffer: [UInt8] = []
    private var expected = 0
    private var inSysex = false

    public init() {}

    public static func dataLength(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0: return 2
        case 0xC0, 0xD0: return 1
        default:
            switch status {
            case 0xF1, 0xF3: return 1
            case 0xF2: return 2
            default: return 0
            }
        }
    }

    public mutating func feed(_ bytes: [UInt8], emit: ([UInt8]) -> Void) {
        for b in bytes {
            // Realtime-bytes mogen overal tussendoor staan
            if b >= 0xF8 {
                emit([b])
                continue
            }
            if b == 0xF0 {
                inSysex = true
                buffer = [b]
                running = 0
                continue
            }
            if b == 0xF7 {
                if inSysex {
                    buffer.append(b)
                    emit(buffer)
                }
                inSysex = false
                buffer = []
                continue
            }
            if inSysex {
                if b & 0x80 == 0 {
                    buffer.append(b)
                    continue
                }
                // Statusbyte onderbreekt SysEx: SysEx weggooien
                inSysex = false
                buffer = []
            }
            if b & 0x80 != 0 {
                let len = Self.dataLength(for: b)
                if b >= 0xF0 {
                    running = 0
                    if len == 0 {
                        emit([b])
                        buffer = []
                        continue
                    }
                } else {
                    running = b
                }
                buffer = [b]
                expected = len
                continue
            }
            // Databyte
            if buffer.isEmpty {
                guard running != 0 else { continue }
                buffer = [running]
                expected = Self.dataLength(for: running)
            }
            buffer.append(b)
            if buffer.count - 1 >= expected {
                emit(buffer)
                buffer = []
            }
        }
    }
}
