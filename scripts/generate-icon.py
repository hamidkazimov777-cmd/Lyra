#!/usr/bin/env python3
"""Generate the Lyra app icon: microphone + constellation motif."""
import subprocess
import sys
import os
import tempfile

SWIFT_ICON_RENDERER = '''
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
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.224
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Deep space gradient
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bgColors = [
        CGColor(red: 0.04, green: 0.05, blue: 0.16, alpha: 1.0),
        CGColor(red: 0.10, green: 0.08, blue: 0.26, alpha: 1.0),
        CGColor(red: 0.06, green: 0.12, blue: 0.28, alpha: 1.0),
    ]
    let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0.0, 0.6, 1.0])!
    ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    ctx.restoreGState()

    // Soft vignette
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let vignetteColors = [
        CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
        CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.35),
    ] as CFArray
    let vignetteGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: vignetteColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(vignetteGradient, startCenter: CGPoint(x: s * 0.5, y: s * 0.5), startRadius: 0, endCenter: CGPoint(x: s * 0.5, y: s * 0.5), endRadius: s * 0.65, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Accent gradient: cyan → violet
    let accentColors = [
        CGColor(red: 0.35, green: 0.78, blue: 1.0, alpha: 1.0),   // cyan
        CGColor(red: 0.55, green: 0.45, blue: 1.0, alpha: 1.0),   // violet
    ]
    let accentGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: accentColors as CFArray, locations: [0.0, 1.0])!

    func fillWithAccent(_ path: CGPath) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let bounds = path.boundingBox
        ctx.drawLinearGradient(accentGradient, start: CGPoint(x: bounds.midX, y: bounds.maxY), end: CGPoint(x: bounds.midX, y: bounds.minY), options: [])
        ctx.restoreGState()
    }

    // Constellation dots (Lyra motif) — placed around the microphone
    let constellationDots: [(CGFloat, CGFloat, CGFloat)] = [
        (0.28, 0.72, 0.028),
        (0.22, 0.60, 0.018),
        (0.34, 0.62, 0.022),
        (0.30, 0.52, 0.016),
        (0.72, 0.72, 0.028),
        (0.78, 0.60, 0.018),
        (0.66, 0.62, 0.022),
        (0.70, 0.52, 0.016),
    ]

    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 0.45))
    ctx.setLineWidth(s * 0.006)
    ctx.setLineCap(.round)
    // Left constellation lines
    ctx.move(to: CGPoint(x: s * 0.28, y: s * 0.72))
    ctx.addLine(to: CGPoint(x: s * 0.22, y: s * 0.60))
    ctx.addLine(to: CGPoint(x: s * 0.34, y: s * 0.62))
    ctx.addLine(to: CGPoint(x: s * 0.30, y: s * 0.52))
    // Right constellation lines
    ctx.move(to: CGPoint(x: s * 0.72, y: s * 0.72))
    ctx.addLine(to: CGPoint(x: s * 0.78, y: s * 0.60))
    ctx.addLine(to: CGPoint(x: s * 0.66, y: s * 0.62))
    ctx.addLine(to: CGPoint(x: s * 0.70, y: s * 0.52))
    ctx.strokePath()

    for (nx, ny, nr) in constellationDots {
        let dotPath = CGPath(ellipseIn: CGRect(x: s * nx - s * nr, y: s * ny - s * nr, width: s * nr * 2, height: s * nr * 2), transform: nil)
        fillWithAccent(dotPath)
    }
    ctx.restoreGState()

    // Waveform bars
    let barWidth = s * 0.040
    let barRadius = barWidth / 2
    let leftBars: [(x: CGFloat, height: CGFloat)] = [
        (0.17, 0.16),
        (0.225, 0.32),
        (0.28, 0.22),
    ]
    let rightBars: [(x: CGFloat, height: CGFloat)] = [
        (0.72, 0.22),
        (0.775, 0.32),
        (0.83, 0.16),
    ]
    for bar in leftBars + rightBars {
        let x = s * bar.x - barWidth / 2
        let h = s * bar.height
        let y = (s - h) / 2 + s * 0.02
        let rect = CGRect(x: x, y: y, width: barWidth, height: h)
        let path = CGPath(roundedRect: rect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
        ctx.setAlpha(0.75)
        fillWithAccent(path)
        ctx.setAlpha(1.0)
    }

    // Microphone body
    let micWidth = s * 0.13
    let micHeight = s * 0.30
    let micX = (s - micWidth) / 2
    let micY = s * 0.44
    let micRect = CGRect(x: micX, y: micY, width: micWidth, height: micHeight)
    let micPath = CGPath(roundedRect: micRect, cornerWidth: micWidth / 2, cornerHeight: micWidth / 2, transform: nil)
    fillWithAccent(micPath)

    // Mic stand arc
    let arcCenter = CGPoint(x: s / 2, y: s * 0.44)
    let arcRadius = s * 0.11
    ctx.saveGState()
    let arcPath = CGMutablePath()
    arcPath.addArc(center: arcCenter, radius: arcRadius, startAngle: .pi * 0.05, endAngle: .pi * 0.95, clockwise: false)
    ctx.addPath(arcPath)
    ctx.setLineWidth(s * 0.035)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 0.35, green: 0.78, blue: 1.0, alpha: 1.0))
    ctx.strokePath()
    ctx.restoreGState()

    // Mic stand (vertical line)
    let standWidth = s * 0.035
    let standX = (s - standWidth) / 2
    let standY = s * 0.24
    let standHeight = s * 0.09
    let standRect = CGRect(x: standX, y: standY, width: standWidth, height: standHeight)
    let standPath = CGPath(roundedRect: standRect, cornerWidth: standWidth / 2, cornerHeight: standWidth / 2, transform: nil)
    fillWithAccent(standPath)

    // Mic base
    let baseWidth = s * 0.14
    let baseHeight = s * 0.035
    let baseX = (s - baseWidth) / 2
    let baseY = s * 0.22
    let baseRect = CGRect(x: baseX, y: baseY, width: baseWidth, height: baseHeight)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: baseHeight / 2, cornerHeight: baseHeight / 2, transform: nil)
    fillWithAccent(basePath)

    // Outer subtle glow ring
    ctx.saveGState()
    let ringPath = CGPath(ellipseIn: CGRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84), transform: nil)
    ctx.addPath(ringPath)
    ctx.setStrokeColor(CGColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 0.18))
    ctx.setLineWidth(s * 0.01)
    ctx.strokePath()
    ctx.restoreGState()

    img.unlockFocus()
    return img
}

let outputDir = CommandLine.arguments[1]

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
print("[Icon] Generated \\(outputDir)/AppIcon.icns")
'''

def generate_icon(resources_dir):
    """Render the icon using a Swift script that uses AppKit/CoreGraphics."""
    os.makedirs(resources_dir, exist_ok=True)

    with tempfile.NamedTemporaryFile(mode='w', suffix='.swift', delete=False) as f:
        f.write(SWIFT_ICON_RENDERER)
        swift_path = f.name

    try:
        binary_path = swift_path.replace('.swift', '')
        subprocess.run([
            'swiftc', swift_path,
            '-framework', 'AppKit',
            '-o', binary_path
        ], check=True, capture_output=True)

        subprocess.run([binary_path, resources_dir], check=True)
    finally:
        os.unlink(swift_path)
        if os.path.exists(binary_path):
            os.unlink(binary_path)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: generate-icon.py <Resources_dir>")
        sys.exit(1)
    generate_icon(sys.argv[1])
