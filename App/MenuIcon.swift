import AppKit

/// Menu-bar glyphs as template images, so macOS tints them for light/dark menu bars.
enum MenuIcon {
    private static var cache: [IconArt.Glyph: NSImage] = [:]

    static func image(_ glyph: IconArt.Glyph) -> NSImage {
        if let img = cache[glyph] { return img }
        let side: CGFloat = 18
        let img = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: side / 112, y: side / 112)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            IconArt.drawGlyph(glyph, in: ctx)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Afterimage"
        cache[glyph] = img
        return img
    }
}
