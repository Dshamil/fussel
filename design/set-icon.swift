import AppKit

// Gives files a custom Finder icon, e.g. the installer package the Fussel icon.
// Usage: swift design/set-icon.swift <icon.icns> <file>...
let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!
for path in CommandLine.arguments.dropFirst(2) {
    print(NSWorkspace.shared.setIcon(icon, forFile: path) ? "Icon set on \(path)" : "Could not set icon on \(path)")
}
