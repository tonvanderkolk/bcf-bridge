import BridgeCore
import BridgeEngine
import Foundation

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "selftest" {
    exit(SelfTest.run())
}

if args.contains("--help") || args.contains("-h") {
    print("""
    BCF Bridge \(bridgeVersion)

    Gebruik:
      bcf-bridge                 start de bridge in Terminal
      bcf-bridge --list          toon alle MIDI-poorten en stop
      bcf-bridge selftest        test de vertaallogica zonder hardware

    Opties:
      --in  "naam"     deel van de naam van de BCF2000-ingang  (standaard: BCF2000)
      --out "naam"     deel van de naam van de BCF2000-uitgang (standaard: BCF2000)
      --log-all        ook meters, timecode en LCD-tekst loggen

    Gebruik de bridge in Terminal of de menubalk-app, niet allebei tegelijk.
    """)
    exit(0)
}

var options = EngineOptions()
var i = 0
while i < args.count {
    switch args[i] {
    case "--in" where i + 1 < args.count: options.inMatch = args[i + 1]; i += 1
    case "--out" where i + 1 < args.count: options.outMatch = args[i + 1]; i += 1
    case "--log-all": options.logAll = true
    case "--list":
        print("MIDI-ingangen (sources):")
        for e in MIDIIO.sources() { print("  - \(e.name)") }
        print("MIDI-uitgangen (destinations):")
        for e in MIDIIO.destinations() { print("  - \(e.name)") }
        exit(0)
    default:
        print("Onbekende optie: \(args[i])  (zie --help)")
        exit(2)
    }
    i += 1
}

let engine = BridgeEngine(options: options)
engine.onQuitRequested = {
    engine.shutdown()
    exit(0)
}

do {
    try engine.start()
} catch {
    print("Starten mislukt: \(error.localizedDescription)")
    exit(1)
}
engine.command("help")

// Ctrl-C netjes afhandelen (touch loslaten richting Logic)
signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: engine.queue)
sigint.setEventHandler {
    engine.shutdown()
    exit(0)
}
sigint.resume()

// Toetsenbordcommando's
Thread.detachNewThread {
    while let line = readLine() {
        engine.command(line)
    }
}

dispatchMain()
