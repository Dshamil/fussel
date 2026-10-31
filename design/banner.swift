import SwiftUI
import AppKit

// Banner for posts and link previews: logo + text on the left, the app on the right.
// The app shot comes from: Fussel --render-previews <dir> -AppleLocale en_US -AppleLanguages "(en)"
// usage: swift design/banner.swift docs/logo.png <dir>/light-ready.png docs/social.png light wide
//        (without "wide": 16:9 at 2400×1350 for image posts)
let args = CommandLine.arguments
let logo = NSImage(contentsOfFile: args[1])!
let shot = NSImage(contentsOfFile: args[2])!
let out = args[3]
let dark = args.count > 4 && args[4] == "dark"
let wide = args.count > 5 && args[5] == "wide" // 2:1 at 1280×640 for link previews (GitHub wants < 1 MB)
let H: CGFloat = wide ? 800 : 900

let bg = dark ? Color(red: 0.09, green: 0.09, blue: 0.10) : Color(red: 0.955, green: 0.955, blue: 0.965)
let ink = dark ? Color.white : Color(red: 0.15, green: 0.15, blue: 0.17)
let soft = dark ? Color.white.opacity(0.6) : Color(red: 0.42, green: 0.42, blue: 0.45)
let chipFill = dark ? Color.white.opacity(0.08) : Color.white
let chipStroke = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)

struct Chip: View {
    let symbol: String, text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            Text(text).font(.system(size: 22, weight: .semibold))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(Capsule().fill(chipFill))
        .overlay(Capsule().strokeBorder(chipStroke, lineWidth: 1))
    }
}

struct Banner: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            bg
            Image(nsImage: shot).resizable().interpolation(.high)
                .frame(width: 880, height: 587)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(dark ? 0.5 : 0.16), radius: 40, y: 20)
                .offset(x: 676, y: (H - 587) / 2 + 10)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 22) {
                    Image(nsImage: logo).resizable().interpolation(.high).frame(width: 128, height: 128)
                        .padding(.leading, -12.5) // the icon image has a 100/1024 clear margin
                    Text("Fussel").font(.system(size: 112, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink).tracking(-2)
                }
                Text("A free, open-source\nMac cleaner.")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(ink).lineSpacing(2)
                    .padding(.top, 40)
                Text("Everything goes to the Trash.\nEvery clean-up can be undone.")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(soft).lineSpacing(6)
                    .padding(.top, 22)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Chip(symbol: "chevron.left.forwardslash.chevron.right", text: "MIT licensed")
                        Chip(symbol: "checkmark.seal", text: "Signed updates")
                    }
                    Chip(symbol: "macbook", text: "macOS 14 and later")
                }
                .padding(.top, 36)
                Spacer()
                Text("github.com/Dshamil/fussel")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(soft)
            }
            .padding(.leading, 96).padding(.top, wide ? 64 : 92).padding(.bottom, wide ? 56 : 72)
            .frame(width: 700, height: H, alignment: .topLeading)
        }
        .frame(width: 1600, height: H)
        .clipped()
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

MainActor.assumeIsolated {
    let r = ImageRenderer(content: Banner())
    r.scale = wide ? 0.8 : 1.5
    let rep = NSBitmapImageRep(cgImage: r.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
