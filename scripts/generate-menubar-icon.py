#!/usr/bin/env python3
"""Generate template PNGs for the Lyra menu bar icon."""
import subprocess
import sys
import os
import tempfile

SWIFT_RENDERER = '''
import AppKit

func render(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    // Template image: rendered in black, tinted by NSStatusBar in light/dark mode.
    ctx.setFillColor(.black)
    ctx.setStrokeColor(.black)

    let micWidth = s * 0.36
    let micHeight = s * 0.46
    let micX = (s - micWidth) / 2
    let micY = s * 0.40
    let micRect = CGRect(x: micX, y: micY, width: micWidth, height: micHeight)
    let micPath = CGPath(roundedRect: micRect, cornerWidth: micWidth / 2, cornerHeight: micWidth / 2, transform: nil)
    ctx.addPath(micPath)
    ctx.fillPath()

    // Stand arc
    let arcCenter = CGPoint(x: s / 2, y: s * 0.40)
    let arcRadius = s * 0.22
    let arcPath = CGMutablePath()
    arcPath.addArc(center: arcCenter, radius: arcRadius, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false)
    ctx.addPath(arcPath)
    ctx.setLineWidth(s * 0.07)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Stand line
    let standWidth = s * 0.07
    let standX = (s - standWidth) / 2
    let standRect = CGRect(x: standX, y: s * 0.14, width: standWidth, height: s * 0.12)
    let standPath = CGPath(roundedRect: standRect, cornerWidth: standWidth / 2, cornerHeight: standWidth / 2, transform: nil)
    ctx.addPath(standPath)
    ctx.fillPath()

    // Base
    let baseWidth = s * 0.38
    let baseHeight = s * 0.07
    let baseRect = CGRect(x: (s - baseWidth) / 2, y: s * 0.10, width: baseWidth, height: baseHeight)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: baseHeight / 2, cornerHeight: baseHeight / 2, transform: nil)
    ctx.addPath(basePath)
    ctx.fillPath()

    img.unlockFocus()
    img.isTemplate = true
    return img
}

let outputDir = CommandLine.arguments[1]
let configs = [(18, "MenuBarIcon.png"), (36, "MenuBarIcon@2x.png")]

for (size, name) in configs {
    let image = render(size: size)
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
    try! pngData.write(to: URL(fileURLWithPath: outputDir + "/" + name))
}

print("[Icon] Generated menu bar icons")
'''

def generate(resources_dir):
    os.makedirs(resources_dir, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', suffix='.swift', delete=False) as f:
        f.write(SWIFT_RENDERER)
        swift_path = f.name
    try:
        binary_path = swift_path.replace('.swift', '')
        subprocess.run(['swiftc', swift_path, '-framework', 'AppKit', '-o', binary_path], check=True, capture_output=True)
        subprocess.run([binary_path, resources_dir], check=True)
    finally:
        os.unlink(swift_path)
        if os.path.exists(binary_path):
            os.unlink(binary_path)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: generate-menubar-icon.py <Resources_dir>")
        sys.exit(1)
    generate(sys.argv[1])
