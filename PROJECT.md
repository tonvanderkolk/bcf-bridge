# BCF Bridge

Versie: 0.5.0

Kleine macOS-tool die een Behringer BCF2000 laat werken als Mackie Control-oppervlak in Logic Pro. De BCF2000 draait in gewone CC-modus (U-1) en de bridge vertaalt in beide richtingen tussen die CC-berichten en het Mackie Control-protocol. Logic praat alleen met de virtuele MIDI-poort "BCF Bridge".

## Status

Mijlpaal 3: menubalk-app "BCF Bridge" met dezelfde bridge als de command line-tool. Getest door Ton op 4 november 2026: start bij inloggen en werkt met Logic zonder Terminal.

Logic voegde na elke start zelf een BCF2000-control surface toe. De bridge zet daarom bij het starten de modelnaam van de BCF2000 in CoreMIDI op "BCF2000 Bridge". De BCF2000 zelf wordt niet aangepast. Dit is uit te zetten in het menu; dan gaat de naam terug naar "BCF2000".

Mijlpaal 5: voorbereiding om openbaar te maken. App tweetalig, Engelse README (README.md), MIT-licentie. Openbaar sinds 4 november 2026: https://github.com/tonvanderkolk/bcf-bridge, eerste release v0.5.0.

- Menubalk-icoon met status BCF2000 en Logic (driehoek = BCF2000 niet gevonden of startfout)
- Functie van beide knoprijen kiezen, fader-loslaattijd instellen, zichtbare bevestiging na opslaan
- Alles leren met overslaan en stoppen
- Mapping exporteren, importeren en terugzetten naar de standaard
- Mappingvenster: alle koppelingen bekijken, per element opnieuw leren of wissen
- Logvenster met kopieerknop en knop naar het logbestand
- Starten bij inloggen
- Weigert te starten als er al een bridge draait (Terminal of app), zodat Logic geen dubbele poort ziet

Eerder:

Mijlpaal 2: command line-tool die alle kanalen vertaalt. Getest in Logic op 4 november 2026: faders, encoders, mute, solo, bank en kanaal werken. Transport heeft nog geen knop.

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
- `Sources/BridgeEngine/` CoreMIDI, logbestand en de motor die alles verbindt (gedeeld door app en command line)
- `Sources/BCFBridgeApp/` SwiftUI menubalk-app
- `Sources/bcf-bridge/` command line-tool en selftest
- `scripts/build-app.sh` bouwt `build/BCF Bridge.app`, met `install` ook naar /Applications
- `docs/dev/TESTEN.md` stap-voor-stap testinstructies voor Logic

## Bouwen en draaien

```bash
scripts/build-app.sh install          # menubalk-app bouwen, installeren en starten
swift build && .build/debug/bcf-bridge selftest
.build/release/bcf-bridge             # command line-versie (niet tegelijk met de app)
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
