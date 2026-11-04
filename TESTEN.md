# Testronde 1: fader 1 in Logic

Doel: kijken of fader 1 van de BCF2000 netjes Logic bestuurt en of de motorfader Logic volgt zonder terug te schieten.

## 1. BCF2000 klaarzetten

1. Sluit de BCF2000 via USB aan op de Mac mini.
2. Controleer dat hij in USB-modus **U-1** staat (de modus kies je bij het aanzetten, zie de handleiding van de BCF2000). Staat er geen U-1 en weet je niet hoe het moet, laat het dan weten.
3. Kies preset 1 (de fabriekspreset). Andere preset kan ook, dan gebruik je straks het learn-commando.

## 2. Logic opruimen (eenmalig)

1. Open Logic Pro.
2. Ga naar **Logic Pro > Control Surfaces > Setup...**
3. Staat daar al een Mackie Control of een BCF2000? Klik erop en druk op **Delete**. Logic mag de BCF2000 niet meer zelf als control surface gebruiken.
4. Sluit het Setup-venster en sluit Logic.

## 3. Bridge bouwen en starten

Open **Terminal** en plak deze regels (één voor één):

```bash
cd "/Users/tonvanderkolk/Documents/TvdK Apps/BCF Bridge"
```

```bash
swift build -c release
```

```bash
.build/release/bcf-bridge
```

Je ziet nu een lijst met MIDI-poorten en regels als `BCF2000 ingang verbonden: ...`. Laat dit venster open staan.

Staat er **NIET gevonden**? Kopieer dan de hele tekst uit Terminal en plak die bij Claude Code.

## 4. Fader 1 controleren

Beweeg fader 1 op de BCF2000. In Terminal moeten regels verschijnen met `BCF  -> bridge ... CC kan.1 #81`.

Zie je een ander CC-nummer, of reageert er niets? Typ in Terminal `learn`, druk op Enter en beweeg fader 1. De bridge onthoudt dan welke fader het is.

## 5. Mackie Control toevoegen in Logic

1. Open Logic Pro met een project met minstens één audiospoor.
2. Ga naar **Logic Pro > Control Surfaces > Setup...**
3. Kies **New > Install...**, selecteer **Mackie Control** (Mackie Designs) en klik **Add**.
4. Klik op het nieuwe Mackie-icoon. Zet in het rechterpaneel **Output Port** en **Input Port** allebei op **BCF Bridge**.
5. In Terminal moet nu kort na elkaar staan: `Device query`, `Host connection reply` en `Mackie-verbinding staat`.

## 6. Testen

Doe de volgende dingen rustig na elkaar:

1. Beweeg fader 1 langzaam omhoog en omlaag. De volume-fader van spoor 1 in Logic moet meebewegen.
2. Laat fader 1 los. Hij moet blijven staan en niet terugschieten.
3. Versleep in Logic met de muis de volume-fader van spoor 1. De motorfader van de BCF2000 moet meebewegen.
4. Start afspelen met volume-automatie op spoor 1 (als je dat hebt). De motorfader moet de automatie volgen.

## 7. Resultaat terugsturen

1. Typ in Terminal `status` en druk op Enter.
2. Typ `quit` en druk op Enter.
3. De log staat ook als bestand in de Finder: **Ga > Ga naar map...** en plak `~/Library/Logs/BCF Bridge`. Pak het nieuwste bestand.
4. Plak de inhoud van dat bestand (of de tekst uit Terminal) bij Claude Code, met een korte zin over wat je zag: werkte het, schoot de fader terug, bromde de motor?

## Handige commando's in de bridge

- `status` laat zien wat er verbonden is
- `learn` leer fader 1 opnieuw
- `release 600` touch pas na 600 ms stilstand loslaten (standaard 400)
- `logall` ook meters en displayberichten loggen
- `ports` alle MIDI-poorten opnieuw tonen
- `quit` stoppen
