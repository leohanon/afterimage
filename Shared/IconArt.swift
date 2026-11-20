import CoreGraphics
import Foundation

/// The Afterimage mark, drawn in a 112×112 design space (y pointing down).
/// Used for both the app icon (scripts/make-icon.swift) and the menu-bar glyphs.
enum IconArt {
    static let center = CGPoint(x: 56, y: 56)

    /// Looping arrow: a 30-radius arc with a gap at the top, ending in an arrowhead.
    static func addArrow(to ctx: CGContext, scale: CGFloat = 1, lineWidth: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -center.x, y: -center.y)

        let r: CGFloat = 30
        func point(_ deg: CGFloat) -> CGPoint {
            let t = deg * .pi / 180
            return CGPoint(x: center.x + r * cos(t), y: center.y + r * sin(t))
        }
        let arc = CGMutablePath()
        arc.move(to: point(-60))
        var d: CGFloat = -60
        while d < 236 { d = min(d + 2, 236); arc.addLine(to: point(d)) }
        ctx.addPath(arc)
        ctx.setLineWidth(lineWidth)  // in the scaled space, like SVG
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        // Arrowhead: tip on the circle at 255°, base centred at 232°.
        let tip = point(255)
        let baseC = point(232)
        let a: CGFloat = 232 * .pi / 180
        let radial = CGPoint(x: cos(a), y: sin(a))
        let half: CGFloat = 9
        let head = CGMutablePath()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: baseC.x - half * radial.x, y: baseC.y - half * radial.y))
        head.addLine(to: CGPoint(x: baseC.x + half * radial.x, y: baseC.y + half * radial.y))
        head.closeSubpath()
        ctx.addPath(head)
        ctx.fillPath()
        ctx.restoreGState()
    }

    static func circle(_ r: CGFloat) -> CGRect {
        CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    }

    /// Full-colour app icon artwork filling the 112×112 space.
    static func drawAppIcon(in ctx: CGContext) {
        let coral = CGColor(srgbRed: 0xD8 / 255, green: 0x5A / 255, blue: 0x30 / 255, alpha: 1)
        let cream = CGColor(srgbRed: 0xFA / 255, green: 0xEC / 255, blue: 0xE7 / 255, alpha: 1)
        let dark = CGColor(srgbRed: 0x4A / 255, green: 0x1B / 255, blue: 0x0C / 255, alpha: 1)
        let glint = CGColor(srgbRed: 0xF5 / 255, green: 0xC4 / 255, blue: 0xB3 / 255, alpha: 1)

        ctx.addPath(CGPath(roundedRect: CGRect(x: 4, y: 4, width: 104, height: 104), cornerWidth: 24, cornerHeight: 24, transform: nil))
        ctx.setFillColor(coral)
        ctx.fillPath()

        ctx.setStrokeColor(cream)
        ctx.setFillColor(cream)
        addArrow(to: ctx, lineWidth: 7)

        ctx.setFillColor(cream); ctx.fillEllipse(in: circle(16))
        ctx.setFillColor(dark); ctx.fillEllipse(in: circle(10.5))
        ctx.setFillColor(glint)
        ctx.fillEllipse(in: CGRect(x: 52.5 - 3, y: 52.5 - 3, width: 6, height: 6))
    }

    enum Glyph { case liveIdle, liveActive, loopIdle, loopActive }

    /// Monochrome menu-bar glyph in the 112×112 space, using the current fill/stroke colour.
    static func drawGlyph(_ g: Glyph, in ctx: CGContext) {
        switch g {
        // Live = lens in a closed ring; Loop = lens in the looping arrow.
        // Same outer radius (37.5) so switching modes only changes ring vs arrow.
        case .liveIdle:
            ctx.setLineWidth(11.25); ctx.strokeEllipse(in: circle(37.5))
            ctx.setLineWidth(7); ctx.strokeEllipse(in: circle(13))
        case .liveActive:
            ctx.setLineWidth(8.75); ctx.strokeEllipse(in: circle(37.5))
            ctx.fillEllipse(in: circle(16))
        case .loopIdle:
            addArrow(to: ctx, scale: 1.25, lineWidth: 9)
            ctx.setLineWidth(7); ctx.strokeEllipse(in: circle(13))
        case .loopActive:
            addArrow(to: ctx, scale: 1.25, lineWidth: 7)
            ctx.fillEllipse(in: circle(16))
        }
    }
}
