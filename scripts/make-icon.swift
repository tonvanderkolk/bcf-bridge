// Tekent het app-icoon (1024x1024 PNG): drie motorfaders op een donkere achtergrond.
// Gebruik: swift scripts/make-icon.swift uitvoer.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Achtergrond: afgeronde tegel in de macOS-maat (824 binnen 1024)
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.31, alpha: 1),
           ending: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1))!
    .draw(in: tilePath, angle: -90)

// Drie fadersleuven met knoppen op verschillende hoogtes
let accent = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.10, alpha: 1)
let xs: [CGFloat] = [332, 512, 692]
let knobY: [CGFloat] = [600, 400, 680]
for (i, x) in xs.enumerated() {
    let slot = NSRect(x: x - 14, y: 230, width: 28, height: 564)
    NSColor.black.withAlphaComponent(0.65).setFill()
    NSBezierPath(roundedRect: slot, xRadius: 14, yRadius: 14).fill()

    // Oplichtend deel onder de knop
    let lit = NSRect(x: x - 6, y: 238, width: 12, height: knobY[i] - 238)
    accent.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: lit, xRadius: 6, yRadius: 6).fill()

    // Faderknop
    let knob = NSRect(x: x - 62, y: knobY[i] - 40, width: 124, height: 80)
    let knobPath = NSBezierPath(roundedRect: knob, xRadius: 16, yRadius: 16)
    NSGraphicsContext.saveGraphicsState()
    let ks = NSShadow()
    ks.shadowColor = NSColor.black.withAlphaComponent(0.5)
    ks.shadowBlurRadius = 12
    ks.shadowOffset = NSSize(width: 0, height: -6)
    ks.set()
    NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
    knobPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedWhite: 0.97, alpha: 1),
               ending: NSColor(calibratedWhite: 0.72, alpha: 1))!.draw(in: knobPath, angle: -90)
    NSColor(calibratedWhite: 0.25, alpha: 1).setFill()
    NSRect(x: x - 50, y: knobY[i] - 3, width: 100, height: 6).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Geschreven: \(out)")
