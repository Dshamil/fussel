# Fussel – Abhakliste vor einem Release

Einmal von Hand durchgehen, bevor eine Version als fertig gilt. Dauert etwa 20 Minuten.
Was nicht klappt oder komisch aussieht: in Fussel **Settings › Feedback › Send Feedback** und kurz beschreiben.

## 1. Update (zuerst, solange die alte Version noch drauf ist)

- [ ] In der alten Version **Settings › Updates › Check Now** klicken. Erscheint „Fussel X is available“ mit **Update Now**?
- [ ] **Update Now** klicken. Fragt macOS genau einmal nach dem Passwort?
- [ ] Startet Fussel danach von selbst neu, ohne Installer-Fenster? Steht unter Settings die neue Versionsnummer?
- [ ] Gegenprobe: bei der Passwortabfrage auf **Abbrechen**. Kommt „Update Now“ mit einem kurzen Hinweis zurück?

## 2. Erster Start (frischer Mac oder nach `defaults delete app.fussel.Fussel tutorialSeen`)

- [ ] Öffnet sich das Fenster von selbst mit der **Willkommens-Tour**?
- [ ] Alle 4 Karten durchklicken: Texte lesbar, nichts abgeschnitten, **Back** und **Next** funktionieren
- [ ] Danach kommt der **Rechte-Bildschirm**. Auch wenn man die Tour mit **Skip** oder Esc überspringt?
- [ ] **Open Settings** bei Full Disk Access öffnet die richtige Stelle. Nach dem Erlauben und Zurückkommen steht dort **Allowed**
- [ ] **Allow** bei Notifications zeigt die Mac-Abfrage. Danach **Allowed**
- [ ] Beim zweiten Start kommt die Tour **nicht** wieder

## 3. Übersicht

- [ ] Der Scan startet von selbst, die drei Kreisel drehen sich, danach stehen Zahlen da
- [ ] „Where your space goes“ zeigt nach einer halben Minute die größten Ordner. Ein Klick öffnet den Ordner im Finder
- [ ] **Clean …** oben rechts fragt nach und räumt auf. Danach steht unter „Overview“ „Cleaned …“, in den Zeilen „… freed“, und der Knopf ist ausgegraut
- [ ] „Recent clean-ups“: **Undo** holt die Dateien wirklich zurück (im Finder nachsehen)
- [ ] Die Werte-Zeile unten (RAM, Akku, CPU, Netzwerk): Jeder Eintrag öffnet beim Klick ein kleines Fenster

## 4. Werkzeuge

- [ ] **System Junk** und **Trash & Downloads**: Liste, Filter (All / Safe to Remove / Review First), Sortierung, Lupe öffnet im Finder
- [ ] **Large Files**: nichts ist vorausgewählt
- [ ] **Uninstaller**: App anklicken, mit ↑ und ↓ durch die Liste gehen, eine unwichtige App mit Resten entfernen
- [ ] **App Updates**: Check for Updates findet etwas oder sagt „Everything's fresh“

## 5. Aussehen

- [ ] **Settings › Appearance**: Match Mac, Light, Dark, Glass und Oreo umschalten. Alles lesbar, nichts grau verirrt
- [ ] Seitenleiste am Trennstrich breiter und schmaler ziehen. Doppelklick setzt sie zurück
- [ ] Menüleiste: Fussel ist erkennbar. Beim Scan wippt die Locke. Rechtsklick zeigt das Menü mit **Send Feedback…**

## 6. Hintergrund

- [ ] Fenster schließen. Fussel bleibt in der Menüleiste und braucht im Aktivitätsmonitor fast keine CPU
- [ ] **Settings › Weekly reminder › Show Example** zeigt die Mitteilung

## 7. Auf anderen Macs (wenn möglich)

- [ ] macOS 14 Sonoma oder 15 Sequoia: startet, Glass sieht wie Milchglas aus, Icon passt
- [ ] Intel-Mac: startet, Scan läuft durch
- [ ] Ganz neuer Benutzer ohne Festplattenvollzugriff: Fussel fragt nicht bei jedem Ordner einzeln nach
