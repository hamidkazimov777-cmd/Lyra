import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    // 1. macOS Squircle Shape
    let squircleRect = CGRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let cornerRadius = squircleRect.width * 0.224
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Shadow behind squircle
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.03), blur: s * 0.06, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.05, green: 0.06, blue: 0.14, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for inner drawing
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // 2. Cosmic Background Gradient
    let bgColors = [
        CGColor(red: 0.05, green: 0.06, blue: 0.16, alpha: 1.0), // Top: Deep midnight
        CGColor(red: 0.08, green: 0.09, blue: 0.24, alpha: 1.0), // Mid-upper
        CGColor(red: 0.06, green: 0.12, blue: 0.28, alpha: 1.0), // Mid-lower
        CGColor(red: 0.03, green: 0.05, blue: 0.14, alpha: 1.0)  // Bottom
    ]
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0.0, 0.35, 0.75, 1.0])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // 3. Radial Nebula Glow
    let glowColors = [
        CGColor(red: 0.30, green: 0.65, blue: 1.0, alpha: 0.28),
        CGColor(red: 0.45, green: 0.35, blue: 0.95, alpha: 0.15),
        CGColor(red: 0.10, green: 0.15, blue: 0.40, alpha: 0.0)
    ]
    let glowGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors as CFArray, locations: [0.0, 0.5, 1.0])!
    ctx.drawRadialGradient(glowGrad,
                           startCenter: CGPoint(x: s * 0.55, y: s * 0.55),
                           startRadius: 0,
                           endCenter: CGPoint(x: s * 0.55, y: s * 0.55),
                           endRadius: s * 0.45,
                           options: [])

    // 4. Subtle stardust field (micro stars)
    if size >= 64 {
        let microStars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.22, 0.78, 1.2, 0.6),
            (0.35, 0.85, 1.0, 0.4),
            (0.78, 0.82, 1.4, 0.7),
            (0.85, 0.68, 1.0, 0.5),
            (0.18, 0.42, 1.2, 0.5),
            (0.25, 0.25, 1.0, 0.4),
            (0.75, 0.28, 1.5, 0.6),
            (0.82, 0.40, 1.1, 0.5),
            (0.50, 0.18, 1.3, 0.5)
        ]
        for ms in microStars {
            ctx.setFillColor(CGColor(red: 0.8, green: 0.9, blue: 1.0, alpha: ms.3))
            let r = ms.2 * (s / 512.0)
            ctx.fillEllipse(in: CGRect(x: ms.0 * s - r, y: ms.1 * s - r, width: r * 2, height: r * 2))
        }
    }

    // 5. Constellation Mapping
    let padX = s * 0.22
    let padY = s * 0.24
    let wUsable = s - 2 * padX
    let hUsable = s - 2 * padY

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let nx = (x - 29.5) / 97.0
        let ny = (114.0 - y) / 80.5
        return CGPoint(x: padX + nx * wUsable, y: padY + ny * hUsable)
    }

    let pPeak = pt(110.0, 33.5)
    let pRight = pt(126.5, 48.0)
    let pJunc = pt(95.5, 63.0)
    let pTL = pt(51.0, 67.5)
    let pBL = pt(29.5, 114.0)
    let pBR = pt(64.0, 114.0)

    // Outer Glow for Constellation Lines
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: max(1.0, s * 0.03), color: CGColor(red: 0.4, green: 0.75, blue: 1.0, alpha: 0.75))
    ctx.setStrokeColor(CGColor(red: 0.65, green: 0.85, blue: 1.0, alpha: 0.9))
    ctx.setLineWidth(max(1.5, s * 0.012))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Triangle
    ctx.beginPath()
    ctx.move(to: pPeak)
    ctx.addLine(to: pRight)
    ctx.addLine(to: pJunc)
    ctx.closePath()
    ctx.strokePath()

    // Quad
    ctx.beginPath()
    ctx.move(to: pTL)
    ctx.addLine(to: pJunc)
    ctx.addLine(to: pBR)
    ctx.addLine(to: pBL)
    ctx.closePath()
    ctx.strokePath()
    ctx.restoreGState()

    // Inner bright lines
    ctx.setStrokeColor(CGColor(red: 0.88, green: 0.95, blue: 1.0, alpha: 0.95))
    ctx.setLineWidth(max(1.0, s * 0.007))
    ctx.beginPath()
    ctx.move(to: pPeak); ctx.addLine(to: pRight); ctx.addLine(to: pJunc); ctx.closePath()
    ctx.strokePath()
    ctx.beginPath()
    ctx.move(to: pTL); ctx.addLine(to: pJunc); ctx.addLine(to: pBR); ctx.addLine(to: pBL); ctx.closePath()
    ctx.strokePath()

    // 6. Stars
    func drawStarNode(p: CGPoint, radius: CGFloat, isVega: Bool) {
        // Outer halo
        ctx.saveGState()
        let haloRadius = radius * (isVega ? 3.8 : 2.6)
        let haloColors = [
            CGColor(red: 0.45, green: 0.80, blue: 1.0, alpha: isVega ? 0.6 : 0.4),
            CGColor(red: 0.30, green: 0.60, blue: 1.0, alpha: 0.0)
        ]
        let haloGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: haloColors as CFArray, locations: [0.0, 1.0])!
        ctx.drawRadialGradient(haloGrad, startCenter: p, startRadius: 0, endCenter: p, endRadius: haloRadius, options: [])
        ctx.restoreGState()

        // Vega diffraction spike cross flare
        if isVega && size >= 64 {
            ctx.saveGState()
            let flareLen = radius * 4.5
            let flareThickness = max(1.0, s * 0.004)
            ctx.setLineWidth(flareThickness)
            ctx.setStrokeColor(CGColor(red: 0.9, green: 0.96, blue: 1.0, alpha: 0.75))
            ctx.strokeLineSegments(between: [CGPoint(x: p.x - flareLen, y: p.y), CGPoint(x: p.x + flareLen, y: p.y)])
            ctx.strokeLineSegments(between: [CGPoint(x: p.x, y: p.y - flareLen), CGPoint(x: p.x, y: p.y + flareLen)])
            ctx.restoreGState()
        }

        // Star core (brilliant white)
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        ctx.setShadow(offset: .zero, blur: max(1.0, radius * 1.5), color: CGColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        ctx.restoreGState()
    }

    let starR = max(1.0, s * 0.016)
    let vegaR = max(1.5, s * 0.024)
    drawStarNode(p: pPeak, radius: vegaR, isVega: true)
    drawStarNode(p: pRight, radius: starR, isVega: false)
    drawStarNode(p: pJunc, radius: starR, isVega: false)
    drawStarNode(p: pTL, radius: starR, isVega: false)
    drawStarNode(p: pBL, radius: starR, isVega: false)
    drawStarNode(p: pBR, radius: starR, isVega: false)

    // 7. Subtle Rim Highlight
    let rimColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.28),
        CGColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 0.08),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.04)
    ]
    let rimGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: rimColors as CFArray, locations: [0.0, 0.4, 1.0])!
    ctx.setLineWidth(max(1.0, s * 0.003))
    ctx.addPath(squirclePath)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(rimGrad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    ctx.restoreGState()

    img.unlockFocus()
    return img
}

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let iconsetPath = outputDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = renderIcon(size: size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    let pngData = rep.representation(using: .png, properties: [:])!
    let filePath = iconsetPath + "/" + name
    try! pngData.write(to: URL(fileURLWithPath: filePath))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", outputDir + "/AppIcon.icns"]
try! process.run()
process.waitUntilExit()

try? FileManager.default.removeItem(atPath: iconsetPath)
print("[Icon] Generated \(outputDir)/AppIcon.icns")
