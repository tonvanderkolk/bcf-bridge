# BCF Bridge

Versie: 0.1.0

Kleine macOS-tool die een Behringer BCF2000 laat werken als Mackie Control-oppervlak in Logic Pro. De BCF2000 draait in gewone CC-modus (U-1) en de bridge vertaalt in beide richtingen tussen die CC-berichten en het Mackie Control-protocol. Logic praat alleen met de virtuele MIDI-poort "BCF Bridge".

## Status

Mijlpaal 1: command line-tool die het protocol bewijst met alleen fader 1.

- Toont alle MIDI-poorten en koppelt automatisch aan de BCF2000 (ook na loskoppelen)
- Maakt virtuele poort "BCF Bridge" aan (in en uit)
- Logt alle MIDI in beide richtingen met hex en uitleg, op het scherm en in `~/Library/Logs/BCF Bridge/`
- Handelt de Mackie-handshake met Logic af
- Vertaalt fader 1 met gesimuleerde touch en onderdrukking van feedback tijdens aanraken
- Learn-commando voor fader 1, instellingen in `~/Library/Application Support/BCF Bridge/mapping.json` met backup van de vorige versie

## Tech stack

- Swift Package (alleen Command Line Tools nodig, geen Xcode)
- CoreMIDI
- macOS 13 of nieuwer, Apple Silicon

## Structuur

- `Sources/BridgeCore/` vertaallogica zonder hardware-afhankelijkheid (parser, Mackie-handshake, fader-vertaling, instellingen)
- `Sources/bcf-bridge/` command line-tool (CoreMIDI, log, toetsenbordcommando's, selftest)
- `TESTEN.md` stap-voor-stap testinstructies voor Logic

## Bouwen en draaien

```bash
swift build -c release
.build/release/bcf-bridge selftest
.build/release/bcf-bridge
```

## Ontwerpkeuzes

- Geen eigen firmware: de BCF2000 blijft ongewijzigd
- Touch wordt gesimuleerd: touch aan bij de eerste beweging, touch uit na 400 ms stilstand (instelbaar met `release <ms>`)
- Zolang een fader aangeraakt is gaat feedback van Logic niet naar de motor. Na loslaten wordt de laatste stand van Logic alsnog gestuurd als die afwijkt
- Gelijke standen worden niet opnieuw naar de motor gestuurd (minder gezoem)
- Een waarde die de BCF2000 binnen 150 ms terugstuurt nadat de motor erheen is gestuurd geldt als echo en telt niet als aanraking
