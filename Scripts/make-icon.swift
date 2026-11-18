#!/usr/bin/env swift
// Draws the app icon: the HomeView outline in white over the six classic rainbow stripes.
// Usage: swift Scripts/make-icon.swift <output.png> [width height]
// The glyph is laid out on a 1024 point square and scaled to the shorter side.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let design: CGFloat = 1024
let stripes: [(CGFloat, CGFloat, CGFloat)] = [
    (0x61, 0xBB, 0x46), (0xFD, 0xB8, 0x27), (0xF5, 0x82, 0x1F),
    (0xE0, 0x3A, 0x3E), (0x96, 0x3D, 0x97), (0x00, 0x9D, 0xDC),
]

let arguments = CommandLine.arguments
guard arguments.count == 2 || arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png> [width height]\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
let width = arguments.count == 4 ? Int(arguments[2]) ?? 1024 : 1024
let height = arguments.count == 4 ? Int(arguments[3]) ?? 1024 : 1024

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
// noneSkipLast keeps the PNG opaque, which App Store icons require.
let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

// Work in a top-left origin so the layout reads like the icon.
context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: 1, y: -1)

let stripeHeight = CGFloat(height) / CGFloat(stripes.count)
for (index, rgb) in stripes.enumerated() {
    context.setFillColor(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
    context.fill(CGRect(x: 0, y: CGFloat(index) * stripeHeight, width: CGFloat(width), height: stripeHeight + 1))
}

let scale = CGFloat(min(width, height)) / design
context.translateBy(x: (CGFloat(width) - design * scale) / 2, y: (CGFloat(height) - design * scale) / 2)
context.scaleBy(x: scale, y: scale)
let size = design

let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
context.setStrokeColor(white)
context.setFillColor(white)
context.setLineJoin(.round)
context.setLineCap(.round)
context.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.22))

let screen = CGRect(x: 222, y: 150, width: 580, height: 580)
let outerStroke: CGFloat = 44
let innerStroke: CGFloat = 18

context.beginTransparencyLayer(auxiliaryInfo: nil)

// Speaker base: drawn first so the screen outline sits in front of it.
let baseWidth: CGFloat = 330
let baseTop = screen.maxY
let baseBottom: CGFloat = 874
let baseLeft = size / 2 - baseWidth / 2
let baseRight = size / 2 + baseWidth / 2
let baseRadius: CGFloat = 54
let base = CGMutablePath()
base.move(to: CGPoint(x: baseLeft, y: baseTop))
base.addLine(to: CGPoint(x: baseLeft, y: baseBottom - baseRadius))
base.addQuadCurve(to: CGPoint(x: baseLeft + baseRadius, y: baseBottom), control: CGPoint(x: baseLeft, y: baseBottom))
base.addLine(to: CGPoint(x: baseRight - baseRadius, y: baseBottom))
base.addQuadCurve(to: CGPoint(x: baseRight, y: baseBottom - baseRadius), control: CGPoint(x: baseRight, y: baseBottom))
base.addLine(to: CGPoint(x: baseRight, y: baseTop))
context.setLineWidth(outerStroke)
context.addPath(base)
context.strokePath()

// Speaker grille hint.
context.setLineWidth(innerStroke)
context.move(to: CGPoint(x: baseLeft + 62, y: baseTop + 62))
context.addLine(to: CGPoint(x: baseRight - 62, y: baseTop + 62))
context.strokePath()

// Display.
context.setLineWidth(outerStroke)
context.addPath(CGPath(roundedRect: screen, cornerWidth: 128, cornerHeight: 128, transform: nil))
context.strokePath()

let glass = screen.insetBy(dx: 62, dy: 62)
context.setLineWidth(innerStroke)
context.addPath(CGPath(roundedRect: glass, cornerWidth: 74, cornerHeight: 74, transform: nil))
context.strokePath()

// Camera.
context.fillEllipse(in: CGRect(x: size / 2 - 9, y: screen.minY + 31 - 9, width: 18, height: 18))

context.endTransparencyLayer()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("could not create image\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("could not write \(output.path)\n".utf8))
    exit(1)
}
print("wrote \(output.path)")
