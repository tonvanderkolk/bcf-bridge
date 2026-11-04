import CoreMIDI
import Foundation

public struct Endpoint {
    public let ref: MIDIEndpointRef
    public let name: String
    public let uniqueID: Int32
}

/// Dunne laag over CoreMIDI: virtuele poort "BCF Bridge" plus de echte BCF2000-poorten.
/// Alle callbacks komen terug op `queue`.
public final class MIDIIO {
    public static let virtualName = "BCF Bridge"

    let queue: DispatchQueue
    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private var virtualSource = MIDIEndpointRef()
    private var virtualDest = MIDIEndpointRef()

    private(set) var bcfIn: Endpoint?
    private(set) var bcfOut: Endpoint?

    var onBCFBytes: ([UInt8]) -> Void = { _ in }
    var onLogicBytes: ([UInt8]) -> Void = { _ in }
    var onSetupChanged: () -> Void = {}

    init(queue: DispatchQueue) { self.queue = queue }

    func start() throws {
        // Twee bridges tegelijk geeft twee poorten met dezelfde naam en verwarring in Logic
        if Self.sources().contains(where: { $0.name == Self.virtualName }) {
            throw NSError(domain: "BCFBridge", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Er draait al een BCF Bridge (in Terminal of als app). Stop die eerst."])
        }
        try check(MIDIClientCreateWithBlock("BCF Bridge" as CFString, &client) { [weak self] notif in
            guard let self else { return }
            if notif.pointee.messageID == .msgSetupChanged {
                self.queue.async { self.onSetupChanged() }
            }
        }, "MIDI-client aanmaken")

        try check(MIDIInputPortCreateWithBlock(client, "BCF in" as CFString, &inPort) { [weak self] list, _ in
            guard let self else { return }
            let bytes = Self.bytes(from: list)
            self.queue.async { self.onBCFBytes(bytes) }
        }, "invoerpoort aanmaken")

        try check(MIDIOutputPortCreate(client, "BCF out" as CFString, &outPort), "uitvoerpoort aanmaken")

        // Logic leest van deze source en schrijft naar deze destination
        try check(MIDISourceCreate(client, Self.virtualName as CFString, &virtualSource), "virtuele source aanmaken")
        try check(MIDIDestinationCreateWithBlock(client, Self.virtualName as CFString, &virtualDest) { [weak self] list, _ in
            guard let self else { return }
            let bytes = Self.bytes(from: list)
            self.queue.async { self.onLogicBytes(bytes) }
        }, "virtuele destination aanmaken")

        // Vaste ID's zodat Logic de poort na een herstart herkent
        MIDIObjectSetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, 0x4243_4601)
        MIDIObjectSetIntegerProperty(virtualDest, kMIDIPropertyUniqueID, 0x4243_4602)
    }

    func stop() {
        MIDIEndpointDispose(virtualSource)
        MIDIEndpointDispose(virtualDest)
        MIDIClientDispose(client)
    }

    // MARK: Poorten zoeken

    static func name(of obj: MIDIObjectRef) -> String {
        var cf: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &cf) == noErr, let s = cf?.takeRetainedValue() {
            return s as String
        }
        if MIDIObjectGetStringProperty(obj, kMIDIPropertyName, &cf) == noErr, let s = cf?.takeRetainedValue() {
            return s as String
        }
        return "(naamloos)"
    }

    static func uid(of obj: MIDIObjectRef) -> Int32 {
        var v: Int32 = 0
        MIDIObjectGetIntegerProperty(obj, kMIDIPropertyUniqueID, &v)
        return v
    }

    public static func sources() -> [Endpoint] {
        (0..<MIDIGetNumberOfSources()).map { i in
            let e = MIDIGetSource(i)
            return Endpoint(ref: e, name: name(of: e), uniqueID: uid(of: e))
        }
    }

    public static func destinations() -> [Endpoint] {
        (0..<MIDIGetNumberOfDestinations()).map { i in
            let e = MIDIGetDestination(i)
            return Endpoint(ref: e, name: name(of: e), uniqueID: uid(of: e))
        }
    }

    static let bridgeModelName = "BCF2000 Bridge"

    /// Logic herkent de BCF2000 aan het model "BCF2000" en zet hem dan bij elke start opnieuw
    /// als control surface neer. Met een andere modelnaam blijft Logic eraf. Alleen de naam in
    /// CoreMIDI verandert, niet de BCF2000 zelf. Geeft true terug als er iets gewijzigd is.
    static func hideBCFModelFromLogic() -> Bool {
        func str(_ o: MIDIObjectRef, _ k: CFString) -> String {
            var cf: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(o, k, &cf) == noErr, let s = cf?.takeRetainedValue() else { return "" }
            return s as String
        }
        var changed = false
        for i in 0..<MIDIGetNumberOfDevices() {
            let d = MIDIGetDevice(i)
            if str(d, kMIDIPropertyManufacturer).uppercased() == "BEHRINGER", str(d, kMIDIPropertyModel) == "BCF2000",
               MIDIObjectSetStringProperty(d, kMIDIPropertyModel, bridgeModelName as CFString) == noErr {
                changed = true
            }
        }
        return changed
    }

    /// Koppelt (opnieuw) aan de BCF2000. Geeft true terug als er iets veranderd is.
    @discardableResult
    func connectBCF(inMatch: String, outMatch: String) -> Bool {
        var changed = false
        let srcs = Self.sources().filter { $0.name != Self.virtualName }
        let dsts = Self.destinations().filter { $0.name != Self.virtualName }

        // Losgekoppelde poorten vergeten
        if let cur = bcfIn, !srcs.contains(where: { $0.uniqueID == cur.uniqueID }) {
            bcfIn = nil; changed = true
        }
        if let cur = bcfOut, !dsts.contains(where: { $0.uniqueID == cur.uniqueID }) {
            bcfOut = nil; changed = true
        }

        if bcfIn == nil, let s = srcs.first(where: { $0.name.localizedCaseInsensitiveContains(inMatch) }) {
            if MIDIPortConnectSource(inPort, s.ref, nil) == noErr {
                bcfIn = s; changed = true
            }
        }
        if bcfOut == nil, let d = dsts.first(where: { $0.name.localizedCaseInsensitiveContains(outMatch) }) {
            bcfOut = d; changed = true
        }
        return changed
    }

    // MARK: Versturen

    func sendToBCF(_ bytes: [UInt8]) {
        guard let d = bcfOut else { return }
        withPacketList(bytes) { MIDISend(outPort, d.ref, $0) }
    }

    func sendToLogic(_ bytes: [UInt8]) {
        withPacketList(bytes) { MIDIReceived(virtualSource, $0) }
    }

    private func withPacketList(_ bytes: [UInt8], _ body: (UnsafePointer<MIDIPacketList>) -> Void) {
        let size = 1024 + bytes.count
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let pkt = MIDIPacketListInit(list)
        _ = MIDIPacketListAdd(list, size, pkt, 0, bytes.count, bytes)
        body(UnsafePointer(list))
    }

    // MARK: Ontvangen

    static func bytes(from list: UnsafePointer<MIDIPacketList>) -> [UInt8] {
        var out: [UInt8] = []
        let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)!
        for packet in list.unsafeSequence() {
            let len = Int(packet.pointee.length)
            let base = UnsafeRawPointer(packet).advanced(by: dataOffset)
            out.append(contentsOf: UnsafeRawBufferPointer(start: base, count: len))
        }
        return out
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr {
            throw NSError(domain: "BCFBridge", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "\(what) mislukt (OSStatus \(status))"])
        }
    }
}
