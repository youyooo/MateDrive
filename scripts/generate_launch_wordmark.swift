#!/usr/bin/env swift

import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: "MateDriveApp/Resources/Assets.xcassets/LaunchWordmark.imageset")
let variants = [
    (name: "LaunchMark.png", scale: 1),
    (name: "LaunchMark@2x.png", scale: 2),
    (name: "LaunchMark@3x.png", scale: 3),
]

for variant in variants {
    let width = 220 * variant.scale
    let height = 64 * variant.scale
    guard let bitmap = NSBitmapImageRep(
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
    ) else {
        fatalError("Unable to create launch wordmark bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let text = "MateDrive" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: CGFloat(39 * variant.scale), weight: .semibold),
        .foregroundColor: NSColor.black,
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(
            x: (CGFloat(width) - textSize.width) / 2,
            y: (CGFloat(height) - textSize.height) / 2
        ),
        withAttributes: attributes
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode launch wordmark")
    }
    try png.write(to: outputDirectory.appendingPathComponent(variant.name), options: .atomic)
}
