# Changelog

## 0.3.0 - 2026-11-04
- Menubalk-app "BCF Bridge" (SwiftUI): status van BCF2000 en Logic, knoprijfuncties, fader-loslaattijd, alles leren, exporteren, importeren, standaard herstellen, starten bij inloggen
- Logvenster met kopieerknop en knop naar het logbestand
- Bridge-motor verplaatst naar een gedeelde bibliotheek (BridgeEngine), gebruikt door app en command line
- Bridge weigert te starten als er al een bridge draait
- Logbestanden ouder dan 14 dagen worden opgeruimd, een logbestand groeit niet verder dan 50 MB
- Script `scripts/build-app.sh` bouwt en installeert de app

## 0.2.1 - 2026-11-04
- Standaardmapping aangevuld met de vier knoppen rechtsonder (CC 89-92: bank links/rechts, kanaal links/rechts), bevestigd met de echte BCF2000
- Commando `reset` zet de mapping terug naar de standaard, vorige versie blijft bewaard
- Tijdens het leren worden berichten van Logic niet getoond, zodat de LEARN-regels zichtbaar blijven

## 0.2.0 - 2026-11-04
- Faders 1-8 met gesimuleerde touch en feedback-onderdrukking
- Encoders 1-8 als V-Pots, absoluut of relatief, encoderstand volgt de LED-krans van Logic
- Bovenste en onderste knoprij met lampjes, functie per rij instelbaar met `row1` en `row2`
- Bank en kanaal links/rechts, transport en encoder indrukken
- Learn-modus: `learn` voor alles achter elkaar, `learn fader 3` enzovoort voor één element, met `skip` en `stop`
- Herkenning van absolute en relatieve encoders en van toggle- en momentary-knoppen
- Instellingen versie 2, oude instellingen worden automatisch overgenomen
- Commando's `mapping` en `help`
- Status toont "Mackie online = ja" ook als Logic de host connection reply overslaat

## 0.1.0 - 2026-11-04
- Project opgezet als Swift Package met PROJECT.md, ROADMAP.md en TESTEN.md
- Command line-tool `bcf-bridge`: poorten tonen, virtuele poort "BCF Bridge", MIDI-log met uitleg
- Mackie-handshake (device query, host connection, versie en serienummer)
- Fader 1: CC naar Pitch Bend met gesimuleerde touch, feedback-onderdrukking, ontdubbelen en echo-filter
- Learn-commando voor fader 1, instellingen in JSON met backup van de vorige versie
- Automatisch opnieuw verbinden met de BCF2000
- `selftest` die de vertaallogica zonder hardware controleert
