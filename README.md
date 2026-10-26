<p align="center">
  <img src="docs/logo.png" width="160" alt="Fussel app icon">
</p>

<h1 align="center">Fussel</h1>

<p align="center">Free up your Mac, calmly. Fussel finds caches, logs and forgotten files, tells you what each one is, and moves what you choose to the Trash.<br><i>Public beta.</i></p>

<p align="center"><img src="docs/screenshots/tour.gif" width="720" alt="Fussel scanning, showing what it found, explaining System Junk and cleaning up"></p>

- **Overview**: used and free space, a bar that shows where it goes, and a row per tool
- **System Junk**: app caches, logs and Xcode build data
- **Trash & Downloads**: empty the Trash and sweep out old downloads
- **Large Files**: big files and things you haven't opened in ages
- **Uninstaller**: remove apps together with their support files, caches and preferences
- **App Updates**: updates for apps from the App Store and the web

Every item comes with a plain-language explanation and a **Safe to Clean** or **Check First** label.
Plus memory, CPU, battery and network at a glance, and a menu bar helper.

<p align="center"><img src="docs/screenshots/styles.gif" width="720" alt="Fussel in Light, Dark and the see-through Glass style"></p>

<p align="center">Light, Dark or Glass, picked in Settings. Glass lets your desktop shine through, softly blurred.</p>

<p align="center"><img src="docs/screenshots/list.png" width="640" alt="System Junk with explanations and safety labels"></p>

<p align="center"><img src="docs/screenshots/fussel.gif" width="96" alt="Fussel swinging his curl"><br>
<i>Fussel lives in your menu bar and swings his curl while he looks around.</i></p>

## Safety first

- Everything is moved to the Trash first, so you can always restore it.
- Only items that are already in the Trash are deleted permanently, and Fussel asks before doing it.
- Fussel never touches system files, Apple apps, or the top-level folders in your home folder.
- Nothing is selected in *Large Files* or *Trash & Downloads* until you choose it.

## Install

1. Download **Fussel-Installer.pkg** from the latest [release](../../releases) and open it.
2. Fussel isn't signed with an Apple Developer ID yet, so macOS blocks the installer at first:
   open **System Settings › Privacy & Security** and click **Open Anyway**.
3. Click through the installer. Fussel lands in Applications and appears in the menu bar.
4. Optional but recommended: give Fussel **Full Disk Access** in
   **System Settings › Privacy & Security › Full Disk Access**.

Prefer drag and drop? Use **Fussel.dmg**, then run
`xattr -dr com.apple.quarantine /Applications/Fussel.app` once before the first launch.

Fussel lives in the menu bar: click the fluff to open or close it, right-click for more.
It starts with your Mac; turn that off in Settings.

Requires macOS 14 Sonoma or later. Runs natively on Apple Silicon and Intel.

## Build it yourself

```sh
scripts/build.sh 0.9.0      # builds dist/Fussel.app
scripts/package.sh 0.9.0    # builds dist/Fussel-Installer.pkg and dist/Fussel.dmg
```

Needs Xcode 15 or later (or the Swift toolchain that comes with it).

Every push to `main` is built by GitHub Actions. To publish a new release, bump the
number in `VERSION` (for example to `0.9.1`) and push: a beta release `v0.9.1` with the
installer, disk image and zip attached is created automatically. If `release-notes/<version>.md`
exists, it becomes the release text (a first line `<!-- title: … -->` sets the release title);
otherwise GitHub generates notes from the commits.

## Project layout

- `Sources/Fussel/`: the SwiftUI app
- `Resources/`: Info.plist and the app icon
- `design/`: icon artwork (light, dark, tinted) as SVG and PNG
- `scripts/`: build and packaging scripts

## License

MIT, see [LICENSE](LICENSE).
