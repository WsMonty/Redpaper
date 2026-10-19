// Renders icon/AppIcon.icns (and icon/preview.png). Run: swift icon/make_icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A mountain with a rounded peak.
func mountain(left: CGFloat, peak: CGPoint, right: CGFloat, base: CGFloat, round: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let l = CGPoint(x: left, y: base), r = CGPoint(x: right, y: base)
    func toward(_ a: CGPoint, _ b: CGPoint, _ d: CGFloat) -> CGPoint {
        let len = hypot(b.x - a.x, b.y - a.y)
        return CGPoint(x: a.x + (b.x - a.x) * d / len, y: a.y + (b.y - a.y) * d / len)
    }
    p.move(to: l)
    p.addLine(to: toward(peak, l, round))
    p.addQuadCurve(to: toward(peak, r, round), control: peak)
    p.addLine(to: r)
    p.closeSubpath()
    return p
}

func sparkle(_ ctx: CGContext, at c: CGPoint, size s: CGFloat) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + s))
    p.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - s), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x - s, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + s), control: c)
    ctx.addPath(p)
    ctx.fillPath()
}

/// Draws on a 1024×1024 canvas (origin bottom-left).
func draw(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x2A2040, 0.3))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Sky
    let sky = CGGradient(colorsSpace: nil, colors: [color(0xB9BEFF), color(0xFFD6C8)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 380), options: [.drawsAfterEndLocation])

    // Sun with a soft glow
    ctx.setFillColor(color(0xFFFFFF, 0.35))
    ctx.fillEllipse(in: CGRect(x: 690 - 150, y: 700 - 150, width: 300, height: 300))
    ctx.setFillColor(color(0xFFC94D))
    ctx.fillEllipse(in: CGRect(x: 690 - 105, y: 700 - 105, width: 210, height: 210))

    // Cloud
    ctx.setFillColor(color(0xFFFFFF))
    for (x, y, r) in [(250.0, 742.0, 44.0), (312.0, 768.0, 62.0), (378.0, 746.0, 46.0)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    ctx.addPath(CGPath(roundedRect: CGRect(x: 206, y: 698, width: 218, height: 64), cornerWidth: 32, cornerHeight: 32, transform: nil))
    ctx.fillPath()

    // Sparkles
    ctx.setFillColor(color(0xFFFFFF, 0.95))
    sparkle(ctx, at: CGPoint(x: 520, y: 840), size: 26)
    sparkle(ctx, at: CGPoint(x: 850, y: 860), size: 16)
    sparkle(ctx, at: CGPoint(x: 180, y: 600), size: 14)

    // Back mountain with a scalloped snow cap
    let back = mountain(left: 400, peak: CGPoint(x: 735, y: 590), right: 1150, base: 60, round: 70)
    ctx.addPath(back)
    ctx.setFillColor(color(0x8C93E6))
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(back)
    ctx.clip()
    let cap = CGMutablePath()
    cap.move(to: CGPoint(x: 560, y: 488))
    for i in 0..<5 {
        let x = 560 + CGFloat(i) * 70
        cap.addQuadCurve(to: CGPoint(x: x + 70, y: 488), control: CGPoint(x: x + 35, y: 448))
    }
    cap.addLine(to: CGPoint(x: 910, y: 700))
    cap.addLine(to: CGPoint(x: 560, y: 700))
    cap.closeSubpath()
    ctx.addPath(cap)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Front mountain (the cute one)
    let front = mountain(left: -80, peak: CGPoint(x: 400, y: 640), right: 880, base: 60, round: 120)
    ctx.saveGState()
    ctx.addPath(front)
    ctx.clip()
    let green = CGGradient(colorsSpace: nil, colors: [color(0x7EDDB4), color(0x52C095)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(green, start: CGPoint(x: 400, y: 640), end: CGPoint(x: 400, y: 150), options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Face
    let ink = color(0x3B3152)
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: 338 - 15, y: 420 - 21, width: 30, height: 42))
    ctx.fillEllipse(in: CGRect(x: 462 - 15, y: 420 - 21, width: 30, height: 42))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: 338 - 3, y: 428, width: 11, height: 11))
    ctx.fillEllipse(in: CGRect(x: 462 - 3, y: 428, width: 11, height: 11))
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(13)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: 400, y: 392), radius: 30, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
    ctx.strokePath()
    ctx.setFillColor(color(0xFF9EB4))
    ctx.fillEllipse(in: CGRect(x: 290 - 30, y: 378 - 15, width: 60, height: 30))
    ctx.fillEllipse(in: CGRect(x: 510 - 30, y: 378 - 15, width: 60, height: 30))

    // Foreground hill
    ctx.setFillColor(color(0x3FAE84))
    ctx.fillEllipse(in: CGRect(x: 520, y: -150, width: 760, height: 380))

    ctx.restoreGState()
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(_ px: Int, to url: URL) throws {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

for pt in [16, 32, 128, 256, 512] {
    try png(pt, to: iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try png(pt * 2, to: iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
try png(1024, to: dir.appendingPathComponent("preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote icon/AppIcon.icns" : "iconutil failed")
