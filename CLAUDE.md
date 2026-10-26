# Fussel

Fussel ist eine minimalistische, verspielte Mac-Aufräum-App (ähnlich CleanMyMac), Beta. Der Besitzer (Dshamil) programmiert nicht selbst, sondern lässt Fussel komplett von Claude bauen ("vibe coding").

## So arbeiten wir

- **Antworte immer auf Deutsch**, in einfachen Worten, ohne Fachjargon. Fachbegriffe kurz erklären.
- Die App-Oberfläche ist **nur Englisch**.
- Nach einer Änderung: bauen, starten, selbst prüfen, dann knapp sagen, was sich geändert hat.
- Kleinste Lösung, die das Problem ganz löst (Ponytail-Skills liegen in `.claude/skills`). Für Design-Fragen den Skill `apple-design` nutzen.
- Commits nur, wenn der Nutzer es möchte oder ein Release ansteht. Commit-Autor: `Dshamil <dshamilmeziane38@gmail.com>`.
- Das Repo ist **privat**. Öffentlich machen entscheidet nur der Nutzer.

## Bauen und starten (auf dem Mac)

```
swift build                     # Debug-Build
swift test                      # Tests (Schutzregeln, Versionsvergleich, Appcast)
scripts/build.sh 0.8.1          # Universal-Build → dist/Fussel.app (ad-hoc signiert)
scripts/package.sh 0.8.1        # Installer dist/Fussel-Installer.pkg + dist/Fussel.dmg
open dist/Fussel.app            # starten
```

Fussel ist eine Menüleisten-App (keine Dock-Icon, `LSUIElement`). Läuft schon eine Version, vorher beenden: `pkill -x Fussel`.
`Fussel --render-previews <ordner>` rendert Screenshots aller Stile (ImageRenderer kann keine AppKit-Views wie native Buttons zeichnen; die erscheinen dort als gelbe Platzhalter).

## Release

- Version steht in `VERSION`. Neue Nummer + `release-notes/<version>.md` (Vorlage: letzte Notes, mit Logo oben) + Push auf `main` → GitHub Actions (`.github/workflows/build.yml`, macos-15) baut, testet, packt und veröffentlicht eine **Prerelease** mit pkg, dmg und zip.
- CI legt Screenshots auf den Branch `ci-previews` und misst CPU/RAM (`scripts/perf-probe.sh`).
- Nicht mit Developer ID signiert/notarisiert: Gatekeeper fragt beim Installer einmal nach („Trotzdem öffnen“). Langfristige Lösung: Apple Developer Account. Bewusst auf später verschoben.

## Aufbau (`Sources/Fussel`)

- `FusselApp.swift` – App-Start, Menüleisten-Icon (Links-Klick: Fenster, Rechts-Klick: Menü), Hauptfenster (fest oben rechts, gleitet herein, nicht verschiebbar), Tastenkürzel, Login-Item.
- `AppModel.swift` – Zustand: Smart Scan → Ergebnisse → Aufräumen → fertig, Undo, Stimmungen (hot/sleepy/stuffed).
- `Scanner.swift`, `Cleaner.swift` – Suchen und in den Papierkorb legen. **`Cleaner.isSafeToRemove` ist die letzte Schutzlinie** – nur mit Tests ändern.
- `History.swift` – Verlauf + Undo (JSON in Application Support).
- `SystemMonitor.swift` – Speicher, RAM, CPU, Temperatur (SMC), Akku, Netzwerk. Eine einzige Messschleife: 2 s bei offenem Fenster, 30 s im Hintergrund.
- `ContentView.swift` – der eine Hauptbildschirm (Hero-Banner, Statistik-Kacheln, 6 Karten, Fußzeile mit Verlauf, Stil-Wahl, Zahnrad für Einstellungen).
- `Mascot.swift` – Fussel als Figur (Canvas, 100×100 Design-Raum), Augen folgen dem Zeiger (`Gaze`), Menüleisten-Icons.
- `Particles.swift` – Fusseln, Scan-Strudel, Konfetti.
- `FusselWorld.swift` – Fussels kleine Welt im Banner: Dielenboden, Lichtstrahl, verlorene Sachen, Fusselhaufen je nach Scan.
- `Style.swift`, `Theme.swift` – Stile White/Dark/Coral/Graphite, Farben, `AnimationBudget` (60/30 fps; pausiert bei verstecktem Fenster).
- `Tutorial.swift`, `StatsView.swift`, `SettingsView.swift`, `ModuleView.swift`, `UninstallerView.swift`.
- `Updater.swift` – Selbst-Updater über GitHub Releases (geht erst, wenn das Repo öffentlich ist).
- `AppUpdates.swift` – Updates anderer Apps (App Store + Sparkle-Feeds).
- `Closet.swift` – Kostüme, App-Icon-Wechsel, 13 Abzeichen.
- `FluffWatcher.swift` – wöchentliche Erinnerung.

Weitere Ordner: `Resources` (Info.plist, Icons), `installer` (pkg-Installer), `scripts`, `release-notes`, `docs` (Logo, Screenshots), `design`, `Tests`.

## Offene Punkte

- **Update-Signatur (wichtig, bevor das Repo öffentlich wird):** Der Selbst-Updater öffnet den Installer ohne Prüfung. Plan: Ed25519-Signatur mit CryptoKit, privater Schlüssel als GitHub-Secret, öffentlicher Schlüssel in der App.
- Kleinere Audit-Punkte: Wochen-Check und Scan teilen sich den Live-Zähler; Icon wird bei jedem Start neu geschrieben; Undo aus altem Verlauf setzt aktuelle Scan-Ergebnisse zurück.
- Auf echtem Mac prüfen: Flüssigkeit der Animationen, Augen-Tracking, ob der Icon-Wechsel die Signatur stört.
