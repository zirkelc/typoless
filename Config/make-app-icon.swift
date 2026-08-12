#!/usr/bin/env swift

/**
 Generates the placeholder app icon set.

 A stand-in until the app has real artwork: an amber squircle carrying a bold
 "S". Run it from the repo root after changing anything here:

     swift Config/make-app-icon.swift
 */

import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDirectory = URL(fileURLWithPath: "Spellbee/Assets.xcassets/AppIcon.appiconset")

/** macOS icon artwork sits inside its canvas rather than bleeding to the edges. */
let inset = 0.09
/** Ratio Apple's squircle uses between corner radius and side length. */
let cornerRatio = 0.2237

/**
 Draws at exactly one pixel per point.

 Rendering through `NSImage.lockFocus` instead would pick up the main display's
 backing scale and silently produce artwork at twice the requested size.
 */
func icon(ofSize size: Int) -> NSBitmapImageRep {
    let side = CGFloat(size)

    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        fatalError("Could not allocate a \(size)x\(size) bitmap")
    }
    rep.size = CGSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let shape = CGRect(x: 0, y: 0, width: side, height: side).insetBy(
        dx: side * inset,
        dy: side * inset
    )
    let path = NSBezierPath(
        roundedRect: shape,
        xRadius: shape.width * cornerRatio,
        yRadius: shape.width * cornerRatio
    )
    path.addClip()

    let gradient = NSGradient(
        colors: [
            NSColor(srgbRed: 0.988, green: 0.780, blue: 0.302, alpha: 1),
            NSColor(srgbRed: 0.949, green: 0.545, blue: 0.114, alpha: 1),
        ]
    )
    gradient?.draw(in: shape, angle: -90)

    let glyphSize = shape.height * 0.62
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: glyphSize, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let glyph = NSAttributedString(string: "S", attributes: attributes)
    let glyphBounds = glyph.size()
    glyph.draw(
        at: NSPoint(
            x: shape.midX - glyphBounds.width / 2,
            y: shape.midY - glyphBounds.height / 2
        )
    )

    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

for size in sizes {
    let url = outputDirectory.appendingPathComponent("icon_\(size).png")
    try writePNG(icon(ofSize: size), to: url)
    print("wrote \(url.lastPathComponent)")
}
