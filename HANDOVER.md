# HANDOVER - BCF Bridge

Gegenereerd: 4 november 2026
Versie: concept (start op 0.1.0)
Status: Nieuw project

---

## Wat is dit project?

BCF Bridge is een kleine macOS-app (menubalk) die een Behringer BCF2000 laat werken als Mackie Control-oppervlak in Logic Pro op een Mac mini met M1. De ingebouwde Mackie Control-emulatie van de BCF2000 werkt niet goed: faders schieten terug en lopen niet synchroon met Logic, mute en panning reageren verkeerd. Eerdere pogingen via modus, poorten en control surface-instellingen hebben dit niet opgelost.

De oplossing: de BCF2000 draait in zijn gewone CC-modus (U-1) en de bridge vertaalt in beide richtingen tussen die CC-berichten en het Mackie Control-protocol. Logic praat met een virtuele MIDI-poort van de bridge en ziet de BCF2000 zelf niet meer als control surface.

Gebruiker: Ton van der Kolk, alleen eigen gebruik. Ton is technisch maar geen programmeur; hij test met het echte apparaat en geeft logs terug.

---

## Tech stack

- **Taal:** Swift (SwiftUI menubalk-app)
- **MIDI:** CoreMIDI (virtuele source + destination aanmaken, BCF2000-poorten openen)
- **Platform:** macOS op Apple Silicon (Mac mini M1), recente macOS-versie
- **DAW:** Logic Pro (recente versie)
- **Opslag instellingen:** JSON-bestand in Application Support (geen database nodig)
- **Versiebeheer:** GitHub, privé repo `tonvanderkolk/bcf-bridge`
- **Distributie:** alleen lokaal bouwen en draaien, geen App Store, geen notarisatie nodig

---

## Genomen besluiten

- Geen eigen firmware voor de BCF2000. Het apparaat blijft ongewijzigd; alle logica zit op de Mac.
- BCF2000 staat in standaard USB-modus (U-1) en stuurt gewone CC-berichten.
- De bridge maakt een virtuele MIDI-poort aan (naam bijv. "BCF Bridge"). In Logic wordt één Mackie Control-oppervlak toegevoegd met in- en output op die virtuele poort. De echte BCF2000-poort wordt in Logic niet als control surface gebruikt.
- Fader-touch wordt door de bridge gesimuleerd (zie protocol hieronder). Ontbrekende of onbetrouwbare touch-berichten zijn de vermoedelijke oorzaak van het terugschieten.
- Mapping van de BCF2000-bedieningselementen gaat via een **learn-modus** in de bridge, zodat we niet afhankelijk zijn van welke preset er op het apparaat staat.
- Ingebouwde MIDI-log in de app die Ton kan kopiëren en terugplakken bij Claude Code voor debuggen.
- Projectstandaard volgen: PROJECT.md, ROADMAP.md, CHANGELOG.md, versienummer vanaf 0.1.0, changelog bij elke wijziging.
- Import en export van de mapping (JSON) plus automatische backup van de vorige mapping bij opslaan.
- Instellingen worden automatisch opgeslagen met zichtbare bevestiging.

---

## Functionele scope v1

1. **8 kanaalfaders** naar Mackie fader 1-8, motorfaders volgen Logic.
2. **8 encoders** naar V-Pots (panning standaard in Logic), LED-ringen volgen Logic.
3. **Mute-knoppen** per kanaal met LED-feedback. Overige knoprij instelbaar als Solo, Select of Rec.
4. **Bank links/rechts** en **kanaal links/rechts** op vier knoppen rechtsonder.
5. **Transport** (play, stop, record, terug, vooruit) waar knoppen over zijn.
6. Menubalk-icoon met status: BCF2000 verbonden ja/nee, Logic verbonden ja/nee.
7. Automatisch opnieuw verbinden als de BCF2000 wordt losgekoppeld of de USB-verbinding wegvalt.
8. Optioneel starten bij inloggen.

Buiten scope v1: master fader, LCD-teksten (de BCF2000 heeft geen display), meters.

---

## Mackie Control-protocol (referentie)

Alles op MIDI-kanaal 1 tenzij anders vermeld. Waarden hieronder zijn gangbaar voor MCU; controleer tijdens het bouwen en log afwijkingen.

**Faders**
- Positie: Pitch Bend op kanaal 1-8 (fader 1-8), 14-bit. Logic stuurt hetzelfde terug als feedback.
- Touch: Note On nootnummer 0x68-0x6F (104-111), velocity 127 = aangeraakt, 0 = losgelaten.

**V-Pots**
- Draaien: CC 0x10-0x17, relatief. 0x01-0x0F = rechtsom (aantal stappen), 0x41-0x4F = linksom.
- Indrukken: Note 0x20-0x27.
- LED-ring feedback van Logic: CC 0x30-0x37.

**Kanaalknoppen** (Note On, 127 = in, 0 = los; Logic stuurt dezelfde nootnummers terug voor LEDs: 127 aan, 1 knipperen, 0 uit)
- Rec arm 0x00-0x07, Solo 0x08-0x0F, Mute 0x10-0x17, Select 0x18-0x1F

**Navigatie en transport**
- Bank links/rechts 0x2E / 0x2F, Kanaal links/rechts 0x30 / 0x31
- Terug 0x5B, Vooruit 0x5C, Stop 0x5D, Play 0x5E, Record 0x5F

**Handshake**
- Logic stuurt SysEx device query `F0 00 00 66 14 00 F7`. De bridge moet antwoorden als een MCU (host connection query `F0 00 00 66 14 01 [7 bytes serienummer] [4 bytes challenge] F7`) en het vervolg afhandelen. Zoek de exacte volgorde uit en log alle SysEx van Logic.

---

## Vertaallogica (kern)

**BCF2000 naar Logic**
- Fader-CC (7-bit) schalen naar 14-bit Pitch Bend.
- Bij de eerste fader-CC: eerst touch-on sturen, dan pitch bend. Na ca. 300-500 ms zonder beweging touch-off sturen (instelbaar).
- Zolang een fader "aangeraakt" is: inkomende fader-feedback van Logic voor die fader **niet** naar de BCF2000 doorsturen. Anders vechten motor en hand.
- Encoder-CC: als de encoder absolute waarden stuurt, verschil met vorige waarde berekenen en omzetten naar relatieve V-Pot-stappen. Als hij relatief stuurt direct doorzetten. Learn-modus detecteert welk type.
- Knop-CC (127/0 of toggle) omzetten naar Note On 127 bij indrukken en 0 bij loslaten. Toggle-gedrag van de BCF-preset neutraliseren.

**Logic naar BCF2000**
- Pitch Bend per fader terug naar 7-bit CC zodat de motorfader beweegt.
- Gelijke waarden niet opnieuw sturen (ontdubbelen) om motorgezoem te beperken.
- LED-ring CC omzetten naar de encoder-waarde op de BCF2000 (LED-krans toont positie).
- LED-notes voor mute/solo/select terugsturen als CC naar de juiste knop zodat het lampje klopt.

---

## Learn-modus

- Ton kiest in de app een doel (bijv. "Fader 3" of "Mute 5") en beweegt of drukt het bijbehorende element op de BCF2000.
- De bridge legt kanaal, CC-nummer en gedrag vast (absoluut/relatief, momentary/toggle).
- Optie "alles in één keer leren": de app loopt de elementen in vaste volgorde langs.
- Mapping opslaan als JSON, exporteren en importeren, vorige versie als backup bewaren.

---

## Openstaande vragen

- Welke preset staat er nu op de BCF2000 en sturen de encoders absoluut of relatief? (Learn-modus vangt dit op, maar handig om te weten.)
- Kan de BCF2000 via een eigen preset faders als Pitch Bend (14-bit) sturen? Dat geeft hogere resolutie. Eerst v1 met 7-bit CC, later onderzoeken.
- Werkt de USB-verbinding van de BCF2000 stabiel op de M1? Zo niet: aansluiten via 5-pins MIDI op een interface. De bridge moet een vrij te kiezen in- en uitgangspoort ondersteunen.
- Moet het een volledige .app worden of volstaat een command line-versie voor de eerste test? Voorstel: eerst minimale CLI om het protocol te bewijzen, daarna menubalk-app.

---

## Volgende stap voor Claude Code

**Instructie:**
> Zet het project op (Swift package of Xcode-project, PROJECT.md, ROADMAP.md, CHANGELOG.md, versie 0.1.0, privé repo tonvanderkolk/bcf-bridge). Bouw daarna als eerste mijlpaal een minimale command line-tool die:
> 1. alle MIDI-poorten toont en de BCF2000-poort opent;
> 2. een virtuele poort "BCF Bridge" aanmaakt;
> 3. alle MIDI in beide richtingen leesbaar logt (hex + uitleg);
> 4. de Mackie-handshake met Logic afhandelt;
> 5. alleen **fader 1** vertaalt inclusief gesimuleerde touch en feedback-onderdrukking.
>
> Geef Ton daarna stap voor stap instructies om dit in Logic te testen (control surface toevoegen op de virtuele poort, de echte BCF2000 daar weghalen). Pas als fader 1 stabiel werkt de rest uitbreiden.

---

## Notities

- Ton is geen programmeur: geef bij elke testronde exacte stappen (wat openen, wat klikken, wat terugplakken).
- Claude Code kan de hardware niet zelf testen. Bouw de log zo dat één keer kopiëren genoeg is om te debuggen.
- De BCF2000 zelf niet flashen of firmware wijzigen.
- Het probleem zit vermoedelijk in ontbrekende touch-berichten en de buggy emulatie van het apparaat, niet in Logic zelf.
- Schrijfstijl in docs: geen komma voor "en", "of" of "noch", geen em dash, geen emoticons.
