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
- [x] App-icoon
- [x] Logic voegt de BCF2000 niet meer automatisch toe (modelnaam in CoreMIDI aangepast)
- [x] Test met Ton: app installeren, starten bij inloggen, werken met Logic na herstart, één Mackie Control (4 november 2026)

## 0.4 Mapping in de app
- [x] Mappingvenster met alle koppelingen
- [x] Per element opnieuw leren of wissen
- [x] Test met Ton: venster duidelijk, per element leren werkt (4 november 2026)

## 0.5 Openbaar maken
- [x] App tweetalig (Engels en Nederlands)
- [x] Engelse README en MIT-licentie
- [x] Modelnaam-aanpassing uitschakelbaar
- [x] Release-zip
- [x] Ton controleert README en app, screenshots toegevoegd
- [x] Repository openbaar en release v0.5.0 gepubliceerd (4 november 2026)
- [ ] Commentaar in de code naar het Engels
- [ ] Eventueel: Apple Developer ID en notarisatie, zodat de app zonder waarschuwing opent

## Later
- [ ] Onderzoeken of een eigen BCF2000-preset faders als 14-bit Pitch Bend kan sturen
- [ ] Vrij te kiezen in- en uitgangspoort in de app (5-pins MIDI via interface)

## Bewust niet
- Transport (play, stop, record) op de BCF2000: Ton gebruikt hem om te mixen (faders, panning, mute, solo), niet voor transport (besluit 4 november 2026)
