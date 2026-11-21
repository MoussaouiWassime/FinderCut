#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-icon.swift <output-icns-path>\n", stderr)
    exit(1)
}

let outputICNSPath = CommandLine.arguments[1]
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("FinderCutIcon-\(UUID().uuidString)")
let iconsetDir = tempDir.appendingPathComponent("AppIcon.iconset")

try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.shouldAntialias = true

    let inset = size * 0.095
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Subtle outer shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
    shadow.shadowBlurRadius = size * 0.04

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Finder-inspired blue/indigo gradient fill
    NSGraphicsContext.saveGraphicsState()
    path.addClip()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.17, green: 0.62, blue: 1.00, alpha: 1.0),
        NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.96, alpha: 1.0),
        NSColor(calibratedRed: 0.30, green: 0.28, blue: 0.88, alpha: 1.0),
    ])
    gradient?.draw(in: rect, angle: -55)

    // Subtle top light sheen
    let sheenGradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.24),
        NSColor(calibratedWhite: 1.0, alpha: 0.0),
    ])
    let sheenRect = NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height * 0.5)
    sheenGradient?.draw(in: sheenRect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Crisp inner highlight border
    NSColor(calibratedWhite: 1.0, alpha: 0.28).setStroke()
    path.lineWidth = max(1.0, size * 0.012)
    path.stroke()

    // White scissors SF Symbol
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: rect.width * 0.48, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

    if let symbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let symbolSize = symbol.size
        let targetMax = rect.width * 0.62
        let scale = min(targetMax / max(symbolSize.width, 1), targetMax / max(symbolSize.height, 1))
        let drawWidth = symbolSize.width * scale
        let drawHeight = symbolSize.height * scale
        let drawRect = NSRect(
            x: rect.midX - drawWidth / 2,
            y: rect.midY - drawHeight / 2,
            width: drawWidth,
            height: drawHeight
        )

        let symbolShadow = NSShadow()
        symbolShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.25)
        symbolShadow.shadowOffset = NSSize(width: 0, height: -size * 0.014)
        symbolShadow.shadowBlurRadius = size * 0.03

        NSGraphicsContext.saveGraphicsState()
        symbolShadow.set()
        symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, px) in entries {
    guard let pngData = renderIcon(pixelSize: px) else {
        fputs("Failed to render \(filename)\n", stderr)
        exit(1)
    }
    try pngData.write(to: iconsetDir.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputICNSPath]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(process.terminationStatus)
}
