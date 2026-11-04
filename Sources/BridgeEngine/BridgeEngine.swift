import BridgeCore
import Foundation

public let bridgeVersion = "0.5.0"

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
            self.log.line("LEARN: \(text)   " + tr("(type skip to skip, stop to stop)", "(typ skip om over te slaan, stop om te stoppen)"))
            self.status.learnPrompt = text
            self.emit()
        }
        learner.learned = { [unowned self] target, mapping, detail in
            let cleared = self.settings.assign(mapping, to: target)
            self.router.update(self.settings)
            var msg = tr("LEARNED", "GELEERD") + ": \(target.label(self.settings)) = CC \(mapping.cc) " + tr("channel", "kanaal") + " \(mapping.channel)"
            if !detail.isEmpty { msg += ", \(detail)" }
            if !cleared.isEmpty {
                msg += tr(". Removed from: ", ". Weggehaald bij: ") + cleared.map { $0.label(self.settings) }.joined(separator: ", ")
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
            log.line(tr("START FAILED", "STARTEN MISLUKT") + ": \(failure.localizedDescription)")
            emit()
            throw failure
        }
    }

    private func startOnQueue() throws {
        log.plain("BCF Bridge \(bridgeVersion)")
        log.plain(tr("Log file", "Logbestand") + ": \(log.fileURL.path)")
        log.plain(tr("Settings", "Instellingen") + ": \(BridgeSettings.file.path)")
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
            self.log.line("MIDI setup changed, looking for ports again")
            self.reconnect()
        }
        try io.start()
        running = true
        log.line("Virtual port \"\(MIDIIO.virtualName)\" created (in and out)")
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
            self.log.line("Shutting down")
            self.io.stop()
        }
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil { work() } else { queue.sync(execute: work) }
    }

    private static let queueKey = DispatchSpecificKey<Bool>()

    // MARK: Publieke bediening (veilig vanaf elke thread)

    public func command(_ raw: String) { queue.async { self.runCommand(raw) } }
    public func learnAll() { command("learn") }
    public func learn(_ t: LearnTarget) { command("learn \(t.command)") }
    public func clearMapping(_ t: LearnTarget) { command("clear \(t.command)") }
    public func learnSkip() { command("skip") }
    public func learnStop() { queue.async { self.learner.stop() } }
    public func resetMapping() { command("reset") }

    public func setRowFunction(top: Bool, _ f: ButtonFunction) {
        command("\(top ? "row1" : "row2") \(f.rawValue)")
    }

    public func setReleaseMs(_ ms: Int) { command("release \(ms)") }
    public func setHideModelFromLogic(_ on: Bool) { command("hidemodel \(on ? "on" : "off")") }

    /// Huidige mapping als JSON-bestand wegschrijven.
    public func exportMapping(to url: URL, completion: @escaping (Error?) -> Void) {
        queue.async {
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(self.settings).write(to: url, options: .atomic)
                self.log.line(tr("Mapping exported to", "Mapping geëxporteerd naar") + " \(url.path)")
                completion(nil)
            } catch {
                self.log.line(tr("Export failed", "Exporteren mislukt") + ": \(error.localizedDescription)")
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
                self.saveSettings(tr("Mapping imported from \(url.lastPathComponent) (previous version kept as \(BridgeSettings.backup.lastPathComponent))", "Mapping geïmporteerd uit \(url.lastPathComponent) (vorige versie bewaard als \(BridgeSettings.backup.lastPathComponent))"))
                completion(nil)
            } catch {
                self.log.line(tr("Import failed", "Importeren mislukt") + ": \(error.localizedDescription)")
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
        Commands (type and press Enter):
          learn              learn everything: faders, encoders, button rows, bank/channel
          learn fader 3      learn one element (also: encoder 2, push 1, top 4, bottom 5,
                             bankleft, bankright, chanleft, chanright, rewind, forward, stop, play, record)
          clear fader 3      remove the mapping of one element
          skip / stop        while learning: skip element / stop learning
          row1 mute          function of the top button row (mute, solo, select or rec)
          row2 solo          function of the bottom button row
          mapping            show what is mapped to what
          reset              back to the default mapping (previous version is kept)
          status             show connection and state
          release 400        release fader touch after this many ms without movement
          logall             log meters and display messages on/off
          hidemodel on|off   rename the BCF2000 model in CoreMIDI so Logic does not auto-add it
          ports              show MIDI ports
          help               this overview
          quit               stop
        """)
    }

    func printPorts() {
        log.plain("MIDI sources:")
        for e in MIDIIO.sources() { log.plain("  - \(e.name)") }
        log.plain("MIDI destinations:")
        for e in MIDIIO.destinations() { log.plain("  - \(e.name)") }
    }

    func printMapping() {
        log.plain("Mapping:")
        for t in BridgeSettings.allTargets {
            log.plain("  \(t.label(settings).padding(toLength: 46, withPad: " ", startingAt: 0)) \(settings.mapping(for: t)?.short ?? "-")")
        }
        log.plain("  Touch release after \(settings.touchReleaseMs) ms")
    }

    // MARK: Verbinding met de BCF2000

    private func reconnect() {
        let hadIn = io.bcfIn?.name, hadOut = io.bcfOut?.name
        applyModelName()
        io.connectBCF(inMatch: options.inMatch, outMatch: options.outMatch)
        let force = firstConnect
        firstConnect = false
        if force || io.bcfIn?.name != hadIn {
            log.line(io.bcfIn.map { tr("BCF2000 input connected", "BCF2000 ingang verbonden") + ": \($0.name)" }
                     ?? tr("BCF2000 input NOT found (looking for \"\(options.inMatch)\")", "BCF2000 ingang NIET gevonden (zoek op \"\(options.inMatch)\")"))
        }
        if force || io.bcfOut?.name != hadOut {
            log.line(io.bcfOut.map { tr("BCF2000 output connected", "BCF2000 uitgang verbonden") + ": \($0.name)" }
                     ?? tr("BCF2000 output NOT found (looking for \"\(options.outMatch)\")", "BCF2000 uitgang NIET gevonden (zoek op \"\(options.outMatch)\")"))
        }
        emit()
    }

    /// Logic recognises the BCF2000 by its CoreMIDI model name and then adds it as a control surface
    /// on every launch. While the option is on, the model name is changed; when it is off, it is restored.
    private func applyModelName() {
        if MIDIIO.setBCFModelHidden(settings.hideModelFromLogic) {
            log.line(settings.hideModelFromLogic
                ? tr("BCF2000 model name changed to \"\(MIDIIO.bridgeModelName)\" so Logic does not add it as a control surface",
                     "Modelnaam BCF2000 gewijzigd in \"\(MIDIIO.bridgeModelName)\", zodat Logic hem niet als control surface toevoegt")
                : tr("BCF2000 model name restored to \"BCF2000\"", "Modelnaam BCF2000 teruggezet naar \"BCF2000\""))
        }
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
            log.line("   ..  not mapped (use learn to map this element)")
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
            if let reply { toLogic(reply, "Mackie reply: \(MIDIDescribe.mackie(reply))") }
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
            log.line("bridge -> BCF   \(shortHex(m))  \(why)  [NOT sent: no BCF2000 output]")
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
            log.line("\(message). " + tr("Saved.", "Opgeslagen."))
            status.lastSaved = Date()
            status.lastSaveMessage = message
        } catch {
            log.line("\(message), " + tr("but SAVING FAILED", "maar OPSLAAN MISLUKT") + ": \(error.localizedDescription)")
            status.error = tr("Saving failed", "Opslaan mislukt") + ": \(error.localizedDescription)"
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
                log.line("LEARN: " + tr("learning everything. Operate each element when asked.", "alles leren. Bedien elk element als erom gevraagd wordt."))
                learner.start(LearnTarget.learnAllOrder)
            } else if let t = LearnTarget.parse(Array(words.dropFirst())) {
                learner.start([t])
            } else {
                log.line(tr("Unknown element", "Onbekend element") + ": \(raw). " + tr("Examples", "Voorbeelden") + ": learn fader 3, learn encoder 2, learn top 1, learn bankleft")
            }
        case "clear":
            if let t = LearnTarget.parse(Array(words.dropFirst())) {
                settings.set(nil, for: t)
                router.update(settings)
                saveSettings(tr("\(t.label(settings)) unmapped", "\(t.label(settings)) ontkoppeld"))
            } else {
                log.line(tr("Unknown element", "Onbekend element") + ": \(raw). " + tr("Example", "Voorbeeld") + ": clear fader 3")
            }
        case "skip":
            learner.skip()
        case "stop" where learner.isActive:
            learner.stop()
        case "reset":
            learner.stop()
            var fresh = BridgeSettings()
            fresh.touchReleaseMs = settings.touchReleaseMs
            fresh.hideModelFromLogic = settings.hideModelFromLogic
            settings = fresh
            router.update(settings)
            saveSettings(tr("Mapping reset to the default (previous version kept as \(BridgeSettings.backup.lastPathComponent))", "Mapping teruggezet naar de standaard (vorige versie bewaard als \(BridgeSettings.backup.lastPathComponent))"))
            printMapping()
        case "row1", "row2":
            guard words.count > 1, let f = ButtonFunction(rawValue: words[1]) else {
                log.line("Usage: \(cmd) mute   (mute, solo, select, rec)")
                return
            }
            if cmd == "row1" { settings.topRowFunction = f } else { settings.bottomRowFunction = f }
            router.update(settings)
            saveSettings(cmd == "row1" ? tr("Top button row is now \(f.label)", "Bovenste knoprij is nu \(f.label)") : tr("Bottom button row is now \(f.label)", "Onderste knoprij is nu \(f.label)"))
        case "mapping":
            printMapping()
        case "status":
            log.line("STATUS: BCF in = \(io.bcfIn?.name ?? "-"), BCF out = \(io.bcfOut?.name ?? "-"), Mackie online = \(handshake.online ? "yes" : "no")")
            let touched = router.faders.filter { $0.touched }.map { String($0.index + 1) }
            log.line("STATUS: faders touched = \(touched.isEmpty ? "none" : touched.joined(separator: ",")), positions = \(router.faders.map { $0.bcfPosition.map(String.init) ?? "-" }.joined(separator: " ")), hidden meter/display messages = \(hiddenCount)")
        case "ports":
            printPorts()
        case "logall":
            options.logAll.toggle()
            log.line("Log meters and display messages: \(options.logAll ? "on" : "off")")
        case "release":
            if words.count > 1, let ms = Int(words[1]), (50...3000).contains(ms) {
                settings.touchReleaseMs = ms
                router.update(settings)
                saveSettings(tr("Fader release after \(ms) ms", "Fader loslaten na \(ms) ms"))
            } else {
                log.line("Usage: release 400   (50 to 3000 ms)")
            }
        case "hidemodel":
            guard words.count > 1, ["on", "off"].contains(words[1]) else {
                log.line("Usage: hidemodel on   (or off)")
                return
            }
            settings.hideModelFromLogic = words[1] == "on"
            router.update(settings)
            saveSettings(settings.hideModelFromLogic
                ? tr("BCF2000 model name is hidden from Logic", "Modelnaam BCF2000 wordt verborgen voor Logic")
                : tr("BCF2000 model name restored", "Modelnaam BCF2000 teruggezet"))
            applyModelName()
        case "help":
            printHelp()
        case "quit", "exit", "q":
            onQuitRequested?()
        default:
            log.line(tr("Unknown command", "Onbekend commando") + ": \(raw)  " + tr("(type help)", "(typ help)"))
        }
    }
}
