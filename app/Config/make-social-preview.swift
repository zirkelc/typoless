#!/usr/bin/env swift
//
// Draws the card GitHub, Slack and every chat app show when the repository is
// linked: 1280x640, the size GitHub asks for.
//
// Built from the same SVG as the app icon rather than exported by hand, so the
// card cannot end up showing an older logo than the app does.
//
//     swift Config/make-social-preview.swift
//
// GitHub has no API for the social preview, so the result has to be uploaded
// once by hand under Settings, General, Social preview.

import AppKit

let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let source = repository.appending(path: "design/logo/typoless-icon.svg")
let output = repository.appending(path: "design/logo/social-preview.png")

guard let artwork = NSImage(contentsOf: source) else {
    fatalError("Could not read \(source.path).")
}

let width = 1280
let height = 640

/** The icon's own background, so the card and the icon sit in the same world. */
let background = NSColor(srgbRed: 0.067, green: 0.067, blue: 0.075, alpha: 1)
let amber = NSColor(srgbRed: 0.949, green: 0.710, blue: 0.267, alpha: 1)

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else {
    fatalError("Could not allocate the bitmap")
}
rep.size = CGSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

background.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

/**
 The site's own serif, loaded from the file rather than from the system.

 Fraunces is what the page and the icon's T are drawn in, and it is not
 installed on any Mac by default, so the card would otherwise be lettered in
 something else and look like a different product. It is a variable font: the
 weight axis and the optical size axis both have to be set, because its default
 optical size is 9, drawn for captions, and using that at 104 points looks like
 a mistake nobody can name.
 */
let fontFile = repository.appending(path: "design/fonts/Fraunces-Variable.ttf")
let hasFraunces = CTFontManagerRegisterFontsForURL(fontFile as CFURL, .process, nil)

if !hasFraunces {
    print("warning: could not load \(fontFile.lastPathComponent), falling back to the system serif")
}

func serif(_ size: CGFloat, weight: CGFloat = 700, opticalSize: CGFloat = 144) -> NSFont {
    let system = NSFont.systemFont(ofSize: size, weight: weight >= 600 ? .bold : .regular)
    let fallback = NSFont(
        descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor,
        size: size
    ) ?? system

    guard hasFraunces else { return fallback }

    /** Four-character axis tags, which is how CoreText names a variation. */
    let weightAxis = 0x7767_6874
    let opticalAxis = 0x6F70_737A

    let descriptor = NSFontDescriptor(fontAttributes: [
        .name: "Fraunces",
        NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): [
            weightAxis: weight,
            opticalAxis: opticalSize,
        ],
    ])

    return NSFont(descriptor: descriptor, size: size) ?? fallback
}

let iconSide: CGFloat = 240
let left: CGFloat = 96
let gap: CGFloat = 56

let ink = NSColor(srgbRed: 0.953, green: 0.949, blue: 0.937, alpha: 1)
let muted = NSColor(srgbRed: 0.639, green: 0.635, blue: 0.659, alpha: 1)

let title = NSAttributedString(
    string: "Typoless",
    attributes: [.font: serif(104), .foregroundColor: ink, .kern: -2]
)

/**
 The slogan reads as the page does: the promise in the quiet colour, the part
 that is the whole point in the amber the app is built around.
 */
let tagline = NSMutableAttributedString(
    string: "Your words. ",
    attributes: [.font: serif(40, weight: 500, opticalSize: 72), .foregroundColor: muted]
)
tagline.append(
    NSAttributedString(
        string: "Just spelled right.",
        attributes: [.font: serif(40, weight: 500, opticalSize: 72), .foregroundColor: amber]
    )
)

let footnote = NSAttributedString(
    string: "On-device · macOS · works offline · open source",
    attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.435, green: 0.431, blue: 0.459, alpha: 1),
    ]
)

let lines = [title, tagline, footnote]
let spacing: [CGFloat] = [22, 30]
let block = lines.reduce(0) { $0 + $1.size().height } + spacing.reduce(0, +)

let textLeft = left + iconSide + gap
var cursor = (CGFloat(height) + block) / 2

for (index, line) in lines.enumerated() {
    cursor -= line.size().height
    line.draw(at: CGPoint(x: textLeft, y: cursor))
    if index < spacing.count { cursor -= spacing[index] }
}

artwork.draw(
    in: NSRect(x: left, y: (CGFloat(height) - iconSide) / 2, width: iconSide, height: iconSide),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

/**
 The squiggle that straightens, which is the icon's own idea: the mistake, then
 the fix. Along the bottom edge, so the card carries the thought without
 repeating the icon.
 */
let line = NSBezierPath()
let baseline: CGFloat = 56
let end = CGFloat(width) - left
let wave: CGFloat = 60

line.move(to: CGPoint(x: left, y: baseline))

var x = left
while x < left + wave * 4 {
    line.curve(
        to: CGPoint(x: x + wave, y: baseline),
        controlPoint1: CGPoint(x: x + wave * 0.25, y: baseline + 14),
        controlPoint2: CGPoint(x: x + wave * 0.75, y: baseline - 14)
    )
    x += wave
}

line.line(to: CGPoint(x: end, y: baseline))
line.lineWidth = 6
line.lineCapStyle = .round
amber.setStroke()
line.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the card")
}

try png.write(to: output)
print("wrote \(output.path) (\(width)x\(height))")

/**
 A raster copy of the icon for the README, where a relative SVG is at the mercy
 of whatever sanitiser the page is rendered through.
 */
let markSide = 256
guard
    let mark = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: markSide,
        pixelsHigh: markSide,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else {
    fatalError("Could not allocate the mark")
}
mark.size = CGSize(width: markSide, height: markSide)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mark)
NSGraphicsContext.current?.imageInterpolation = .high
artwork.draw(
    in: NSRect(x: 0, y: 0, width: markSide, height: markSide),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

let markURL = repository.appending(path: "design/logo/typoless-icon.png")
guard let markPNG = mark.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the mark")
}
try markPNG.write(to: markURL)
print("wrote \(markURL.path) (\(markSide)x\(markSide))")
