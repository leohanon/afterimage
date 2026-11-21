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

extension MenuIcon {
    static let liveColor = NSColor.systemGreen
    static let loopColor = NSColor(red: 0.847, green: 0.353, blue: 0.188, alpha: 1)

    /// The glyph in white on a filled rounded shape, like the system's own
    /// "in use" indicators, so what the call is seeing is obvious at a glance.
    static func highlighted(_ glyph: IconArt.Glyph, color: NSColor) -> NSImage {
        // Same height and shape as the system's screen-sharing indicator.
        let size = NSSize(width: 36, height: 24)
        let glyphSide: CGFloat = 16
        let img = NSImage(size: size, flipped: true) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).fill()
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: (size.width - glyphSide) / 2, y: (size.height - glyphSide) / 2)
            ctx.scaleBy(x: glyphSide / 112, y: glyphSide / 112)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor.white.cgColor)
            IconArt.drawGlyph(glyph, in: ctx)
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = "Afterimage: in use"
        return img
    }
}
