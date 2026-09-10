#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

struct IconSlot {
    let idiom: String
    let size: String
    let scale: String
    let pixels: Int
    let filename: String
}

let slots: [IconSlot] = [
    .init(idiom: "iphone", size: "20x20", scale: "2x", pixels: 40, filename: "Icon-20@2x.png"),
    .init(idiom: "iphone", size: "20x20", scale: "3x", pixels: 60, filename: "Icon-20@3x.png"),
    .init(idiom: "iphone", size: "29x29", scale: "2x", pixels: 58, filename: "Icon-29@2x.png"),
    .init(idiom: "iphone", size: "29x29", scale: "3x", pixels: 87, filename: "Icon-29@3x.png"),
    .init(idiom: "iphone", size: "40x40", scale: "2x", pixels: 80, filename: "Icon-40@2x.png"),
    .init(idiom: "iphone", size: "40x40", scale: "3x", pixels: 120, filename: "Icon-40@3x.png"),
    .init(idiom: "iphone", size: "60x60", scale: "2x", pixels: 120, filename: "Icon-60@2x.png"),
    .init(idiom: "iphone", size: "60x60", scale: "3x", pixels: 180, filename: "Icon-60@3x.png"),
    .init(idiom: "ipad", size: "20x20", scale: "1x", pixels: 20, filename: "Icon-iPad-20.png"),
    .init(idiom: "ipad", size: "20x20", scale: "2x", pixels: 40, filename: "Icon-iPad-20@2x.png"),
    .init(idiom: "ipad", size: "29x29", scale: "1x", pixels: 29, filename: "Icon-iPad-29.png"),
    .init(idiom: "ipad", size: "29x29", scale: "2x", pixels: 58, filename: "Icon-iPad-29@2x.png"),
    .init(idiom: "ipad", size: "40x40", scale: "1x", pixels: 40, filename: "Icon-iPad-40.png"),
    .init(idiom: "ipad", size: "40x40", scale: "2x", pixels: 80, filename: "Icon-iPad-40@2x.png"),
    .init(idiom: "ipad", size: "76x76", scale: "1x", pixels: 76, filename: "Icon-iPad-76.png"),
    .init(idiom: "ipad", size: "76x76", scale: "2x", pixels: 152, filename: "Icon-iPad-76@2x.png"),
    .init(idiom: "ipad", size: "83.5x83.5", scale: "2x", pixels: 167, filename: "Icon-iPad-83.5@2x.png"),
    .init(idiom: "ios-marketing", size: "1024x1024", scale: "1x", pixels: 1024, filename: "Icon-1024.png")
]

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("MateDriveApp/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let existingFiles = try FileManager.default.contentsOfDirectory(
    at: outputDirectory,
    includingPropertiesForKeys: nil
)
for file in existingFiles where file.pathExtension == "png" {
    try FileManager.default.removeItem(at: file)
}

for slot in slots {
    let image = renderIcon(size: slot.pixels)
    let destination = outputDirectory.appendingPathComponent(slot.filename)
    try writePNG(image: image, to: destination)
}

let images = slots.map { slot -> [String: String] in
    [
        "filename": slot.filename,
        "idiom": slot.idiom,
        "scale": slot.scale,
        "size": slot.size
    ]
}
let contents: [String: Any] = [
    "images": images,
    "info": [
        "author": "xcode",
        "version": 1
    ]
]
let contentsData = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try contentsData.write(to: outputDirectory.appendingPathComponent("Contents.json"))

func renderIcon(size: Int) -> CGImage {
    let width = size
    let height = size
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    let rect = CGRect(x: 0, y: 0, width: width, height: height)

    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(red: 0.05, green: 0.09, blue: 0.13, alpha: 1).cgColor,
            NSColor(red: 0.02, green: 0.18, blue: 0.21, alpha: 1).cgColor,
            NSColor(red: 0.00, green: 0.47, blue: 0.55, alpha: 1).cgColor
        ] as CFArray,
        locations: [0, 0.58, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    let inset = CGFloat(size) * 0.16
    let roadRect = rect.insetBy(dx: inset, dy: inset)
    let roadPath = CGMutablePath()
    roadPath.move(to: CGPoint(x: roadRect.minX + roadRect.width * 0.22, y: roadRect.maxY))
    roadPath.addCurve(
        to: CGPoint(x: roadRect.midX, y: roadRect.midY + roadRect.height * 0.04),
        control1: CGPoint(x: roadRect.minX + roadRect.width * 0.30, y: roadRect.maxY - roadRect.height * 0.28),
        control2: CGPoint(x: roadRect.minX + roadRect.width * 0.34, y: roadRect.midY + roadRect.height * 0.20)
    )
    roadPath.addCurve(
        to: CGPoint(x: roadRect.maxX - roadRect.width * 0.16, y: roadRect.minY),
        control1: CGPoint(x: roadRect.maxX - roadRect.width * 0.12, y: roadRect.midY - roadRect.height * 0.14),
        control2: CGPoint(x: roadRect.maxX - roadRect.width * 0.22, y: roadRect.minY + roadRect.height * 0.18)
    )

    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(NSColor(red: 0.86, green: 0.96, blue: 0.97, alpha: 1).cgColor)
    context.setLineWidth(CGFloat(size) * 0.15)
    context.addPath(roadPath)
    context.strokePath()

    context.setStrokeColor(NSColor(red: 0.03, green: 0.17, blue: 0.20, alpha: 1).cgColor)
    context.setLineWidth(CGFloat(size) * 0.055)
    context.setLineDash(phase: 0, lengths: [CGFloat(size) * 0.10, CGFloat(size) * 0.08])
    context.addPath(roadPath)
    context.strokePath()
    context.setLineDash(phase: 0, lengths: [])

    let bolt = CGMutablePath()
    let cx = CGFloat(size) * 0.64
    let cy = CGFloat(size) * 0.55
    let s = CGFloat(size) * 0.30
    bolt.move(to: CGPoint(x: cx - s * 0.08, y: cy + s * 0.55))
    bolt.addLine(to: CGPoint(x: cx - s * 0.42, y: cy - s * 0.04))
    bolt.addLine(to: CGPoint(x: cx - s * 0.06, y: cy - s * 0.04))
    bolt.addLine(to: CGPoint(x: cx - s * 0.20, y: cy - s * 0.58))
    bolt.addLine(to: CGPoint(x: cx + s * 0.45, y: cy + s * 0.10))
    bolt.addLine(to: CGPoint(x: cx + s * 0.08, y: cy + s * 0.10))
    bolt.closeSubpath()

    context.setShadow(offset: CGSize(width: 0, height: CGFloat(size) * 0.02), blur: CGFloat(size) * 0.03, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    context.setFillColor(NSColor(red: 0.16, green: 0.86, blue: 0.78, alpha: 1).cgColor)
    context.addPath(bolt)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    let badgeRect = CGRect(
        x: CGFloat(size) * 0.17,
        y: CGFloat(size) * 0.17,
        width: CGFloat(size) * 0.24,
        height: CGFloat(size) * 0.24
    )
    context.setFillColor(NSColor(red: 0.94, green: 0.20, blue: 0.28, alpha: 1).cgColor)
    context.fillEllipse(in: badgeRect)

    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(CGFloat(size) * 0.025)
    let poleX = badgeRect.midX - badgeRect.width * 0.15
    context.move(to: CGPoint(x: poleX, y: badgeRect.minY + badgeRect.height * 0.24))
    context.addLine(to: CGPoint(x: poleX, y: badgeRect.maxY - badgeRect.height * 0.22))
    context.addLine(to: CGPoint(x: badgeRect.maxX - badgeRect.width * 0.20, y: badgeRect.maxY - badgeRect.height * 0.34))
    context.addLine(to: CGPoint(x: poleX, y: badgeRect.maxY - badgeRect.height * 0.46))
    context.strokePath()

    return context.makeImage()!
}

func writePNG(image: CGImage, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MateDriveIconGenerator", code: 1)
    }
    try data.write(to: url)
}
