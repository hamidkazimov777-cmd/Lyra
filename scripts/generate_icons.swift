import AppKit

func renderMenuBarIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    ctx.setFillColor(NSColor.black.cgColor)
    ctx.setStrokeColor(NSColor.black.cgColor)

    // Fit within size with standard menu bar padding (2.2pt horiz, 2.8pt vert on 18pt canvas)
    let padX = s * (2.2 / 18.0)
    let padY = s * (2.8 / 18.0)
    let wUsable = s - 2 * padX
    let hUsable = s - 2 * padY

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let nx = (x - 29.5) / 97.0
        let ny = (114.0 - y) / 80.5 // CoreGraphics origin bottom-left
        return CGPoint(x: padX + nx * wUsable, y: padY + ny * hUsable)
    }

    let pPeak = pt(110.0, 33.5)
    let pRight = pt(126.5, 48.0)
    let pJunc = pt(95.5, 63.0)
    let pTL = pt(51.0, 67.5)
    let pBL = pt(29.5, 114.0)
    let pBR = pt(64.0, 114.0)

    let stroke = s * (1.1 / 18.0)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Triangle (Vega, epsilon, zeta)
    ctx.beginPath()
    ctx.move(to: pPeak)
    ctx.addLine(to: pRight)
    ctx.addLine(to: pJunc)
    ctx.closePath()
    ctx.strokePath()

    // Parallelogram (delta, zeta, gamma, beta)
    ctx.beginPath()
    ctx.move(to: pTL)
    ctx.addLine(to: pJunc)
    ctx.addLine(to: pBR)
    ctx.addLine(to: pBL)
    ctx.closePath()
    ctx.strokePath()

    // Stars at vertices
    let r = s * (0.95 / 18.0)
    let rVega = s * (1.35 / 18.0)
    func dot(_ p: CGPoint, rad: CGFloat) {
        ctx.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
    }
    dot(pPeak, rad: rVega)
    dot(pRight, rad: r)
    dot(pJunc, rad: r)
    dot(pTL, rad: r)
    dot(pBL, rad: r)
    dot(pBR, rad: r)

    img.unlockFocus()
    img.isTemplate = true
    return img
}

func savePNG(image: NSImage, size: Int, path: String) {
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
    try! pngData.write(to: URL(fileURLWithPath: path))
}

let targetDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
try? FileManager.default.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

savePNG(image: renderMenuBarIcon(size: 18), size: 18, path: "\(targetDir)/MenuBarIcon.png")
savePNG(image: renderMenuBarIcon(size: 36), size: 36, path: "\(targetDir)/MenuBarIcon@2x.png")
print("[Icon] MenuBarIcon generated successfully in \(targetDir)")
