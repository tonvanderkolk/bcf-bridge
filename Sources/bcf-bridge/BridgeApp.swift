import BridgeCore
import Foundation

let appVersion = "0.1.0"

struct Options {
    var inMatch = "BCF2000"
    var outMatch = "BCF2000"
    var logAll = false
}

/// Koppelt alles aan elkaar. Alle code hier draait op `queue`.
final class BridgeApp {
    let queue = DispatchQueue(label: "bcf-bridge")
    let log = Logger()
    let io: MIDIIO
    let clock: QueueClock
    let handshake = MackieHandshake()
    var settings = BridgeSettings.load()
    var options: Options
    let fader1: FaderBridge

    private var bcfParser = MIDIParser()
    private var logicParser = MIDIParser()
    private var learning = false
    private var hiddenCount = 0

    init(options: Options) {
        self.options = options
        io = MIDIIO(queue: queue)
        clock = QueueClock(queue: queue)
        fader1 = FaderBridge(index: 0, mapping: settings.fader1, releaseMs: settings.touchReleaseMs, clock: clock)

        fader1.sendToLogic = { [unowned self] bytes, why in self.toLogic(bytes, why) }
        fader1.sendToBCF = { [unowned self] bytes, why in self.toBCF(bytes, why) }
        fader1.note = { [unowned self] text in self.log.line("   ..  \(text)") }
    }

    func start() throws {
        log.plain("BCF Bridge \(appVersion)  (command line test, alleen fader 1)")
        log.plain("Logbestand: \(log.fileURL.path)")
        log.plain("Instellingen: \(BridgeSettings.file.path)")
        log.plain("Fader 1 = CC \(settings.fader1.cc) op kanaal \(settings.fader1.channel), touch loslaten na \(settings.touchReleaseMs) ms")
        log.plain("")
        printPorts()

        io.onBCFBytes = { [unowned self] bytes in
            self.bcfParser.feed(bytes) { self.handleBCF($0) }
        }
        io.onLogicBytes = { [unowned self] bytes in
            self.logicParser.feed(bytes) { self.handleLogic($0) }
        }
        io.onSetupChanged = { [unowned self] in
            self.log.line("MIDI-configuratie gewijzigd, poorten opnieuw zoeken")
            self.reconnect()
        }
        try io.start()
        log.line("Virtuele poort \"\(MIDIIO.virtualName)\" aangemaakt (in en uit)")
        reconnect()
        scheduleRetry()
        log.plain("")
        log.plain("Commando's: learn, status, ports, logall, release <ms>, quit")
        log.plain("")
    }

    func printPorts() {
        log.plain("MIDI-ingangen (sources):")
        for e in MIDIIO.sources() { log.plain("  - \(e.name)") }
        log.plain("MIDI-uitgangen (destinations):")
        for e in MIDIIO.destinations() { log.plain("  - \(e.name)") }
    }

    private var firstConnect = true

    private func reconnect() {
        let hadIn = io.bcfIn?.name, hadOut = io.bcfOut?.name
        io.connectBCF(inMatch: options.inMatch, outMatch: options.outMatch)
        let force = firstConnect
        firstConnect = false
        if force || io.bcfIn?.name != hadIn {
            log.line(io.bcfIn.map { "BCF2000 ingang verbonden: \($0.name)" }
                     ?? "BCF2000 ingang NIET gevonden (zoek op \"\(options.inMatch)\")")
        }
        if force || io.bcfOut?.name != hadOut {
            log.line(io.bcfOut.map { "BCF2000 uitgang verbonden: \($0.name)" }
                     ?? "BCF2000 uitgang NIET gevonden (zoek op \"\(options.outMatch)\")")
        }
    }

    /// Vangnet naast de setup-melding: elke 3 seconden kijken of de BCF2000 terug is.
    private func scheduleRetry() {
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            if self.io.bcfIn == nil || self.io.bcfOut == nil { self.reconnect() }
            self.scheduleRetry()
        }
    }

    // MARK: Berichten

    private func handleBCF(_ m: [UInt8]) {
        log.line("BCF  -> bridge  \(MIDIDescribe.hex(m).padding(toLength: 12, withPad: " ", startingAt: 0))  \(MIDIDescribe.generic(m))")

        if learning, m.count == 3, m[0] & 0xF0 == 0xB0 {
            learning = false
            let mapping = ControlMapping(channel: Int(m[0] & 0x0F) + 1, cc: Int(m[1]))
            settings.fader1 = mapping
            fader1.mapping = mapping
            saveSettings("Fader 1 geleerd: CC \(mapping.cc) op kanaal \(mapping.channel)")
            return
        }
        if fader1.matches(m) {
            fader1.fromBCF(value: Int(m[2]))
        }
    }

    private func handleLogic(_ m: [UInt8]) {
        let noisy = MIDIDescribe.isNoisyLogicMessage(m)
        if noisy && !options.logAll {
            hiddenCount += 1
        } else {
            log.line("Logic -> bridge \(shortHex(m))  \(MIDIDescribe.mackie(m))")
        }

        if m.first == 0xF0 {
            let (reply, why) = handshake.handle(m)
            if let why { log.line("   ..  \(why)") }
            if let reply { toLogic(reply, "Mackie-antwoord: \(MIDIDescribe.mackie(reply))") }
            return
        }
        if m.count == 3, m[0] == 0xE0 {
            fader1.fromLogic(pitchBend: Int(m[1]) | (Int(m[2]) << 7))
        }
    }

    private func toLogic(_ m: [UInt8], _ why: String) {
        io.sendToLogic(m)
        log.line("bridge -> Logic \(shortHex(m))  \(why)")
    }

    private func toBCF(_ m: [UInt8], _ why: String) {
        if io.bcfOut == nil {
            log.line("bridge -> BCF   \(shortHex(m))  \(why)  [NIET verstuurd: geen BCF2000-uitgang]")
            return
        }
        io.sendToBCF(m)
        log.line("bridge -> BCF   \(shortHex(m))  \(why)")
    }

    private func shortHex(_ m: [UInt8]) -> String {
        let h = m.count > 24 ? MIDIDescribe.hex(Array(m.prefix(24))) + " ..." : MIDIDescribe.hex(m)
        return h.count < 12 ? h.padding(toLength: 12, withPad: " ", startingAt: 0) : h
    }

    private func saveSettings(_ message: String) {
        do {
            try settings.save()
            log.line("\(message). Opgeslagen in \(BridgeSettings.file.path) (vorige versie: \(BridgeSettings.backup.lastPathComponent))")
        } catch {
            log.line("\(message), maar OPSLAAN MISLUKT: \(error.localizedDescription)")
        }
    }

    // MARK: Commando's van het toetsenbord

    func command(_ raw: String) {
        let parts = raw.trimmingCharacters(in: .whitespaces).lowercased().split(separator: " ")
        guard let cmd = parts.first else { return }
        switch cmd {
        case "learn":
            learning = true
            log.line("LEARN: beweeg nu fader 1 op de BCF2000")
        case "status":
            log.line("STATUS: BCF in = \(io.bcfIn?.name ?? "-"), BCF uit = \(io.bcfOut?.name ?? "-"), Mackie online = \(handshake.online ? "ja" : "nee")")
            log.line("STATUS: fader 1 = CC \(settings.fader1.cc) kanaal \(settings.fader1.channel), aangeraakt = \(fader1.touched ? "ja" : "nee"), stand = \(fader1.bcfPosition.map(String.init) ?? "-"), verborgen meter/display-berichten = \(hiddenCount)")
        case "ports":
            printPorts()
        case "logall":
            options.logAll.toggle()
            log.line("Meters en display-berichten loggen: \(options.logAll ? "aan" : "uit")")
        case "release":
            if parts.count > 1, let ms = Int(parts[1]), (50...3000).contains(ms) {
                settings.touchReleaseMs = ms
                fader1.releaseMs = ms
                saveSettings("Touch loslaten na \(ms) ms")
            } else {
                log.line("Gebruik: release 400   (tussen 50 en 3000 ms)")
            }
        case "quit", "exit", "q":
            shutdown()
        default:
            log.line("Onbekend commando: \(raw)")
        }
    }

    func shutdown() {
        fader1.forceRelease()
        log.line("Afsluiten")
        io.stop()
        exit(0)
    }
}
