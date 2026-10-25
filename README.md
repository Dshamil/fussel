# Fussel

A small, friendly Mac cleaner. Fussel finds the fluff on your Mac and moves it to the Trash.

- **System Junk**: app caches, logs and Xcode build data
- **Large & Old Files**: big files and things you haven't opened in ages
- **Uninstaller**: remove apps together with their support files, caches and preferences
- **Trash & Downloads**: empty the Trash and sweep out old downloads

Fussel lives in its own window and in the menu bar, where a quick scan cleans caches and logs in one click.

## Safety first

- Everything is moved to the Trash first, so you can always restore it.
- Only items that are already in the Trash are deleted permanently, and Fussel asks before doing it.
- Fussel never touches system files, Apple apps, or the top-level folders in your home folder.
- Nothing is selected in *Large & Old Files* or *Trash & Downloads* until you choose it.

## Install

1. Download `Fussel.zip` from the latest [release](../../releases) and unzip it.
2. Move `Fussel.app` into your Applications folder.
3. Fussel isn't signed with an Apple Developer ID, so macOS warns on first launch.
   Right-click the app, choose **Open**, then confirm with **Open**.
   (Or go to **System Settings → Privacy & Security** and click **Open Anyway**.)
4. Optional but recommended: give Fussel **Full Disk Access** in
   **System Settings → Privacy & Security → Full Disk Access**, so it can see the Trash
   and every hidden cache.

Requires macOS 14 Sonoma or later. Runs natively on Apple Silicon and Intel.

## Build it yourself

```sh
scripts/build.sh 0.1.0
open dist/Fussel.app
```

Needs Xcode 15 or later (or the Swift toolchain that comes with it).

Every push to `main` is built by GitHub Actions. To publish a new release, bump the
number in `VERSION` (for example to `0.2.0`) and push: a release `v0.2.0` with
`Fussel.zip` attached is created automatically.

## Project layout

- `Sources/Fussel/`: the SwiftUI app
- `Resources/`: Info.plist and the app icon
- `design/`: icon artwork (light, dark, tinted) as SVG and PNG
- `scripts/`: build and packaging scripts
