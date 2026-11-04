# BCF Bridge

Versie: 0.2.1

Kleine macOS-tool die een Behringer BCF2000 laat werken als Mackie Control-oppervlak in Logic Pro. De BCF2000 draait in gewone CC-modus (U-1) en de bridge vertaalt in beide richtingen tussen die CC-berichten en het Mackie Control-protocol. Logic praat alleen met de virtuele MIDI-poort "BCF Bridge".

## Status

Mijlpaal 2: command line-tool die alle kanalen vertaalt. Getest in Logic: fader 1 (versie 0.1.0) werkt stabiel zonder terugschieten.

- Toont alle MIDI-poorten en koppelt automatisch aan de BCF2000 (ook na loskoppelen)
- Maakt virtuele poort "BCF Bridge" aan (in en uit)
- Logt alle MIDI in beide richtingen met hex en uitleg, op het scherm en in `~/Library/Logs/BCF Bridge/`
- Handelt de Mackie-handshake met Logic af
- Faders 1-8 met gesimuleerde touch en onderdrukking van feedback tijdens aanraken
- Encoders 1-8 als V-Pots (absoluut of relatief), LED-krans van Logic zet de encoderstand terug
- Bovenste en onderste knoprij met lampjes, functie per rij instelbaar (standaard Mute en Solo)
- Bank en kanaal links/rechts, transport en encoder indrukken (via learn te koppelen)
- Learn-modus voor één element of alles achter elkaar, met herkenning van absoluut/relatief en toggle/momentary
- Instellingen in `~/Library/Application Support/BCF Bridge/mapping.json`, vorige versie als `mapping.vorige.json`


- Swift Package (alleen Command Line Tools nodig, geen Xcode)
- CoreMIDI
- macOS 13 of nieuwer, Apple Silicon

## Structuur

- `Sources/BridgeCore/` vertaallogica zonder hardware-afhankelijkheid (parser, Mackie-handshake, faders, encoders, knoppen, router, learn, instellingen)
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
- Absolute encoders worden omgerekend naar relatieve V-Pot-stappen. Na 300 ms stilstand zet de bridge de encoder op de stand van Logic (LED-krans, 11 posities), zodat de LED-krans van de BCF2000 klopt en de encoder niet tegen 0 of 127 vastloopt
- Toggle-knoppen van de BCF2000 sturen per druk één bericht; dat wordt altijd één complete klik naar Logic. Lampjes volgen Logic
- Knoppen zonder lampje in Logic (bank, kanaal, encoder indrukken) worden na een klik weer uitgezet
- Logic voegt zelf een "BCF2000"-control surface toe als het de BCF2000 ziet. Die moet weg, anders bestuurt Logic de BCF2000 langs de bridge heen
