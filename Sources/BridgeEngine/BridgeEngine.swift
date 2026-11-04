import BridgeCore
import Foundation

public let bridgeVersion = "0.3.1"

public struct EngineOptions {
    public var inMatch = "BCF2000"
    public var outMatch = "BCF2000"
    public var logAll = false
    /// Logregels ook naar stdout (command line)
    public var echoLog = true
    public init() {}
}

/// Momentopname voor de app: wat is verbonden, wat wordt er geleerd, welke instellingen gelden.
public struct EngineStatus {
    public var bcfIn: String?
    public var bcfOut: String?
    public var logicOnline = false
    public var learnPrompt: String?
    public var settings = BridgeSettings()
    public var lastSaved: Date?
    public var lastSaveMessage: String?
    public var error: String?
    public init() {}
}

/// De bridge zelf. Alle interne code draait op `queue`; de publieke methodes zijn veilig vanaf elke thread.
public final class BridgeEngine {
    public let queue = DispatchQueue(label: "bcf-bridge")
    public let log = Logger()
    let io: MIDIIO
    let clock: QueueClock
    let handshake = MackieHandshake()
    var settings = BridgeSettings.load()
    var options: EngineOptions
    let router: Router
    let learner: Learner

    /// Wordt aangeroepen op `queue` bij elke statuswijziging
    public var onStatus: ((EngineStatus) -> Void)?
    /// Wordt aangeroepen als iemand "quit" typt
    public var onQuitRequested: (() -> Void)?

    private var status = EngineStatus()
    private var bcfParser = MIDIParser()
    private var logicParser = MIDIParser()
    private var hiddenCount = 0
    private var savedThisRun = false
    private var firstConnect = true
    private var running = false

    public init(options: EngineOptions = EngineOptions()) {
        self.options = options
        log.echo = options.echoLog
        queue.setSpecific(key: Self.queueKey, value: true)
        io = MIDIIO(queue: queue)
        clock = QueueClock(queue: queue)
        router = Router(settings: settings, clock: clock)
        learner = Learner(clock: clock)
        status.settings = settings

        router.sendToLogic = { [unowned self] bytes, why in self.toLogic(bytes, why) }
        router.sendToBCF = { [unowned self] bytes, why in self.toBCF(bytes, why) }
        router.note = { [unowned self] text in self.log.line("   ..  \(text)") }

        learner.prompt = { [unowned self] target in
            let text = "\(target.label(self.settings)): \(target.instruction)"
            self.log.line("LEARN: \(text)   (typ skip om over te slaan, stop om te stoppen)")
            self.status.learnPrompt = text
            self.emit()
        }
        learner.learned = { [unowned self] target, mapping, detail in
            let cleared = self.settings.assign(mapping, to: target)
            self.router.update(self.settings)
            var msg = "GELEERD: \(target.label(self.settings)) = CC \(mapping.cc) kanaal \(mapping.channel)"
            if !detail.isEmpty { msg += ", \(detail)" }
            if !cleared.isEmpty {
                msg += ". Weggehaald bij: " + cleared.map { $0.label(self.settings) }.joined(separator: ", ")
            }
            self.saveSettings(msg)
        }
        learner.finished = { [unowned self] text in
            self.log.line("LEARN: \(text)")
            self.status.learnPrompt = nil
            self.emit()
        }
    }

    // MARK: Starten en stoppen

    /// Start de bridge. Niet aanroepen vanaf `queue`.
    public func start() throws {
        var failure: Error?
        queue.sync {
            do { try self.startOnQueue() } catch { failure = error }
        }
        if let failure {
            status.error = failure.localizedDescription
            log.line("STARTEN MISLUKT: \(failure.localizedDescription)")
            emit()
            throw failure
        }
    }

    private func startOnQueue() throws {
        log.plain("BCF Bridge \(bridgeVersion)")
        log.plain("Logbestand: \(log.fileURL.path)")
        log.plain("Instellingen: \(BridgeSettings.file.path)")
        log.plain("")
        printPorts()
        log.plain("")
        printMapping()

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
        running = true
        log.line("Virtuele poort \"\(MIDIIO.virtualName)\" aangemaakt (in en uit)")
        reconnect()
        scheduleRetry()
        emit()
    }

    /// Faders loslaten richting Logic en de virtuele poort opruimen.
    public func shutdown() {
        let work = {
            guard self.running else { return }
            self.running = false
            self.router.releaseAll()
            self.log.line("Afsluiten")
            self.io.stop()
        }
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil { work() } else { queue.sync(execute: work) }
    }

    private static let queueKey = DispatchSpecificKey<Bool>()

    // MARK: Publieke bediening (veilig vanaf elke thread)

    public func command(_ raw: String) { queue.async { self.runCommand(raw) } }
    public func learnAll() { command("learn") }
    public func learnSkip() { command("skip") }
    public func learnStop() { queue.async { self.learner.stop() } }
    public func resetMapping() { command("reset") }

    public func setRowFunction(top: Bool, _ f: ButtonFunction) {
        command("\(top ? "row1" : "row2") \(f.rawValue)")
    }

    public func setReleaseMs(_ ms: Int) { command("release \(ms)") }

    /// Huidige mapping als JSON-bestand wegschrijven.
    public func exportMapping(to url: URL, completion: @escaping (Error?) -> Void) {
        queue.async {
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(self.settings).write(to: url, options: .atomic)
                self.log.line("Mapping geëxporteerd naar \(url.path)")
                completion(nil)
            } catch {
                self.log.line("Exporteren mislukt: \(error.localizedDescription)")
                completion(error)
            }
        }
    }

    /// Mapping inlezen uit een JSON-bestand. De huidige versie wordt eerst als backup bewaard.
    public func importMapping(from url: URL, completion: @escaping (Error?) -> Void) {
        queue.async {
            do {
                let data = try Data(contentsOf: url)
                let s = try JSONDecoder().decode(BridgeSettings.self, from: data)
                self.learner.stop()
                self.settings = s
                self.router.update(s)
                self.savedThisRun = false // altijd een backup van de huidige versie maken
                self.saveSettings("Mapping geïmporteerd uit \(url.lastPathComponent) (vorige versie bewaard als \(BridgeSettings.backup.lastPathComponent))")
                completion(nil)
            } catch {
                self.log.line("Importeren mislukt: \(error.localizedDescription)")
                completion(error)
            }
        }
    }

    // MARK: Status

    private func emit() {
        status.bcfIn = io.bcfIn?.name
        status.bcfOut = io.bcfOut?.name
        status.logicOnline = handshake.online
        status.settings = settings
        onStatus?(status)
    }

    // MARK: Overzichten

    func printHelp() {
        log.plain("""
        Commando's (typen en Enter):
          learn              alles leren: faders, encoders, knoprijen, bank/kanaal, transport
          learn fader 3      één element leren (ook: encoder 2, push 1, top 4, bottom 5,
                             bankleft, bankright, chanleft, chanright, rewind, forward, stop, play, record)
          skip / stop        tijdens leren: element overslaan / leren stoppen
          row1 mute          functie bovenste knoprij (mute, solo, select of rec)
          row2 solo          functie onderste knoprij
          mapping            toon wat waaraan gekoppeld is
          reset              alles terug naar de standaard (vorige versie wordt bewaard)
          status             toon verbinding en stand
          release 400        fader-touch loslaten na zoveel ms stilstand
          logall             meters en display-berichten wel/niet loggen
          ports              toon MIDI-poorten
          help               dit overzicht
          quit               stoppen
        """)
    }

    func printPorts() {
        log.plain("MIDI-ingangen (sources):")
        for e in MIDIIO.sources() { log.plain("  - \(e.name)") }
        log.plain("MIDI-uitgangen (destinations):")
        for e in MIDIIO.destinations() { log.plain("  - \(e.name)") }
    }

    func printMapping() {
        log.plain("Mapping:")
        for t in BridgeSettings.allTargets {
            log.plain("  \(t.label(settings).padding(toLength: 46, withPad: " ", startingAt: 0)) \(settings.mapping(for: t)?.short ?? "-")")
        }
        log.plain("  Touch loslaten na \(settings.touchReleaseMs) ms")
    }

    // MARK: Verbinding met de BCF2000

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
        emit()
    }

    /// Vangnet naast de setup-melding: elke 3 seconden kijken of de BCF2000 terug is.
    private func scheduleRetry() {
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.running else { return }
            if self.io.bcfIn == nil || self.io.bcfOut == nil { self.reconnect() }
            self.scheduleRetry()
        }
    }

    // MARK: Berichten

    private func handleBCF(_ m: [UInt8]) {
        log.line("BCF  -> bridge  \(MIDIDescribe.hex(m).padding(toLength: 12, withPad: " ", startingAt: 0))  \(MIDIDescribe.generic(m))")
        if learner.feed(m) { return }
        if !router.fromBCF(m) {
            log.line("   ..  niet gekoppeld (gebruik learn om dit element te koppelen)")
        }
    }

    private func handleLogic(_ m: [UInt8]) {
        // Tijdens leren Logic-berichten niet tonen, zodat de LEARN-regels zichtbaar blijven
        let noisy = MIDIDescribe.isNoisyLogicMessage(m) || learner.isActive
        if noisy && !options.logAll {
            hiddenCount += 1
        } else {
            log.line("Logic -> bridge \(shortHex(m))  \(MIDIDescribe.mackie(m))")
        }

        if m.first == 0xF0 {
            let wasOnline = handshake.online
            let (reply, why) = handshake.handle(m)
            if let why { log.line("   ..  \(why)") }
            if let reply { toLogic(reply, "Mackie-antwoord: \(MIDIDescribe.mackie(reply))") }
            if wasOnline != handshake.online { emit() }
            return
        }
        router.fromLogic(m)
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

    /// Slaat op. De eerste keer per sessie wordt de vorige versie als backup bewaard.
    private func saveSettings(_ message: String) {
        do {
            try settings.save(makeBackup: !savedThisRun)
            savedThisRun = true
            log.line("\(message). Opgeslagen.")
            status.lastSaved = Date()
            status.lastSaveMessage = message
        } catch {
            log.line("\(message), maar OPSLAAN MISLUKT: \(error.localizedDescription)")
            status.error = "Opslaan mislukt: \(error.localizedDescription)"
        }
        emit()
    }

    // MARK: Tekstcommando's

    private func runCommand(_ raw: String) {
        let words = raw.trimmingCharacters(in: .whitespaces).lowercased().split(separator: " ").map(String.init)
        guard let cmd = words.first else { return }
        switch cmd {
        case "learn":
            if words.count == 1 {
                log.line("LEARN: alles leren. Bedien elk element als erom gevraagd wordt.")
                learner.start(LearnTarget.learnAllOrder)
            } else if let t = LearnTarget.parse(Array(words.dropFirst())) {
                learner.start([t])
            } else {
                log.line("Onbekend leerdoel: \(raw). Voorbeelden: learn fader 3, learn encoder 2, learn top 1, learn bankleft, learn play")
            }
        case "skip":
            learner.skip()
        case "stop" where learner.isActive:
            learner.stop()
        case "reset":
            learner.stop()
            var fresh = BridgeSettings()
            fresh.touchReleaseMs = settings.touchReleaseMs
            settings = fresh
            router.update(settings)
            saveSettings("Mapping teruggezet naar de standaard (vorige versie bewaard als \(BridgeSettings.backup.lastPathComponent))")
            printMapping()
        case "row1", "row2":
            guard words.count > 1, let f = ButtonFunction(rawValue: words[1]) else {
                log.line("Gebruik: \(cmd) mute   (mute, solo, select of rec)")
                return
            }
            if cmd == "row1" { settings.topRowFunction = f } else { settings.bottomRowFunction = f }
            router.update(settings)
            saveSettings("\(cmd == "row1" ? "Bovenste" : "Onderste") knoprij is nu \(f.label)")
        case "mapping":
            printMapping()
        case "status":
            log.line("STATUS: BCF in = \(io.bcfIn?.name ?? "-"), BCF uit = \(io.bcfOut?.name ?? "-"), Mackie online = \(handshake.online ? "ja" : "nee")")
            let touched = router.faders.filter { $0.touched }.map { String($0.index + 1) }
            log.line("STATUS: faders aangeraakt = \(touched.isEmpty ? "geen" : touched.joined(separator: ",")), standen = \(router.faders.map { $0.bcfPosition.map(String.init) ?? "-" }.joined(separator: " ")), verborgen meter/display-berichten = \(hiddenCount)")
        case "ports":
            printPorts()
        case "logall":
            options.logAll.toggle()
            log.line("Meters en display-berichten loggen: \(options.logAll ? "aan" : "uit")")
        case "release":
            if words.count > 1, let ms = Int(words[1]), (50...3000).contains(ms) {
                settings.touchReleaseMs = ms
                router.update(settings)
                saveSettings("Touch loslaten na \(ms) ms")
            } else {
                log.line("Gebruik: release 400   (tussen 50 en 3000 ms)")
            }
        case "help":
            printHelp()
        case "quit", "exit", "q":
            onQuitRequested?()
        default:
            log.line("Onbekend commando: \(raw)  (typ help)")
        }
    }
}
