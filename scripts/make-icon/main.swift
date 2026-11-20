// Renders the app icon PNGs into App/Assets.xcassets/AppIcon.appiconset.
// Run from the repo root:  swiftc -o /tmp/make-icon scripts/make-icon/main.swift Shared/IconArt.swift && /tmp/make-icon
import AppKit
import CoreGraphics

let setDir = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)

func render(px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let size = CGFloat(px)
    // macOS icon grid: the rounded square is 824/1024 of the canvas, centred.
    let s = (size * 824 / 1024) / 104
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)              // y down, matching the design space
    ctx.translateBy(x: size * 100 / 1024 - 4 * s, y: size * 100 / 1024 - 4 * s)
    ctx.scaleBy(x: s, y: s)
    IconArt.drawAppIcon(in: ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try render(px: pt * scale).write(to: setDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: setDir.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!
    .write(to: setDir.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon sizes to \(setDir.path)")
