#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-dmg-bg.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let widthPt: CGFloat = 660
let heightPt: CGFloat = 400
let scale = 2
let pixelWidth = Int(widthPt) * scale
let pixelHeight = Int(heightPt) * scale

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to allocate bitmap\n", stderr)
    exit(1)
}

rep.size = NSSize(width: widthPt, height: heightPt)

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    exit(1)
}
NSGraphicsContext.current = ctx
ctx.shouldAntialias = true
ctx.imageInterpolation = .high

let fullRect = NSRect(x: 0, y: 0, width: widthPt, height: heightPt)

// Soft, clean light macOS gradient background
let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.975, green: 0.980, blue: 0.992, alpha: 1.0),
    NSColor(calibratedRed: 0.925, green: 0.938, blue: 0.965, alpha: 1.0),
])
bgGradient?.draw(in: fullRect, angle: -90)

// Subtle soft radial halo behind the arrow area
let centerY: CGFloat = heightPt - 195 // AppKit y-up vs Finder y-down (Finder y=195 -> AppKit y=205)

// Clean vector arrow between FinderCut.app (x=185) and Applications (x=475)
let arrowColor = NSColor(calibratedRed: 0.24, green: 0.44, blue: 0.92, alpha: 0.55)
arrowColor.setStroke()
arrowColor.setFill()

let shaftPath = NSBezierPath()
shaftPath.lineWidth = 3.5
shaftPath.lineCapStyle = .round
shaftPath.move(to: NSPoint(x: 292, y: centerY))
shaftPath.line(to: NSPoint(x: 364, y: centerY))
shaftPath.stroke()

let headPath = NSBezierPath()
headPath.lineWidth = 3.5
headPath.lineCapStyle = .round
headPath.lineJoinStyle = .round
headPath.move(to: NSPoint(x: 350, y: centerY + 12))
headPath.line(to: NSPoint(x: 366, y: centerY))
headPath.line(to: NSPoint(x: 350, y: centerY - 12))
headPath.stroke()

// Subtle title at top
let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1.0),
    .paragraphStyle: titleStyle,
]
let title = "FinderCut" as NSString
title.draw(in: NSRect(x: 0, y: heightPt - 62, width: widthPt, height: 30), withAttributes: titleAttrs)

// Instruction text at bottom (French, zero emojis)
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.40, alpha: 1.0),
    .paragraphStyle: titleStyle,
]
let subtitle = "Glissez FinderCut dans Applications pour l'installer" as NSString
subtitle.draw(in: NSRect(x: 0, y: 42, width: widthPt, height: 24), withAttributes: subtitleAttrs)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
