// Draws the disk-image window background: a soft gradient, an arrow from the
// app to the Applications folder, and a one-line hint. Usage: background <out.png> <scale>
import AppKit
let out = CommandLine.arguments[1]
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let W: CGFloat = 640, H: CGFloat = 400
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(starting: NSColor(red: 0.984, green: 0.933, blue: 0.910, alpha: 1),
           ending: NSColor(red: 0.965, green: 0.835, blue: 0.776, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -70)
let accent = NSColor(red: 0.847, green: 0.353, blue: 0.188, alpha: 1)
// Arrow between icon centres (app at x=170, Applications at x=470, y=190 from top).
let y = H - 190
let path = NSBezierPath()
path.move(to: NSPoint(x: 250, y: y)); path.line(to: NSPoint(x: 382, y: y))
path.lineWidth = 6; path.lineCapStyle = .round
accent.setStroke(); path.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 392, y: y)); head.line(to: NSPoint(x: 370, y: y + 15)); head.line(to: NSPoint(x: 370, y: y - 15)); head.close()
accent.setFill(); head.fill()
let style = NSMutableParagraphStyle(); style.alignment = .center
let text = NSAttributedString(string: "Drag Afterimage to Applications to install", attributes: [
    .font: NSFont.systemFont(ofSize: 16, weight: .medium),
    .foregroundColor: NSColor(red: 0.43, green: 0.29, blue: 0.24, alpha: 1), .paragraphStyle: style])
text.draw(in: NSRect(x: 0, y: 70, width: W, height: 24))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
