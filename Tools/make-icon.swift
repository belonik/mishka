#!/usr/bin/env swift
//
//  make-icon.swift
//  Mishka
//
//  Renders the Mishka macOS app icon (1024×1024, sRGB, real alpha) as a PNG.
//
//      swift Tools/make-icon.swift <output.png>
//
//  Everything is drawn procedurally with CoreGraphics — no assets, no network,
//  no third-party dependencies, and pixel-identical on every run.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Command line

let usage = "usage: swift Tools/make-icon.swift <output.png>"

guard CommandLine.arguments.count >= 2, !CommandLine.arguments[1].isEmpty else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
if outputURL.deletingLastPathComponent().path != "/" {
    try? FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("make-icon: " + message + "\n").utf8))
    exit(1)
}

// MARK: - Canvas

let side: CGFloat = 1024
let px = Int(side)

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { fail("no sRGB colour space") }

guard let ctx = CGContext(
    data: nil,
    width: px,
    height: px,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fail("could not create bitmap context") }

ctx.setShouldAntialias(true)
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(colorSpace: colorSpace, components: [r, g, b, alpha])!
}

// MARK: - Geometry helpers

/// Superellipse |x/a|^n + |y/b|^n = 1, sampled from its parametric form.
/// n ≈ 5 gives the continuous-corner "squircle" silhouette of macOS icons.
func squirclePath(center: CGPoint, halfWidth a: CGFloat, halfHeight b: CGFloat,
                  n: CGFloat, samples: Int = 1440) -> CGPath {
    let path = CGMutablePath()
    let exponent = 2 / n
    for i in 0...samples {
        let t = CGFloat(i) / CGFloat(samples) * 2 * .pi
        let ct = cos(t)
        let st = sin(t)
        let x = center.x + a * (ct < 0 ? -1 : 1) * pow(abs(ct), exponent)
        let y = center.y + b * (st < 0 ? -1 : 1) * pow(abs(st), exponent)
        let point = CGPoint(x: x, y: y)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

/// Triangle with the apex pointing down and evenly rounded corners (bear nose).
func roundedNosePath(center: CGPoint, width w: CGFloat, height h: CGFloat,
                     corner: CGFloat) -> CGPath {
    let vertices = [
        CGPoint(x: center.x - w / 2, y: center.y + h / 2),   // top left
        CGPoint(x: center.x + w / 2, y: center.y + h / 2),   // top right
        CGPoint(x: center.x, y: center.y - h / 2)            // apex, pointing down
    ]

    var entry = [CGPoint](repeating: .zero, count: 3)
    var exit = [CGPoint](repeating: .zero, count: 3)
    for i in 0..<3 {
        let previous = vertices[(i + 2) % 3]
        let vertex = vertices[i]
        let next = vertices[(i + 1) % 3]
        let inLength = hypot(vertex.x - previous.x, vertex.y - previous.y)
        let outLength = hypot(next.x - vertex.x, next.y - vertex.y)
        // Never eat more than half of either adjacent edge.
        let r = min(corner, min(inLength, outLength) * 0.5)
        entry[i] = CGPoint(
            x: vertex.x + (previous.x - vertex.x) * (r / inLength),
            y: vertex.y + (previous.y - vertex.y) * (r / inLength)
        )
        exit[i] = CGPoint(
            x: vertex.x + (next.x - vertex.x) * (r / outLength),
            y: vertex.y + (next.y - vertex.y) * (r / outLength)
        )
    }

    let path = CGMutablePath()
    path.move(to: exit[0])
    for step in 1...3 {
        let i = step % 3
        path.addLine(to: entry[i])
        path.addQuadCurve(to: exit[i], control: vertices[i])
    }
    path.closeSubpath()
    return path
}

// MARK: - Palette

let amber = rgb(0xF4A742)        // top-left of the plate
let ember = rgb(0xEA7C31)        // midpoint, keeps the ramp from going muddy
let burnt = rgb(0xD64F28)        // bottom-right of the plate
let bearBrown = rgb(0x3A2418)    // glyph
let cream = rgb(0xF7E3C6)        // muzzle
let eyeCream = rgb(0xFFF1DC)     // eyes

// MARK: - Plate

// Apple's macOS icon grid: the artwork is 824 pt tall inside a 1024 pt canvas.
let artwork = side * (824.0 / 1024.0)
let plateRect = CGRect(
    x: (side - artwork) / 2,
    y: (side - artwork) / 2,
    width: artwork,
    height: artwork
)
let plateCenter = CGPoint(x: plateRect.midX, y: plateRect.midY)
let plate = squirclePath(
    center: plateCenter,
    halfWidth: plateRect.width / 2,
    halfHeight: plateRect.height / 2,
    n: 5.0
)

// Soft drop shadow: the plate is inset by ~100 px, so a <=70 px spread never
// reaches the canvas edge and can never be clipped.
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -22),
    blur: 50,
    color: rgb(0x000000, 0.28)
)
ctx.addPath(plate)
ctx.setFillColor(burnt)
ctx.fillPath()
ctx.restoreGState()

// MARK: - Plate fill

ctx.saveGState()
ctx.addPath(plate)
ctx.clip()

// Diagonal gradient: top-left amber -> bottom-right burnt orange.
let bodyGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [amber, ember, burnt] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(
    bodyGradient,
    start: CGPoint(x: plateRect.minX, y: plateRect.maxY),
    end: CGPoint(x: plateRect.maxX, y: plateRect.minY),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// "Lit from above": soft white wash over the top 40 %.
let highlight = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0.0)] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    highlight,
    start: CGPoint(x: plateCenter.x, y: plateRect.maxY),
    end: CGPoint(x: plateCenter.x, y: plateRect.maxY - plateRect.height * 0.40),
    options: []
)

// Soft contact shading along the bottom edge so the plate reads as a solid.
let bounce = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0x4A1A0C, 0.16), rgb(0x4A1A0C, 0.0)] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    bounce,
    start: CGPoint(x: plateCenter.x, y: plateRect.minY),
    end: CGPoint(x: plateCenter.x, y: plateRect.minY + plateRect.height * 0.22),
    options: []
)

// Crisp inner rim: half the stroke is clipped away, leaving a 3 px inner edge.
ctx.addPath(plate)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.14))
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

// MARK: - Bear glyph

let R: CGFloat = 214                        // head radius
let headCenter = CGPoint(x: plateCenter.x, y: plateCenter.y - 13)
let earRadius = 0.50 * R
let earAngle: CGFloat = 46 * .pi / 180      // from vertical
let earDistance = 0.90 * R
let earOffset = CGPoint(x: sin(earAngle) * earDistance, y: cos(earAngle) * earDistance)

// Silhouette: one head circle + two ear circles, unioned by non-zero winding.
let silhouette = CGMutablePath()
silhouette.addEllipse(in: CGRect(
    x: headCenter.x - R, y: headCenter.y - R, width: 2 * R, height: 2 * R
))
for sign in [CGFloat(-1), CGFloat(1)] {
    let c = CGPoint(x: headCenter.x + sign * earOffset.x, y: headCenter.y + earOffset.y)
    silhouette.addEllipse(in: CGRect(
        x: c.x - earRadius, y: c.y - earRadius,
        width: 2 * earRadius, height: 2 * earRadius
    ))
}

ctx.saveGState()
ctx.addPath(silhouette)
ctx.setFillColor(bearBrown)
ctx.fillPath()
ctx.restoreGState()

// Muzzle: soft cream oval low on the face.
let muzzleW = 0.94 * R
let muzzleH = 0.57 * R
let muzzleCenter = CGPoint(x: headCenter.x, y: headCenter.y - 0.37 * R)
ctx.setFillColor(cream)
ctx.fillEllipse(in: CGRect(
    x: muzzleCenter.x - muzzleW / 2, y: muzzleCenter.y - muzzleH / 2,
    width: muzzleW, height: muzzleH
))

// Nose: wide rounded triangle hanging from the top of the muzzle.
let noseW = 0.38 * R
let noseH = 0.28 * R
ctx.setFillColor(bearBrown)
ctx.addPath(roundedNosePath(
    center: CGPoint(x: headCenter.x, y: headCenter.y - 0.21 * R),
    width: noseW, height: noseH,
    corner: noseH * 0.30
))
ctx.fillPath()

// Eyes: two generous cream dots, kept clear of the muzzle so they survive 32 px.
let eyeRadius = 0.145 * R
let eyeSpacing = 0.30 * R
let eyeY = headCenter.y + 0.225 * R
ctx.setFillColor(eyeCream)
for sign in [CGFloat(-1), CGFloat(1)] {
    let c = CGPoint(x: headCenter.x + sign * eyeSpacing, y: eyeY)
    ctx.fillEllipse(in: CGRect(
        x: c.x - eyeRadius, y: c.y - eyeRadius,
        width: 2 * eyeRadius, height: 2 * eyeRadius
    ))
}

// MARK: - Write PNG

guard let image = ctx.makeImage() else { fail("could not render image") }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: side, height: side)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fail("could not encode PNG")
}
do {
    try png.write(to: outputURL)
} catch {
    fail("could not write \(outputURL.path): \(error.localizedDescription)")
}

print("make-icon: wrote \(px)×\(px) PNG to \(outputURL.path)")
