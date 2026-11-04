# Changelog

## 0.1.0 - 2026-11-04
- Project opgezet als Swift Package met PROJECT.md, ROADMAP.md en TESTEN.md
- Command line-tool `bcf-bridge`: poorten tonen, virtuele poort "BCF Bridge", MIDI-log met uitleg
- Mackie-handshake (device query, host connection, versie en serienummer)
- Fader 1: CC naar Pitch Bend met gesimuleerde touch, feedback-onderdrukking, ontdubbelen en echo-filter
- Learn-commando voor fader 1, instellingen in JSON met backup van de vorige versie
- Automatisch opnieuw verbinden met de BCF2000
- `selftest` die de vertaallogica zonder hardware controleert
