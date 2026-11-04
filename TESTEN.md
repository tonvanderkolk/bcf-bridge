# Testinstructies

## Testronde 3: menubalk-app (versie 0.3.0)

### 1. Terminal-bridge stoppen

De app en de Terminal-versie kunnen niet tegelijk draaien. Typ in het Terminal-venster waar de bridge draait `quit` en Enter.

### 2. App bouwen en installeren

Plak in Terminal (één regel, Enter):

```bash
cd "/Users/tonvanderkolk/Documents/TvdK Apps/BCF Bridge" && scripts/build-app.sh install
```

Na ongeveer een minuut staat er `Geïnstalleerd in /Applications en gestart`. Rechtsboven in de menubalk verschijnt een icoon met schuifjes.

### 3. Controleren

1. Klik op het icoon. Bij **BCF2000** en **Logic** moet een groen bolletje staan (bij Logic pas als Logic open is).
2. Test faders, encoders, mute, solo en bank zoals in ronde 2.
3. Zet **Starten bij inloggen** aan.
4. Klik **Log tonen**: je ziet de berichten voorbij komen.

### 4. Na herstart van de Mac

Log opnieuw in, start Logic en kijk of alles meteen werkt zonder Terminal.

Kijk in **Control Surfaces > Setup** of er nog steeds precies één Mackie Control staat (geen BCF2000, geen Mackie Control #2).

---


## Eenmalige voorbereiding in Logic

1. Ga naar **Logic Pro > Control Surfaces > Setup...**
2. Daar mag alleen **Mackie Control** staan, met **Output Port** en **Input Port** op **BCF Bridge**.
3. Staat er ook een **BCF2000** (toetsenbord-icoon)? Klik erop en druk op **Delete**. Logic voegt die soms zelf weer toe als het de BCF2000 ziet, dus kijk hier na elke herstart van Logic even.

## Bridge bouwen en starten

Doe dit in het Terminal-venster. Draait de bridge nog? Typ dan eerst `quit` en Enter.

```bash
cd "/Users/tonvanderkolk/Documents/TvdK Apps/BCF Bridge"
```

```bash
swift build -c release
```

```bash
.build/release/bcf-bridge
```

Laat het venster openstaan zolang je met Logic werkt.

---

# Testronde 2: alle kanalen (versie 0.2.0)

## 1. Alles leren

1. Open Logic met een project met **minstens 8 sporen** (maak er anders een paar lege audiosporen bij).
2. Typ in Terminal `learn` en druk op Enter.
3. De bridge vraagt steeds om één element, bijvoorbeeld `LEARN: Fader 1: beweeg de fader`. Doe precies wat er staat en wacht tot je `GELEERD` ziet. Dan komt vanzelf het volgende.
   - Faders: even op en neer bewegen.
   - Encoders: een paar tikken **rechtsom** draaien en dan loslaten. Na een seconde gaat hij verder.
   - Knoppen: **één keer kort** drukken.
4. Volgorde: fader 1-8, encoder 1-8, bovenste knoprij 1-8, onderste knoprij 1-8, dan Bank links, Bank rechts, Kanaal links, Kanaal rechts (gebruik daarvoor vier knoppen rechtsonder), en tot slot Terugspoelen, Vooruitspoelen, Stop, Play, Record.
5. Heb je geen knop over voor iets? Typ `skip` en Enter. Wil je stoppen? Typ `stop`.
6. Typ daarna `mapping` om te zien wat waaraan gekoppeld is.

## 2. Testen

1. **Faders 1-8**: beweeg ze één voor één. Logic moet meebewegen en na loslaten moeten ze blijven staan.
2. **Encoders**: draai encoder 1. Het panorama van spoor 1 in Logic moet meedraaien. Na even wachten moet de LED-krans van de BCF2000 de stand van Logic tonen.
3. **Bovenste knoprij (Mute)**: druk knop 1. Spoor 1 moet op mute gaan en het lampje aan. Nog een keer: mute uit, lampje uit. Klik ook eens in Logic zelf op M van spoor 1: het lampje moet volgen.
4. **Onderste knoprij (Solo)**: hetzelfde voor solo.
5. **Bank rechts / links**: de faders moeten naar sporen 9-16 en terug springen, en de motorfaders moeten meebewegen.
6. **Transport**: play, stop, record, spoelen.

Wil je de onderste rij liever als Select of Rec? Typ bijvoorbeeld `row2 select` of `row2 rec`.

## 3. Resultaat terugsturen

1. Typ `quit` en Enter.
2. Laat Claude Code per punt hierboven weten wat werkte en wat niet. Claude Code leest het logbestand zelf uit `~/Library/Logs/BCF Bridge`.

## Handige commando's

Typ `help` voor het hele overzicht. De belangrijkste:

- `learn` alles leren, `learn fader 3` of `learn bankright` één element opnieuw leren
- `mapping` laat zien wat waaraan gekoppeld is
- `row1 mute`, `row2 solo` functie van de knoprijen
- `release 600` faders pas na 600 ms stilstand loslaten (standaard 400)
- `status` verbinding en standen
- `quit` stoppen
