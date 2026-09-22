#!/usr/bin/env swift

/**
 Generates every copy of the logo from the one SVG.

 The artwork lives at `design/logo/typoless-icon.svg` in the repository. This
 writes the app's icon set from it, and the website's copies too, so after a
 change to the logo nothing is left showing the old one. Paths are found from
 this file's own location, so it runs from any folder:

     swift app/Config/make-app-icon.swift
 */

import AppKit

let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Config
    .deletingLastPathComponent()  // app
    .deletingLastPathComponent()  // repository root

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let source = repository.appending(path: "design/logo/typoless-icon.svg")
let outputDirectory = repository.appending(path: "app/Typoless/Assets.xcassets/AppIcon.appiconset")
let website = repository.appending(path: "www")

/** macOS icon artwork sits inside its canvas rather than bleeding to the edges. */
let inset = 0.09

guard let artwork = NSImage(contentsOf: source) else {
    fatalError("Could not read \(source.path).")
}

/**
 Draws at exactly one pixel per point.

 Rendering through `NSImage.lockFocus` instead would pick up the main display's
 backing scale and silently produce artwork at twice the requested size.
 */
func icon(ofSize size: Int, inset: Double = inset) -> NSBitmapImageRep {
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
    NSGraphicsContext.current?.imageInterpolation = .high

    let frame = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side * inset, dy: side * inset)
    artwork.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)

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

/**
 The website uses the SVG itself wherever it can, and full-bleed renders where
 a browser or iOS wants a bitmap: the app's margin exists for the Dock, and on a
 page or a home screen it only makes the icon look small.
 */
let svg = try Data(contentsOf: source)

for copy in ["public/favicon.svg", "src/assets/logo.svg"] {
    try svg.write(to: website.appending(path: copy))
    print("copied \(copy)")
}

for (name, size) in [("public/favicon.png", 64), ("public/apple-touch-icon.png", 180)] {
    try writePNG(icon(ofSize: size, inset: 0), to: website.appending(path: name))
    print("wrote \(name)")
}
