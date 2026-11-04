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

    Usage:
      bcf-bridge                 run the bridge in Terminal
      bcf-bridge --list          list all MIDI ports and quit
      bcf-bridge selftest        test the translation logic without hardware

    Options:
      --in  "name"     part of the BCF2000 input name   (default: BCF2000)
      --out "name"     part of the BCF2000 output name  (default: BCF2000)
      --log-all        also log meters, timecode and LCD text

    Run the bridge either in Terminal or as the menu bar app, not both at once.
    Set BCF_BRIDGE_LANG=nl for Dutch messages.
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
        print("MIDI sources:")
        for e in MIDIIO.sources() { print("  - \(e.name)") }
        print("MIDI destinations:")
        for e in MIDIIO.destinations() { print("  - \(e.name)") }
        exit(0)
    default:
        print("Unknown option: \(args[i])  (see --help)")
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
    print(tr("Start failed", "Starten mislukt") + ": \(error.localizedDescription)")
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
