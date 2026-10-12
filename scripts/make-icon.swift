// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
            green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

/// Almond eye outline: two circular arcs meeting at the corners.
func eyePath(center: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
    let half = width / 2
    // Radius of a circle through both corners whose arc bulges by `height / 2`.
    let bulge = height / 2
    let radius = (half * half + bulge * bulge) / (2 * bulge)
    let angle = asin(half / radius)
    let path = CGMutablePath()
    path.addArc(center: CGPoint(x: center.x, y: center.y - (radius - bulge)), radius: radius,
                startAngle: .pi / 2 + angle, endAngle: .pi / 2 - angle, clockwise: true)
    path.addArc(center: CGPoint(x: center.x, y: center.y + (radius - bulge)), radius: radius,
                startAngle: -.pi / 2 + angle, endAngle: -.pi / 2 - angle, clockwise: true)
    path.closeSubpath()
    return path
}

func drawIcon(in ctx: CGContext) {
    let center = CGPoint(x: canvas / 2, y: canvas / 2)

    // Rounded-square tile, inset like other macOS app icons.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.3))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x2F6BE0))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(0x4FC3F7), color(0x3A7BE8), color(0x3B3FC4)]),
                           start: CGPoint(x: tile.midX, y: tile.maxY),
                           end: CGPoint(x: tile.midX, y: tile.minY), options: [])
    ctx.restoreGState()

    // White of the eye.
    let eye = eyePath(center: center, width: 640, height: 380)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x101040, 0.35))
    ctx.addPath(eye)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(eye)
    ctx.clip()

    // Iris.
    let irisRadius: CGFloat = 150
    let iris = CGRect(x: center.x - irisRadius, y: center.y - irisRadius,
                      width: irisRadius * 2, height: irisRadius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: iris)
    ctx.clip()
    ctx.drawRadialGradient(gradient([color(0x2C3E8F), color(0x1B2560)]),
                           startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: irisRadius, options: [])
    ctx.restoreGState()

    // Fatigue ring around the pupil, echoing the ring in the app.
    let ringRadius: CGFloat = 104
    ctx.setLineWidth(30)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
    ctx.saveGState()
    ctx.addArc(center: center, radius: ringRadius, startAngle: .pi / 2, endAngle: .pi / 2 - 1.45 * .pi,
               clockwise: true)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(0x7CF29A), color(0x34C759)]),
                           start: CGPoint(x: center.x, y: center.y + ringRadius),
                           end: CGPoint(x: center.x, y: center.y - ringRadius),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Pupil and highlight.
    let pupilRadius: CGFloat = 62
    ctx.setFillColor(color(0x0B0F2A))
    ctx.fillEllipse(in: CGRect(x: center.x - pupilRadius, y: center.y - pupilRadius,
                               width: pupilRadius * 2, height: pupilRadius * 2))
    ctx.setFillColor(color(0xFFFFFF, 0.9))
    ctx.fillEllipse(in: CGRect(x: center.x + 8, y: center.y + 16, width: 34, height: 34))
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try png(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
