// Renders the app icon: an ear between left (blue) and right (red) sound waves,
// the audiogram colours for each ear.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let size = 1024
let out = "HearingCheck/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let s = CGFloat(size)

// Background: deep blue to teal, full bleed (iOS applies the mask).
let colors = [
    NSColor(srgbRed: 0.07, green: 0.11, blue: 0.27, alpha: 1).cgColor,
    NSColor(srgbRed: 0.05, green: 0.38, blue: 0.47, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

// Sound waves: 3 arcs on each side.
let center = CGPoint(x: s / 2, y: s / 2)
let left = NSColor(srgbRed: 0.45, green: 0.68, blue: 1.0, alpha: 1)
let right = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.40, alpha: 1)
ctx.setLineCap(.round)
for (i, radius) in [270.0, 345.0, 420.0].enumerated() {
    let alpha = 1.0 - Double(i) * 0.25
    ctx.setLineWidth(34)
    let spread = CGFloat.pi / 5
    ctx.setStrokeColor(right.withAlphaComponent(alpha).cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: -spread, endAngle: spread, clockwise: false)
    ctx.strokePath()
    ctx.setStrokeColor(left.withAlphaComponent(alpha).cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: .pi - spread, endAngle: .pi + spread, clockwise: false)
    ctx.strokePath()
}

// Ear glyph in the centre.
let config = NSImage.SymbolConfiguration(pointSize: 360, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let ear = NSImage(systemSymbolName: "ear", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let earSize = ear.size
ear.draw(in: NSRect(x: center.x - earSize.width / 2, y: center.y - earSize.height / 2,
                    width: earSize.width, height: earSize.height))

NSGraphicsContext.restoreGraphicsState()
try! FileManager.default.createDirectory(
    atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

// App icons must not have an alpha channel: flatten through JPEG (no alpha) and back to PNG.
let flatten = Process()
flatten.executableURL = URL(fileURLWithPath: "/bin/sh")
flatten.arguments = ["-c", "sips -s format jpeg -s formatOptions best '\(out)' --out /tmp/hc-icon.jpg >/dev/null && sips -s format png /tmp/hc-icon.jpg --out '\(out)' >/dev/null && rm /tmp/hc-icon.jpg"]
try! flatten.run()
flatten.waitUntilExit()
