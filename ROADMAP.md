# Roadmap

## 0.1 Protocol bewijzen (command line)
- [x] MIDI-poorten tonen, BCF2000 openen, automatisch opnieuw verbinden
- [x] Virtuele poort "BCF Bridge"
- [x] Leesbare MIDI-log in beide richtingen
- [x] Mackie-handshake
- [x] Fader 1 met gesimuleerde touch en feedback-onderdrukking
- [x] Test met Ton in Logic: fader 1 stabiel

## 0.2 Alle kanalen (command line)
- [x] Faders 1-8
- [x] Encoders als V-Pots (absoluut en relatief), LED-ringen
- [x] Mute-knoppen met LED, tweede knoprij instelbaar (Solo, Select of Rec)
- [x] Bank en kanaal links/rechts
- [x] Transport
- [x] Learn-modus voor alle elementen, ook "alles in één keer"
- [x] Test met Ton in Logic: faders, encoders, mute, solo, bank en kanaal werken (4 november 2026)

## 0.3 Menubalk-app
- [x] SwiftUI menubalk-app met status BCF2000 en Logic
- [x] Ingebouwde log met kopieerknop
- [x] Mapping importeren en exporteren
- [x] Automatisch opslaan met zichtbare bevestiging
- [x] Starten bij inloggen
- [x] Beveiliging tegen twee bridges tegelijk
- [ ] Test met Ton: app installeren, starten bij inloggen, werken met Logic

## Later
- [ ] Transport (play, stop, record) op knoppen, bijvoorbeeld als derde functie voor een knoprij
- [ ] Mapping bekijken en per element opnieuw leren vanuit de app
- [ ] Onderzoeken of een eigen BCF2000-preset faders als 14-bit Pitch Bend kan sturen
- [ ] Vrij te kiezen in- en uitgangspoort in de app (5-pins MIDI via interface)
