# Fussel

Fussel ist eine minimalistische, verspielte Mac-Aufräum-App (ähnlich CleanMyMac), Beta. Der Besitzer (Dshamil) programmiert nicht selbst, sondern lässt Fussel komplett von Claude bauen ("vibe coding").

## So arbeiten wir

- **Antworte immer auf Deutsch**, in einfachen Worten, ohne Fachjargon. Fachbegriffe kurz erklären.
- Die App-Oberfläche ist **nur Englisch**.
- Nach einer Änderung: bauen, starten, selbst prüfen, dann knapp sagen, was sich geändert hat.
- Kleinste Lösung, die das Problem ganz löst (Ponytail-Skills liegen in `.claude/skills`). Für Design-Fragen den Skill `apple-design` nutzen.
- Commits nur, wenn der Nutzer es möchte oder ein Release ansteht. Commit-Autor: `Dshamil <dshamilmeziane38@gmail.com>`.
- Das Repo ist **öffentlich** (seit 0.9.0 „Public Beta 1“, MIT-Lizenz). Nichts Privates oder Fremdes committen; der Skill `apple-design` (Apple-Texte) bleibt bewusst nur lokal. Die alte Geschichte (mit den Apple-Texten und den Vorab-Versionen 0.1–0.8.5) liegt im privaten Archiv `Dshamil/fussel-archive`.

## Bauen und starten (auf dem Mac)

```
swift build                     # Debug-Build
swift test                      # Tests (Schutzregeln, Versionsvergleich, Appcast, Update-Signatur)
scripts/build.sh 0.8.1          # Universal-Build → dist/Fussel.app (ad-hoc signiert)
scripts/package.sh 0.8.1        # Installer dist/Fussel-Installer.pkg + dist/Fussel.dmg
open dist/Fussel.app            # starten
```

Fussel ist eine Menüleisten-App (keine Dock-Icon, `LSUIElement`). Läuft schon eine Version, vorher beenden: `pkill -x Fussel`.
`Fussel --render-gifs docs/screenshots` erneuert die README-GIFs (tour, styles, fussel). In Release-Notes GIFs immer über eine feste Commit-Adresse einbinden (`raw.githubusercontent.com/Dshamil/fussel/<commit>/docs/screenshots/…`), sonst zeigt GitHub alte Bilder aus dem Zwischenspeicher. `Fussel --render-previews <ordner>` rendert Screenshots aller Stile (ImageRenderer kann keine AppKit-Views wie native Buttons zeichnen; die erscheinen dort als gelbe Platzhalter).

## Release

- Version steht in `VERSION`. Neue Nummer + `release-notes/<version>.md` (Vorlage: letzte Notes, mit Logo oben; erste Zeile `<!-- title: … -->` setzt den Release-Titel) + Push auf `main` → GitHub Actions (`.github/workflows/build.yml`, macos-15) baut, testet, packt, **signiert den Installer** und veröffentlicht ein Release, **als „Latest“ markiert** (keine Prerelease mehr), mit Installer-zip (empfohlener Download: das pkg mit Fussel-Icon, denn Browser verlieren eigene Icons), pkg, pkg.sig, dmg und App-zip. Installer-Bilder: `swift design/installer-background.swift`, Seiten in `installer/resources/*.html`.
- Update-Signatur: Ed25519. Privater Schlüssel nur als GitHub-Secret `FUSSEL_SIGNING_KEY` (nicht lesbar, keine Kopie), öffentlicher in `UpdateSignature.publicKey`. Der Updater installiert nur Installer mit passender `.pkg.sig`. Geht das Secret verloren: neues Paar mit `swift scripts/sign-update.swift`, Nutzer müssen dann einmal von Hand aktualisieren.
- CI legt Screenshots auf den Branch `ci-previews` und misst CPU/RAM (`scripts/perf-probe.sh`).
- Nicht mit Developer ID signiert/notarisiert: Gatekeeper fragt beim Installer einmal nach („Trotzdem öffnen“). Langfristige Lösung: Apple Developer Account. Bewusst auf später verschoben.

## Aufbau (`Sources/Fussel`)

- `FusselApp.swift` – App-Start, Menüleisten-Icon (Links-Klick: Fenster, Rechts-Klick: Menü), Hauptfenster (normales Mac-Fenster, 960×640, verschieb- und vergrößerbar), Tastenkürzel, Login-Item.
- `AppModel.swift` – Zustand: Smart Scan → Ergebnisse → Aufräumen → fertig, Undo, Stimmungen (hot/sleepy/stuffed).
- `Scanner.swift`, `Cleaner.swift` – Suchen und in den Papierkorb legen. **`Cleaner.isSafeToRemove` ist die letzte Schutzlinie** – nur mit Tests ändern.
- `History.swift` – Verlauf + Undo (JSON in Application Support).
- `SystemMonitor.swift` – Speicher, RAM, CPU, Temperatur (SMC), Akku, Netzwerk. Eine einzige Messschleife: 2 s bei offenem Fenster, 30 s im Hintergrund. Werte, die sich ständig ändern, **ohne** `.contentTransition(.numericText())` anzeigen: das zeichnet und verwischt die Ziffern als Bilder und kostete 11 Prozentpunkte CPU und über 100 MB Speicher.
- `ContentView.swift` – Seitenleiste (Fussel-Icon, Overview, Clean: System Junk/Trash, Review: Large Files/Uninstaller/App Updates, Settings, History, Speicher + „Clean Safe Items“) und die Übersicht (Speicher-Balken, Kategorien-Liste, Werte-Zeile). Ernster Stil im Sinne von Purge, mit dezenten Animationen.
- `Mascot.swift` – Fussel: graphitfarbenes Knäuel mit einer Locke, wie im App-Icon (`FusselGeometry`, `FusselBody`), Menüleisten-Symbole (normal, Punkt, fröhlich, wippende Locke beim Scannen). In der App nur als Abzeichen oben in der Seitenleiste; leere und fertige Zustände zeigen Symbole (`StateIcon`).
- `Style.swift`, `Theme.swift` – Farben für Light/Dark und den Glass-Stil (unscharfer Schreibtisch dahinter, Karten aus Glas ab macOS 26), Wahl `AppearanceChoice` (Match Mac/Light/Dark/Glass/Oreo = weiße Seitenleiste + Hauptbereich wie Dark, in den Einstellungen), je Werkzeug eine Akzentfarbe, Knopf-Stile.
- `OverviewExtras.swift` – unten auf der Übersicht: „Where your space goes“ (4 größte Ordner aus Benutzerordner, Library, Programme; misst nur mit Festplattenvollzugriff, im Hintergrund nach Scan/Aufräumen; Klick öffnet den Ordner) und „Recent clean-ups“ (letzte 3 mit Undo).
- `ModuleView.swift` – Listen der Werkzeuge mit Filter (Safe to Clean / Check First), Sortierung, Erklärung je Eintrag.
- `StatsView.swift` (Werte-Zeile + Popovers), `SettingsView.swift`, `UninstallerView.swift`.
- `PermissionsView.swift` – eigener Bildschirm für die Rechte (Festplattenvollzugriff = nötig, Mitteilungen, Start mit dem Mac), zeigt live „Allowed“. Kommt beim ersten Start direkt nach der Tour (auch nach Skip), sonst über „Check Permissions“ in den Einstellungen.
- `Tutorial.swift` – kurze Willkommens-Tour (4 Karten, Skip/Esc), von selbst nur beim allerersten Start nach der Installation (`FirstLaunch.seen`), sonst über „Show Tour“ in den Einstellungen. Die Seitenleiste ist per Ziehen am Trennstrich 200–340 pt breit (Doppelklick: zurück auf 248).
- `Updater.swift` – Selbst-Updater über GitHub Releases, prüft die Ed25519-Signatur (`UpdateSignature`) vor dem Installieren.
- `AppUpdates.swift` – Updates anderer Apps (App Store + Sparkle-Feeds).
- `FluffWatcher.swift` – wöchentliche Erinnerung.

Weitere Ordner: `Resources` (Info.plist, `AppIcon/` = fertig gebautes Glas-Icon), `installer` (pkg-Installer), `scripts`, `release-notes`, `docs` (Logo, Screenshots), `design` (`AppIcon.icon` = Liquid-Glass-Icon für Icon Composer; nach Änderungen `scripts/icon.sh` laufen lassen, das baut `Resources/AppIcon`, docs/logo.png und die Installer-Bilder, braucht Xcode 26). Markenregeln: Fussel nur weiß auf Graphit oder graphit auf hell, nie bunt, immer mit Locke; Farbe nur für die fünf Werkzeuge und die Etiketten; Wortmarke SF Pro Rounded Heavy, `Tests`.

## Offene Punkte

- Kleinere Audit-Punkte: Wochen-Check und Scan teilen sich den Live-Zähler; Icon wird bei jedem Start neu geschrieben; Undo aus altem Verlauf setzt aktuelle Scan-Ergebnisse zurück.
- Auf echtem Mac prüfen: ob die Locke in der Menüleiste bei 18 pt gut lesbar ist.
